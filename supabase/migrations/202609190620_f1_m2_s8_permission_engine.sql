-- F1.M2.S8 — versioned hybrid RBAC + resource-scope permission engine
-- Authorization chain:
-- identity -> active membership -> active tenant roles -> versioned capability rule
-- -> resource.organization_id -> ownership/assignment/self scope.
-- PLATFORM_SUPERADMIN and SupportContext remain a separate audited plane (F1.M2.S4).

create table if not exists public.permission_matrix_versions (
  version integer primary key,
  code text not null unique,
  sealed boolean not null default false,
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  constraint permission_matrix_versions_positive check (version>0),
  constraint permission_matrix_versions_code_check
    check (char_length(btrim(code)) between 3 and 120),
  constraint permission_matrix_versions_metadata_object
    check (jsonb_typeof(metadata)='object')
);

create table if not exists public.permission_capabilities (
  capability text primary key,
  resource_type text not null,
  description text not null,
  introduced_version integer not null
    references public.permission_matrix_versions(version),
  created_at timestamptz not null default now(),
  constraint permission_capabilities_name_check
    check (
      capability ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'
    ),
  constraint permission_capabilities_resource_type_check
    check (resource_type in (
      'organization','member','coach_profile',
      'client','program','workout_session'
    )),
  constraint permission_capabilities_description_check
    check (char_length(btrim(description)) between 8 and 500)
);

create table if not exists public.permission_role_rules (
  matrix_version integer not null
    references public.permission_matrix_versions(version) on delete restrict,
  role public.organization_member_role not null,
  capability text not null
    references public.permission_capabilities(capability) on delete restrict,
  scope text not null,
  created_at timestamptz not null default now(),
  primary key(matrix_version,role,capability,scope),
  constraint permission_role_rules_scope_check
    check (scope in (
      'tenant',
      'member_any','member_self',
      'coach_any','coach_self','coach_active_member',
      'client_any','client_assigned','client_self',
      'program_any','program_assigned','program_self_published',
      'workout_any','workout_assigned','workout_self'
    ))
);

alter table public.permission_matrix_versions enable row level security;
alter table public.permission_capabilities enable row level security;
alter table public.permission_role_rules enable row level security;

revoke all on public.permission_matrix_versions from public,anon,authenticated;
revoke all on public.permission_capabilities from public,anon,authenticated;
revoke all on public.permission_role_rules from public,anon,authenticated;
grant select,insert,update,delete on public.permission_matrix_versions to service_role;
grant select,insert,update,delete on public.permission_capabilities to service_role;
grant select,insert,update,delete on public.permission_role_rules to service_role;

create or replace function private.guard_sealed_permission_matrix_rule_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_version integer:=coalesce(new.matrix_version,old.matrix_version);
  v_sealed boolean:=false;
begin
  select v.sealed into v_sealed
  from public.permission_matrix_versions v
  where v.version=v_version;

  if coalesce(v_sealed,false) then
    raise exception 'permission matrix version % is sealed',v_version;
  end if;

  return coalesce(new,old);
end;
$function$;

drop trigger if exists permission_role_rules_sealed_v1
  on public.permission_role_rules;
create trigger permission_role_rules_sealed_v1
before insert or update or delete on public.permission_role_rules
for each row execute function private.guard_sealed_permission_matrix_rule_v1();

create or replace function private.guard_sealed_permission_matrix_version_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if old.sealed then
    raise exception 'sealed permission matrix versions are immutable';
  end if;
  return new;
end;
$function$;

drop trigger if exists permission_matrix_versions_sealed_v1
  on public.permission_matrix_versions;
create trigger permission_matrix_versions_sealed_v1
before update or delete on public.permission_matrix_versions
for each row execute function private.guard_sealed_permission_matrix_version_v1();

insert into public.permission_matrix_versions(version,code,sealed,metadata)
values(
  1,
  'F1.M2.S8_PERMISSION_MATRIX_V1',
  false,
  jsonb_build_object(
    'model','RBAC+resource_scope',
    'deny_by_default',true,
    'feature_entitlements_separate',true,
    'platform_superadmin_separate',true
  )
)
on conflict(version) do nothing;

