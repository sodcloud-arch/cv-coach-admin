-- ARCH-1.0 · F1.M1.S6 — Base multi-tenant permission matrix
-- Establishes explicit Organization role capabilities and closes raw roster/config visibility gaps.

create or replace function private.current_org_role_v1(
  p_organization_id uuid,
  p_user_id uuid default auth.uid()
)
returns public.organization_member_role
language sql
stable
security definer
set search_path to ''
as $function$
  select om.role
  from public.organization_members om
  where om.organization_id=p_organization_id
    and om.user_id=p_user_id
    and om.status='active'::public.organization_member_status
  limit 1
$function$;

create or replace function private.can_view_org_member_v1(
  p_organization_id uuid,
  p_member_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    auth.role()='service_role'
    or private.is_platform_admin()
    or private.is_org_admin(p_organization_id)
    or p_member_user_id=(select auth.uid()),
    false
  )
$function$;

create or replace function private.can_view_coach_profile_v1(
  p_organization_id uuid,
  p_coach_user_id uuid,
  p_status public.coach_profile_status
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    auth.role()='service_role'
    or private.is_platform_admin()
    or private.is_org_admin(p_organization_id)
    or (
      p_coach_user_id=(select auth.uid())
      and private.is_org_member(p_organization_id)
    )
    or (
      p_status='active'::public.coach_profile_status
      and private.is_org_member(p_organization_id)
    ),
    false
  )
$function$;

