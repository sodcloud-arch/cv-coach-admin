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
  v_options jsonb:='[]'::jsonb;
  v_resolution text;
  v_active jsonb:=null;
  v_slug text:=nullif(lower(btrim(coalesce(p_suggested_slug,''))),'');
  v_suggested_match uuid;
  v_selected_valid boolean:=false;

  v_active_org_id uuid;
  v_active_slug text;
  v_active_display_name text;
  v_active_org_status public.organization_status;
  v_active_role public.organization_member_role;
  v_active_locale text;
  v_active_timezone text;
  v_active_currency text;
  v_active_branding jsonb;
  v_active_flags jsonb;
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
    select
      o.id,o.slug,o.display_name,o.status,om.role,
      o.locale,o.timezone,o.currency,o.branding_config,o.feature_flags
    into
      v_active_org_id,v_active_slug,v_active_display_name,v_active_org_status,v_active_role,
      v_active_locale,v_active_timezone,v_active_currency,v_active_branding,v_active_flags
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
    v_active_org_id:=null;
  elsif v_count=1 then
    select
      o.id,o.slug,o.display_name,o.status,om.role,
      o.locale,o.timezone,o.currency,o.branding_config,o.feature_flags
    into
      v_active_org_id,v_active_slug,v_active_display_name,v_active_org_status,v_active_role,
      v_active_locale,v_active_timezone,v_active_currency,v_active_branding,v_active_flags
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
  elsif v_selected_valid then
    v_resolution:='selected';
  else
    v_resolution:='selection_required';
    v_active_org_id:=null;
  end if;

  if v_active_org_id is not null then
    v_active:=jsonb_build_object(
      'organization_id',v_active_org_id,
      'slug',v_active_slug,
      'display_name',v_active_display_name,
      'organization_status',v_active_org_status,
      'role',v_active_role,
      'locale',v_active_locale,
      'timezone',v_active_timezone,
      'currency',v_active_currency,
      'branding_config',v_active_branding,
      'feature_flags',v_active_flags
    );
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
