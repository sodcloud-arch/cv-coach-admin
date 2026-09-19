-- F1.M2.S1 — Global login + secure active Organization resolution
-- Credentials authenticate a global User. Tenant authority is derived only from active memberships.

create or replace function public.resolve_active_organization_context_v1(
  p_selected_organization_id uuid default null,
  p_suggested_slug text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_uid uuid:=auth.uid();
  v_profile public.profiles%rowtype;
  v_count integer:=0;
  v_selected public.organization_members%rowtype;
  v_selected_org public.organizations%rowtype;
  v_auto_org public.organizations%rowtype;
  v_auto_member public.organization_members%rowtype;
  v_options jsonb:='[]'::jsonb;
  v_resolution text;
  v_active jsonb:=null;
  v_slug text:=nullif(lower(btrim(coalesce(p_suggested_slug,''))),'');
  v_suggested_match uuid;
  v_selected_valid boolean:=false;
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;

  select * into v_profile
  from public.profiles
  where id=v_uid
    and status='active'::public.profile_status;

  if not found then
    raise exception 'Active global profile required';
  end if;

  with eligible as (
    select
      om.organization_id,
      om.role,
      om.joined_at,
      o.slug,
      o.display_name,
      o.status,
      o.locale,
      o.timezone,
      o.currency,
      o.branding_config,
      o.feature_flags
    from public.organization_members om
    join public.organizations o on o.id=om.organization_id
    where om.user_id=v_uid
      and om.status='active'::public.organization_member_status
      and o.status in (
        'trial'::public.organization_status,
        'active'::public.organization_status
      )
  )
  select
    count(*)::integer,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'organization_id',organization_id,
          'slug',slug,
          'display_name',display_name,
          'organization_status',status,
          'role',role,
          'joined_at',joined_at,
          'locale',locale,
          'timezone',timezone,
          'currency',currency,
          'branding_config',branding_config,
          'feature_flags',feature_flags
        )
        order by lower(display_name),organization_id
      ),
      '[]'::jsonb
    )
  into v_count,v_options
  from eligible;

  if v_slug is not null then
    select om.organization_id into v_suggested_match
    from public.organization_members om
    join public.organizations o on o.id=om.organization_id
    where om.user_id=v_uid
      and om.status='active'::public.organization_member_status
      and o.status in (
        'trial'::public.organization_status,
        'active'::public.organization_status
      )
      and lower(o.slug)=v_slug
    limit 1;
  end if;

  if p_selected_organization_id is not null then
    select om.*,o.*
    into v_selected,v_selected_org
    from public.organization_members om
    join public.organizations o on o.id=om.organization_id
    where om.user_id=v_uid
      and om.organization_id=p_selected_organization_id
      and om.status='active'::public.organization_member_status
      and o.status in (
        'trial'::public.organization_status,
        'active'::public.organization_status
      )
    limit 1;

    v_selected_valid:=found;
  end if;

  if v_count=0 then
    v_resolution:='no_membership';
  elsif v_count=1 then
    select om.*,o.*
    into v_auto_member,v_auto_org
    from public.organization_members om
    join public.organizations o on o.id=om.organization_id
    where om.user_id=v_uid
      and om.status='active'::public.organization_member_status
      and o.status in (
        'trial'::public.organization_status,
        'active'::public.organization_status
      )
    limit 1;

    v_resolution:='auto_selected';
    v_active:=jsonb_build_object(
      'organization_id',v_auto_org.id,
      'slug',v_auto_org.slug,
      'display_name',v_auto_org.display_name,
      'organization_status',v_auto_org.status,
      'role',v_auto_member.role,
      'locale',v_auto_org.locale,
      'timezone',v_auto_org.timezone,
      'currency',v_auto_org.currency,
      'branding_config',v_auto_org.branding_config,
      'feature_flags',v_auto_org.feature_flags
    );
  elsif v_selected_valid then
    v_resolution:='selected';
    v_active:=jsonb_build_object(
      'organization_id',v_selected_org.id,
      'slug',v_selected_org.slug,
      'display_name',v_selected_org.display_name,
      'organization_status',v_selected_org.status,
      'role',v_selected.role,
      'locale',v_selected_org.locale,
      'timezone',v_selected_org.timezone,
      'currency',v_selected_org.currency,
      'branding_config',v_selected_org.branding_config,
      'feature_flags',v_selected_org.feature_flags
    );
  else
    v_resolution:='selection_required';
  end if;

  return jsonb_build_object(
    'ok',true,
    'actor',jsonb_build_object(
      'user_id',v_uid,
      'global_role',v_profile.role,
      'profile_status',v_profile.status
    ),
    'resolution',v_resolution,
    'membership_count',v_count,
    'memberships',v_options,
    'active_organization',v_active,
    'selected_organization_id',p_selected_organization_id,
    'selected_organization_valid',v_selected_valid,
    'suggested_slug',v_slug,
    'suggested_match_organization_id',v_suggested_match,
    'suggested_slug_authoritative',false,
    'next_action',case
      when v_resolution='no_membership' then 'await_invitation_or_onboarding'
      when v_resolution='selection_required' then 'select_organization'
      else 'enter_tenant'
    end,
    'version','F1.M2.S1_ACTIVE_ORG_CONTEXT_V1'
  );
end;
$function$;

revoke all on function public.resolve_active_organization_context_v1(uuid,text) from public,anon;
grant execute on function public.resolve_active_organization_context_v1(uuid,text) to authenticated,service_role;

comment on function public.resolve_active_organization_context_v1(uuid,text)
is 'F1.M2.S1 global-login tenant resolver. Tenant authority comes only from an active Organization membership; URL/slug is a non-authoritative hint.';