insert into public.permission_capabilities(
  capability,resource_type,description,introduced_version
)
values
  ('organization.view','organization','View the active tenant organization shell and tenant-scoped metadata.',1),
  ('organization.members.manage','organization','Manage tenant members and their tenant role assignments.',1),
  ('organization.coaches.manage','organization','Manage coach identities, profiles and assignments inside the tenant.',1),
  ('organization.clients.manage','organization','Manage client identities and client lifecycle inside the tenant.',1),
  ('organization.configuration.manage','organization','Manage operational tenant configuration that is not ownership or billing.',1),
  ('organization.billing.manage','organization','Manage tenant billing and financial administration.',1),
  ('organization.ownership.transfer','organization','Transfer tenant ownership through the dedicated ownership flow.',1),
  ('organization.custom_domain.manage','organization','Manage tenant custom-domain ownership configuration.',1),
  ('permissions.manage','organization','Manage tenant-scoped role assignments and permission-bearing capabilities.',1),
  ('member.view','member','View a tenant member subject to role and self scope.',1),
  ('coach_profile.view','coach_profile','View a coach professional profile in the tenant.',1),
  ('coach_profile.manage','coach_profile','Manage a coach professional profile in the tenant.',1),
  ('coach.scope.expand','coach_profile','Grant or remove an audited expanded coach client scope.',1),
  ('client.view','client','View a client according to self, assignment or tenant-admin scope.',1),
  ('client.manage','client','Manage a client according to assignment or tenant-admin scope.',1),
  ('client.self_profile.update','client','Update the allow-listed fields of the authenticated client profile.',1),
  ('program.view','program','View a program according to tenant role, assignment or published self scope.',1),
  ('program.manage','program','Manage a program according to tenant-admin or assigned-coach scope.',1),
  ('workout.view','workout_session','View a workout session according to tenant, assignment or self scope.',1),
  ('workout.manage','workout_session','Edit a workout session according to tenant, assignment or self scope.',1)
on conflict(capability) do nothing;

insert into public.permission_role_rules(
  matrix_version,role,capability,scope
)
values
  -- OWNER: tenant administration + unrestricted tenant resources.
  (1,'owner','organization.view','tenant'),
  (1,'owner','organization.members.manage','tenant'),
  (1,'owner','organization.coaches.manage','tenant'),
  (1,'owner','organization.clients.manage','tenant'),
  (1,'owner','organization.configuration.manage','tenant'),
  (1,'owner','organization.billing.manage','tenant'),
  (1,'owner','organization.ownership.transfer','tenant'),
  (1,'owner','organization.custom_domain.manage','tenant'),
  (1,'owner','permissions.manage','tenant'),
  (1,'owner','member.view','member_any'),
  (1,'owner','coach_profile.view','coach_any'),
  (1,'owner','coach_profile.manage','coach_any'),
  (1,'owner','coach.scope.expand','coach_any'),
  (1,'owner','client.view','client_any'),
  (1,'owner','client.manage','client_any'),
  (1,'owner','program.view','program_any'),
  (1,'owner','program.manage','program_any'),
  (1,'owner','workout.view','workout_any'),
  (1,'owner','workout.manage','workout_any'),

  -- ORG_ADMIN: operational tenant admin, but no billing/ownership/custom-domain.
  (1,'org_admin','organization.view','tenant'),
  (1,'org_admin','organization.members.manage','tenant'),
  (1,'org_admin','organization.coaches.manage','tenant'),
  (1,'org_admin','organization.clients.manage','tenant'),
  (1,'org_admin','organization.configuration.manage','tenant'),
  (1,'org_admin','permissions.manage','tenant'),
  (1,'org_admin','member.view','member_any'),
  (1,'org_admin','coach_profile.view','coach_any'),
  (1,'org_admin','coach_profile.manage','coach_any'),
  (1,'org_admin','coach.scope.expand','coach_any'),
  (1,'org_admin','client.view','client_any'),
  (1,'org_admin','client.manage','client_any'),
  (1,'org_admin','program.view','program_any'),
  (1,'org_admin','program.manage','program_any'),
  (1,'org_admin','workout.view','workout_any'),
  (1,'org_admin','workout.manage','workout_any'),

  -- COACH: only assigned clients/resources unless S6 audited expanded scope says otherwise.
  (1,'coach','organization.view','tenant'),
  (1,'coach','member.view','member_self'),
  (1,'coach','coach_profile.view','coach_active_member'),
  (1,'coach','client.view','client_assigned'),
  (1,'coach','client.manage','client_assigned'),
  (1,'coach','program.view','program_assigned'),
  (1,'coach','program.manage','program_assigned'),
  (1,'coach','workout.view','workout_assigned'),
  (1,'coach','workout.manage','workout_assigned'),

  -- CLIENT: own identity and published/self operational resources only.
  (1,'client','organization.view','tenant'),
  (1,'client','member.view','member_self'),
  (1,'client','coach_profile.view','coach_active_member'),
  (1,'client','client.view','client_self'),
  (1,'client','client.self_profile.update','client_self'),
  (1,'client','program.view','program_self_published'),
  (1,'client','workout.view','workout_self'),
  (1,'client','workout.manage','workout_self')