create or replace function public.get_my_organization_context_v1(
  p_organization_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_uid uuid:=auth.uid();
  v_org public.organizations%rowtype;
  v_member public.organization_members%rowtype;
  v_role public.organization_member_role;
  v_is_platform_admin boolean:=false;
  v_is_org_admin boolean:=false;
  v_is_active_member boolean:=false;
begin
  if p_organization_id is null then
    raise exception 'organization_id is required';
  end if;

  if auth.role()<>'service_role' and v_uid is null then
    raise exception 'Authentication required';
  end if;

  select * into v_org
  from public.organizations o
  where o.id=p_organization_id;

  if not found then
    raise exception 'Organization not found';
  end if;

  v_is_platform_admin:=case
    when auth.role()='service_role' then true
    else private.is_platform_admin()
  end;

  if v_uid is not null then
    select * into v_member
    from public.organization_members om
    where om.organization_id=p_organization_id
      and om.user_id=v_uid;

    v_is_active_member:=found and v_member.status='active'::public.organization_member_status;
    if v_is_active_member then
      v_role:=v_member.role;
    end if;
  end if;

  v_is_org_admin:=v_is_platform_admin
    or (
      v_is_active_member
      and v_role in (
        'owner'::public.organization_member_role,
        'org_admin'::public.organization_member_role
      )
    );

  if not (v_is_platform_admin or v_is_active_member) then
    raise exception 'Organization outside actor scope';
  end if;

  return jsonb_build_object(
    'organization',
      jsonb_build_object(
        'id',v_org.id,
        'slug',v_org.slug,
        'display_name',v_org.display_name,
        'status',v_org.status,
        'locale',v_org.locale,
        'timezone',v_org.timezone,
        'currency',v_org.currency,
        'branding_config',v_org.branding_config,
        'feature_flags',v_org.feature_flags
      ),
    'membership',
      case
        when v_uid is null then null
        else jsonb_build_object(
          'user_id',v_uid,
          'role',v_member.role,
          'status',v_member.status,
          'joined_at',v_member.joined_at
        )
      end,
    'permissions',
      jsonb_build_object(
        'is_platform_admin',v_is_platform_admin,
        'is_org_admin',v_is_org_admin,
        'can_manage_organization',v_is_org_admin,
        'can_view_all_members',v_is_org_admin,
        'can_manage_members',v_is_org_admin,
        'can_manage_coaches',v_is_org_admin,
        'can_manage_all_clients',v_is_org_admin,
        'can_manage_assignments',v_is_org_admin,
        'can_manage_assigned_clients',v_is_org_admin or v_role='coach'::public.organization_member_role,
        'can_submit_client_state',v_role='client'::public.organization_member_role,
        'can_view_active_coach_directory',v_is_platform_admin or v_is_active_member
      ),
    'admin',
      case
        when v_is_org_admin then jsonb_build_object(
          'legal_name',v_org.legal_name,
          'owner_user_id',v_org.owner_user_id,
          'plan_id',v_org.plan_id,
          'billing_account_configured',v_org.billing_account_id is not null,
          'settings',v_org.settings
        )
        else null
      end,
    'version','F1.M1.S6_PERMISSION_CONTEXT_V1'
  );
end;
$function$;

-- Raw Organization rows contain billing/settings fields. Keep raw-table access admin-only;
-- coaches/clients consume the safe context RPC above.
drop policy if exists organizations_select_v1 on public.organizations;
drop policy if exists organizations_select_v2 on public.organizations;
create policy organizations_select_v2
on public.organizations
for select
to authenticated
using (private.is_org_admin(id));

-- Membership roster is administrative data. Non-admin members can see only their own row.
drop policy if exists organization_members_select_v1 on public.organization_members;
drop policy if exists organization_members_select_v2 on public.organization_members;
create policy organization_members_select_v2
on public.organization_members
for select
to authenticated
using (private.can_view_org_member_v1(organization_id,user_id));

-- All active Organization members may see the active coach directory.
-- Inactive/suspended/archived coach profiles remain visible only to admins or the profile owner.
drop policy if exists coach_profiles_select_v1 on public.coach_profiles;
drop policy if exists coach_profiles_select_v2 on public.coach_profiles;
create policy coach_profiles_select_v2
on public.coach_profiles
for select
to authenticated
using (
  private.can_view_coach_profile_v1(
    organization_id,user_id,status
  )
);

drop policy if exists coach_profile_disciplines_select_v2 on public.coach_profile_disciplines;
drop policy if exists coach_profile_disciplines_select_v3 on public.coach_profile_disciplines;
create policy coach_profile_disciplines_select_v3
on public.coach_profile_disciplines
for select
to authenticated
using (
  exists(
    select 1
    from public.coach_profiles cp
    where cp.organization_id=coach_profile_disciplines.organization_id
      and cp.id=coach_profile_disciplines.coach_profile_id
      and private.can_view_coach_profile_v1(
        cp.organization_id,cp.user_id,cp.status
      )
  )
);

drop policy if exists coach_credentials_select_v2 on public.coach_credentials;
drop policy if exists coach_credentials_select_v3 on public.coach_credentials;
create policy coach_credentials_select_v3
on public.coach_credentials
for select
to authenticated
using (
  private.is_org_admin(organization_id)
  or (
    private.is_org_member(organization_id)
    and exists(
      select 1
      from public.coach_profiles cp
      where cp.organization_id=coach_credentials.organization_id
        and cp.id=coach_credentials.coach_profile_id
        and cp.user_id=(select auth.uid())
    )
  )
);

revoke all on function private.current_org_role_v1(uuid,uuid) from public,anon;
revoke all on function private.can_view_org_member_v1(uuid,uuid) from public,anon;
revoke all on function private.can_view_coach_profile_v1(uuid,uuid,public.coach_profile_status) from public,anon;
grant execute on function private.current_org_role_v1(uuid,uuid) to authenticated,service_role;
grant execute on function private.can_view_org_member_v1(uuid,uuid) to authenticated,service_role;
grant execute on function private.can_view_coach_profile_v1(uuid,uuid,public.coach_profile_status) to authenticated,service_role;

revoke all on function public.get_my_organization_context_v1(uuid) from public,anon;
grant execute on function public.get_my_organization_context_v1(uuid) to authenticated,service_role;

comment on function public.get_my_organization_context_v1(uuid)
is 'F1.M1.S6 canonical permission context. Returns safe tenant context to active members and admin-only tenant settings separately.';

comment on function private.can_view_org_member_v1(uuid,uuid)
is 'F1.M1.S6 roster visibility: org admins see the roster; non-admin members see only their own membership.';

comment on function private.can_view_coach_profile_v1(uuid,uuid,public.coach_profile_status)
is 'F1.M1.S6 coach directory visibility: active coach profiles are visible to active members; inactive profiles are admin/self only.';