on conflict do nothing;

update public.permission_matrix_versions
set sealed=true
where version=1 and sealed=false;

create or replace function private.current_permission_matrix_version_v1()
returns integer
language sql
stable
security definer
set search_path to ''
as $function$
  select max(v.version)
  from public.permission_matrix_versions v
  where v.sealed
$function$;

create or replace function private.permission_decision_v1(
  p_organization_id uuid,
  p_actor_user_id uuid,
  p_capability text,
  p_resource_type text,
  p_resource_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_matrix integer;
  v_expected_type text;
  v_normalized_type text:=p_resource_type;
  v_resource_org uuid;
  v_resource_user uuid;
  v_resource_status text;
  v_program_published timestamptz;
  v_scopes text[];
  v_scope text;
  v_allowed boolean:=false;
  v_reason text:='deny_by_default';
begin
  v_matrix:=private.current_permission_matrix_version_v1();

  if v_matrix is null then
    return jsonb_build_object(
      'allowed',false,'reason','no_sealed_permission_matrix',
      'matrix_version',null
    );
  end if;

  select c.resource_type into v_expected_type
  from public.permission_capabilities c
  where c.capability=p_capability
    and c.introduced_version<=v_matrix;

  if not found then
    return jsonb_build_object(
      'allowed',false,'reason','unknown_capability',
      'capability',p_capability,'matrix_version',v_matrix
    );
  end if;

  if p_organization_id is null or p_resource_id is null then
    return jsonb_build_object(
      'allowed',false,'reason','missing_resource_context',
      'capability',p_capability,'matrix_version',v_matrix
    );
  end if;

  if p_resource_type='organization' then
    v_normalized_type:='organization';
    select o.id into v_resource_org
    from public.organizations o
    where o.id=p_resource_id;
  elsif p_resource_type='member' then
    v_normalized_type:='member';
    select om.organization_id,om.user_id
      into v_resource_org,v_resource_user
    from public.organization_members om
    where om.id=p_resource_id
      and om.status<>'removed'::public.organization_member_status;
  elsif p_resource_type='coach_profile' then
    v_normalized_type:='coach_profile';
    select cp.organization_id,cp.user_id,cp.status::text
      into v_resource_org,v_resource_user,v_resource_status
    from public.coach_profiles cp
    where cp.id=p_resource_id;
  elsif p_resource_type='client' then
    v_normalized_type:='client';
    select c.organization_id,c.user_id,c.status::text
      into v_resource_org,v_resource_user,v_resource_status
    from public.clients c
    where c.id=p_resource_id
      and c.status<>'archived'::public.client_status;
  elsif p_resource_type='client_user' then
    v_normalized_type:='client';
    select c.organization_id,c.user_id,c.status::text
      into v_resource_org,v_resource_user,v_resource_status
    from public.clients c
    where c.organization_id=p_organization_id
      and c.user_id=p_resource_id
      and c.status<>'archived'::public.client_status;
  elsif p_resource_type='program' then
    v_normalized_type:='program';
    select p.organization_id,p.client_id,p.status::text,p.published_at
      into v_resource_org,v_resource_user,v_resource_status,v_program_published
    from public.programs p
    where p.id=p_resource_id;
  elsif p_resource_type='workout_session' then
    v_normalized_type:='workout_session';
    select ws.organization_id,ws.client_id,ws.status::text
      into v_resource_org,v_resource_user,v_resource_status
    from public.workout_sessions ws
    where ws.id=p_resource_id;
  else
    return jsonb_build_object(
      'allowed',false,'reason','unknown_resource_type',
      'capability',p_capability,'matrix_version',v_matrix
    );
  end if;

  if v_resource_org is null then
    return jsonb_build_object(
      'allowed',false,'reason','resource_not_found',
      'capability',p_capability,'matrix_version',v_matrix
    );
  end if;

  if v_resource_org<>p_organization_id then
    return jsonb_build_object(
      'allowed',false,'reason','cross_tenant_resource',
      'capability',p_capability,'matrix_version',v_matrix
    );
  end if;

  if v_normalized_type<>v_expected_type then
    return jsonb_build_object(
      'allowed',false,'reason','resource_type_mismatch',
      'capability',p_capability,'matrix_version',v_matrix,
      'expected_resource_type',v_expected_type,
      'actual_resource_type',v_normalized_type
    );
  end if;

  -- Backend service role may execute known capabilities on a valid in-tenant resource.
  if auth.role()='service_role' then
    return jsonb_build_object(
      'allowed',true,'reason','service_role',
      'capability',p_capability,'resource_type',v_normalized_type,
      'matrix_version',v_matrix
    );
  end if;

  if p_actor_user_id is null then
    return jsonb_build_object(
      'allowed',false,'reason','missing_actor',
      'capability',p_capability,'matrix_version',v_matrix
    );
  end if;

  if not exists(
    select 1
    from public.profiles p
    where p.id=p_actor_user_id
      and p.status='active'::public.profile_status
  ) then
    return jsonb_build_object(
      'allowed',false,'reason','inactive_actor',
      'capability',p_capability,'matrix_version',v_matrix
    );
  end if;

  if not exists(
    select 1
    from public.organization_members om
    where om.organization_id=p_organization_id
      and om.user_id=p_actor_user_id
      and om.status='active'::public.organization_member_status
  ) then
    return jsonb_build_object(
      'allowed',false,'reason','no_active_membership',
      'capability',p_capability,'matrix_version',v_matrix
    );
  end if;

  select coalesce(array_agg(distinct rr.scope order by rr.scope),'{}'::text[])
    into v_scopes
  from public.organization_member_roles mr
  join public.permission_role_rules rr
    on rr.matrix_version=v_matrix
   and rr.role=mr.role
   and rr.capability=p_capability
  where mr.organization_id=p_organization_id
    and mr.user_id=p_actor_user_id
    and mr.status='active'::public.organization_member_role_assignment_status;

  if coalesce(cardinality(v_scopes),0)=0 then
    return jsonb_build_object(
      'allowed',false,'reason','capability_not_granted',
      'capability',p_capability,'matrix_version',v_matrix
    );
  end if;

  foreach v_scope in array v_scopes
  loop
    v_allowed:=case v_scope
      when 'tenant' then
        v_normalized_type='organization'
        and p_resource_id=p_organization_id

      when 'member_any' then
        v_normalized_type='member'

      when 'member_self' then
        v_normalized_type='member'
        and v_resource_user=p_actor_user_id

      when 'coach_any' then
        v_normalized_type='coach_profile'

      when 'coach_self' then
        v_normalized_type='coach_profile'
        and v_resource_user=p_actor_user_id

      when 'coach_active_member' then
        v_normalized_type='coach_profile'
        and v_resource_status='active'

      when 'client_any' then
        v_normalized_type='client'

      when 'client_assigned' then
        v_normalized_type='client'
        and private.coach_can_access_client_v1(
          p_organization_id,p_actor_user_id,v_resource_user
        )

      when 'client_self' then
        v_normalized_type='client'
        and v_resource_user=p_actor_user_id
        and private.is_client_in_org_v1(
          p_organization_id,p_actor_user_id
        )

      when 'program_any' then
        v_normalized_type='program'

      when 'program_assigned' then
        v_normalized_type='program'
        and private.coach_can_access_client_v1(
          p_organization_id,p_actor_user_id,v_resource_user
        )

      when 'program_self_published' then
        v_normalized_type='program'
        and v_resource_user=p_actor_user_id
        and private.is_client_in_org_v1(
          p_organization_id,p_actor_user_id
        )
        and v_program_published is not null
        and v_resource_status in ('active','completed')

      when 'workout_any' then
        v_normalized_type='workout_session'

      when 'workout_assigned' then
        v_normalized_type='workout_session'
        and private.coach_can_access_client_v1(
          p_organization_id,p_actor_user_id,v_resource_user
        )

      when 'workout_self' then
        v_normalized_type='workout_session'
        and v_resource_user=p_actor_user_id
        and private.is_client_in_org_v1(
          p_organization_id,p_actor_user_id
        )

      else false
    end;

    if v_allowed then
      v_reason:='allowed_by_scope:'||v_scope;
      exit;
    end if;
  end loop;

  return jsonb_build_object(
    'allowed',v_allowed,
    'reason',v_reason,
    'capability',p_capability,
    'resource_type',v_normalized_type,
    'resource_id',p_resource_id,
    'organization_id',p_organization_id,
    'actor_user_id',p_actor_user_id,
    'scopes',to_jsonb(v_scopes),
    'matrix_version',v_matrix,
    'matrix_code','F1.M2.S8_PERMISSION_MATRIX_V1',
    'authorization_only',true,
    'feature_entitlements_separate',true,
    'claims_authoritative',false
  );
end;
$function$;

create or replace function private.has_permission_v1(
  p_organization_id uuid,
  p_actor_user_id uuid,
  p_capability text,
  p_resource_type text,
  p_resource_id uuid
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    (
      private.permission_decision_v1(
        p_organization_id,p_actor_user_id,p_capability,
        p_resource_type,p_resource_id
      )->>'allowed'
    )::boolean,
    false
  )
$function$;

create or replace function private.require_permission_v1(
  p_organization_id uuid,
  p_actor_user_id uuid,
  p_capability text,
  p_resource_type text,
  p_resource_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_decision jsonb;
begin
  v_decision:=private.permission_decision_v1(
    p_organization_id,p_actor_user_id,p_capability,
    p_resource_type,p_resource_id
  );
  if coalesce((v_decision->>'allowed')::boolean,false) is not true then
    raise exception 'Permission denied: %',coalesce(v_decision->>'reason','deny_by_default')
      using errcode='42501';
  end if;
  return v_decision;
end;
$function$;

create or replace function public.check_permission_v1(
  p_organization_id uuid,
  p_capability text,
  p_resource_type text,
  p_resource_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_uid uuid:=auth.uid();
begin
  if v_uid is null and auth.role()<>'service_role' then
    raise exception 'Authentication required';
  end if;

  return private.permission_decision_v1(
    p_organization_id,v_uid,p_capability,p_resource_type,p_resource_id
  );
end;
$function$;

create or replace function public.get_my_permission_snapshot_v1(
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
  v_matrix integer;
  v_roles public.organization_member_role[];
  v_caps jsonb:='[]'::jsonb;
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;

  if not exists(
    select 1
    from public.organization_members om
    where om.organization_id=p_organization_id
      and om.user_id=v_uid
      and om.status='active'::public.organization_member_status
  ) then
    raise exception 'Active organization membership required';
  end if;

  v_matrix:=private.current_permission_matrix_version_v1();
  v_roles:=private.current_org_roles_v1(p_organization_id,v_uid);

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'capability',x.capability,
        'resource_type',x.resource_type,
        'scopes',x.scopes
      )
      order by x.capability
    ),
    '[]'::jsonb
  )
  into v_caps
  from (
    select
      c.capability,
      c.resource_type,
      to_jsonb(array_agg(distinct rr.scope order by rr.scope)) as scopes
    from public.permission_role_rules rr
    join public.permission_capabilities c
      on c.capability=rr.capability
    where rr.matrix_version=v_matrix
      and rr.role=any(v_roles)
    group by c.capability,c.resource_type
  ) x;

  return jsonb_build_object(
    'organization_id',p_organization_id,
    'user_id',v_uid,
    'roles',to_jsonb(v_roles),
    'capabilities',v_caps,
    'matrix_version',v_matrix,
    'matrix_code','F1.M2.S8_PERMISSION_MATRIX_V1',
    'authorization_only',true,
    'feature_entitlements_separate',true,
    'claims_authoritative',false,
    'dynamic_membership_revalidation',true
  );
end;
$function$;

revoke all on function public.check_permission_v1(uuid,text,text,uuid)
  from public,anon;
revoke all on function public.get_my_permission_snapshot_v1(uuid)
  from public,anon;
grant execute on function public.check_permission_v1(uuid,text,text,uuid)
  to authenticated,service_role;
grant execute on function public.get_my_permission_snapshot_v1(uuid)
  to authenticated,service_role;

-- Existing RLS helpers now delegate to the same backend decision engine.
create or replace function private.can_view_organization(
  target_organization uuid
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select private.has_permission_v1(
    target_organization,auth.uid(),
    'organization.view','organization',target_organization
  )
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
    or exists(
      select 1
      from public.organization_members om
      where om.organization_id=p_organization_id
        and om.user_id=p_member_user_id
        and private.has_permission_v1(
          p_organization_id,auth.uid(),
          'member.view','member',om.id
        )
    ),
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
    or exists(
      select 1
      from public.coach_profiles cp
      where cp.organization_id=p_organization_id
        and cp.user_id=p_coach_user_id
        and cp.status=p_status
        and private.has_permission_v1(
          p_organization_id,auth.uid(),
          'coach_profile.view','coach_profile',cp.id
        )
    ),
    false
  )
$function$;

create or replace function private.can_view_client_entity(
  target_client uuid
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    auth.role()='service_role'
    or exists(
      select 1
      from public.clients c
      where c.id=target_client
        and private.has_permission_v1(
          c.organization_id,auth.uid(),
          'client.view','client',c.id
        )
    ),
    false
  )
$function$;

create or replace function private.can_view_client_in_org(
  target_organization uuid,
  target_client_user uuid
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select private.has_permission_v1(
    target_organization,auth.uid(),
    'client.view','client_user',target_client_user
  )
$function$;

create or replace function private.can_manage_client_in_org(
  target_organization uuid,
  target_client_user uuid
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select private.has_permission_v1(
    target_organization,auth.uid(),
    'client.manage','client_user',target_client_user
  )
$function$;

create or replace function private.can_view_program(
  target_program uuid
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    exists(
      select 1
      from public.programs p
      where p.id=target_program
        and private.has_permission_v1(
          p.organization_id,auth.uid(),
          'program.view','program',p.id
        )
    ),
    false
  )
$function$;

create or replace function private.can_manage_program(
  target_program uuid
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    exists(
      select 1
      from public.programs p
      where p.id=target_program
        and private.has_permission_v1(
          p.organization_id,auth.uid(),
          'program.manage','program',p.id
        )
    ),
    false
  )
$function$;

create or replace function private.can_manage_program_day(
  target_day uuid
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    exists(
      select 1
      from public.program_days d
      where d.id=target_day
        and private.can_manage_program(d.program_id)
    ),
    false
  )
$function$;

create or replace function private.can_view_workout_session(
  target_session uuid
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    exists(
      select 1
      from public.workout_sessions ws
      where ws.id=target_session
        and private.has_permission_v1(
          ws.organization_id,auth.uid(),
          'workout.view','workout_session',ws.id
        )
    ),
    false
  )
$function$;

create or replace function private.can_edit_workout_session(
  target_session uuid
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    exists(
      select 1
      from public.workout_sessions ws
      where ws.id=target_session
        and private.has_permission_v1(
          ws.organization_id,auth.uid(),
          'workout.manage','workout_session',ws.id
        )
    ),
    false
  )
$function$;

comment on table public.permission_role_rules is
'F1.M2.S8 sealed versioned RBAC matrix. Resource scope is evaluated dynamically; feature entitlements are intentionally separate.';
comment on function private.permission_decision_v1(uuid,uuid,text,text,uuid) is
'F1.M2.S8 deny-by-default authorization decision. Reads live membership/roles/resources; JWT claims are not permission authority.';
comment on function public.get_my_permission_snapshot_v1(uuid) is
'F1.M2.S8 frontend visibility snapshot only. Server/RLS remains authoritative and feature entitlement is separate.';
