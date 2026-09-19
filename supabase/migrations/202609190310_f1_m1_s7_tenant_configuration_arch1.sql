-- ARCH-1.0 · F1.M1.S7 — Tenant base configuration
-- Formalizes safe member-facing Organization configuration and validated admin mutation.

create or replace function private.guard_organization_identity_v1()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
  if tg_op='UPDATE' then
    if new.slug is distinct from old.slug then
      raise exception 'organization slug is immutable; use a controlled migration';
    end if;
    if new.owner_user_id is distinct from old.owner_user_id then
      raise exception 'organization owner is immutable through direct updates';
    end if;
    if old.status='archived'::public.organization_status
       and new.status<>'archived'::public.organization_status then
      raise exception 'archived organization is terminal';
    end if;
  end if;

  new.display_name:=btrim(coalesce(new.display_name,''));
  if new.display_name='' or char_length(new.display_name)>160 then
    raise exception 'organization display_name must be 1..160 characters';
  end if;

  new.locale:=btrim(coalesce(new.locale,''));
  if new.locale!~'^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$' then
    raise exception 'invalid organization locale';
  end if;

  new.currency:=upper(btrim(coalesce(new.currency,'')));
  if new.currency!~'^[A-Z]{3}$' then
    raise exception 'organization currency must be ISO-like 3-letter code';
  end if;

  new.timezone:=btrim(coalesce(new.timezone,''));
  if not exists(
    select 1 from pg_catalog.pg_timezone_names z
    where z.name=new.timezone
  ) then
    raise exception 'invalid organization timezone';
  end if;

  if jsonb_typeof(new.branding_config)<>'object' then
    raise exception 'branding_config must be a JSON object';
  end if;
  if jsonb_typeof(new.feature_flags)<>'object' then
    raise exception 'feature_flags must be a JSON object';
  end if;
  if jsonb_typeof(new.settings)<>'object' then
    raise exception 'settings must be a JSON object';
  end if;

  if pg_catalog.octet_length(new.branding_config::text)>32768 then
    raise exception 'branding_config exceeds 32KB';
  end if;
  if pg_catalog.octet_length(new.feature_flags::text)>32768 then
    raise exception 'feature_flags exceeds 32KB';
  end if;
  if pg_catalog.octet_length(new.settings::text)>65536 then
    raise exception 'settings exceeds 64KB';
  end if;

  if new.status='archived'::public.organization_status then
    new.archived_at:=coalesce(new.archived_at,now());
  else
    new.archived_at:=null;
  end if;

  return new;
end;
$function$;

alter table public.organizations
  drop constraint if exists organizations_currency_format_chk,
  add constraint organizations_currency_format_chk
    check (currency~'^[A-Z]{3}$');

alter table public.organizations
  drop constraint if exists organizations_locale_format_chk,
  add constraint organizations_locale_format_chk
    check (locale~'^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$');

alter table public.organizations
  drop constraint if exists organizations_branding_object_chk,
  add constraint organizations_branding_object_chk
    check (jsonb_typeof(branding_config)='object');

alter table public.organizations
  drop constraint if exists organizations_feature_flags_object_chk,
  add constraint organizations_feature_flags_object_chk
    check (jsonb_typeof(feature_flags)='object');

alter table public.organizations
  drop constraint if exists organizations_settings_object_chk,
  add constraint organizations_settings_object_chk
    check (jsonb_typeof(settings)='object');

create or replace function public.get_organization_configuration_v1(
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

    v_is_active_member:=found
      and v_member.status='active'::public.organization_member_status;
  end if;

  v_is_org_admin:=v_is_platform_admin
    or (
      v_is_active_member
      and v_member.role in (
        'owner'::public.organization_member_role,
        'org_admin'::public.organization_member_role
      )
    );

  if not (v_is_platform_admin or v_is_active_member) then
    raise exception 'Organization outside actor scope';
  end if;

  return jsonb_build_object(
    'organization_id',v_org.id,
    'member_config',jsonb_build_object(
      'slug',v_org.slug,
      'display_name',v_org.display_name,
      'status',v_org.status,
      'locale',v_org.locale,
      'timezone',v_org.timezone,
      'currency',v_org.currency,
      'branding_config',v_org.branding_config,
      'feature_flags',v_org.feature_flags
    ),
    'admin_config',case
      when v_is_org_admin then jsonb_build_object(
        'legal_name',v_org.legal_name,
        'settings',v_org.settings,
        'plan_id',v_org.plan_id,
        'billing_account_configured',v_org.billing_account_id is not null,
        'owner_user_id',v_org.owner_user_id
      )
      else null
    end,
    'permissions',jsonb_build_object(
      'can_manage_configuration',v_is_org_admin,
      'is_org_admin',v_is_org_admin,
      'is_platform_admin',v_is_platform_admin
    ),
    'version','F1.M1.S7_TENANT_CONFIG_V1'
  );
end;
$function$;

create or replace function public.update_organization_configuration_v1(
  p_organization_id uuid,
  p_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid:=auth.uid();
  v_org public.organizations%rowtype;
  v_unknown jsonb;
  v_display_name text;
  v_legal_name text;
  v_locale text;
  v_timezone text;
  v_currency text;
  v_branding jsonb;
  v_flags jsonb;
  v_settings jsonb;
begin
  if p_organization_id is null or p_patch is null then
    raise exception 'organization_id and patch are required';
  end if;

  if jsonb_typeof(p_patch)<>'object' then
    raise exception 'patch must be a JSON object';
  end if;

  if auth.role()<>'service_role' and v_uid is null then
    raise exception 'Authentication required';
  end if;

  if not (
    auth.role()='service_role'
    or private.is_org_admin(p_organization_id)
  ) then
    raise exception 'Organization admin required';
  end if;

  select * into v_org
  from public.organizations
  where id=p_organization_id
  for update;

  if not found then
    raise exception 'Organization not found';
  end if;

  if v_org.status='archived'::public.organization_status then
    raise exception 'Archived organization configuration is immutable';
  end if;

  v_unknown:=p_patch-array[
    'display_name','legal_name','locale','timezone',
    'currency','branding_config','feature_flags','settings'
  ]::text[];

  if v_unknown<>'{}'::jsonb then
    raise exception 'Unsupported configuration fields: %',(
      select string_agg(key,',' order by key)
      from jsonb_object_keys(v_unknown) key
    );
  end if;

  v_display_name:=v_org.display_name;
  v_legal_name:=v_org.legal_name;
  v_locale:=v_org.locale;
  v_timezone:=v_org.timezone;
  v_currency:=v_org.currency;
  v_branding:=v_org.branding_config;
  v_flags:=v_org.feature_flags;
  v_settings:=v_org.settings;

  if p_patch?'display_name' then
    if jsonb_typeof(p_patch->'display_name')<>'string' then
      raise exception 'display_name must be a string';
    end if;
    v_display_name:=btrim(p_patch->>'display_name');
  end if;

  if p_patch?'legal_name' then
    if p_patch->'legal_name'='null'::jsonb then
      v_legal_name:=null;
    elsif jsonb_typeof(p_patch->'legal_name')='string' then
      v_legal_name:=nullif(btrim(p_patch->>'legal_name'),'');
      if v_legal_name is not null and char_length(v_legal_name)>200 then
        raise exception 'legal_name must be <= 200 characters';
      end if;
    else
      raise exception 'legal_name must be a string or null';
    end if;
  end if;

  if p_patch?'locale' then
    if jsonb_typeof(p_patch->'locale')<>'string' then
      raise exception 'locale must be a string';
    end if;
    v_locale:=btrim(p_patch->>'locale');
  end if;

  if p_patch?'timezone' then
    if jsonb_typeof(p_patch->'timezone')<>'string' then
      raise exception 'timezone must be a string';
    end if;
    v_timezone:=btrim(p_patch->>'timezone');
    if not exists(
      select 1 from pg_catalog.pg_timezone_names z
      where z.name=v_timezone
    ) then
      raise exception 'invalid timezone';
    end if;
  end if;

  if p_patch?'currency' then
    if jsonb_typeof(p_patch->'currency')<>'string' then
      raise exception 'currency must be a string';
    end if;
    v_currency:=upper(btrim(p_patch->>'currency'));
  end if;

  if p_patch?'branding_config' then
    if jsonb_typeof(p_patch->'branding_config')<>'object' then
      raise exception 'branding_config must be a JSON object';
    end if;
    v_branding:=p_patch->'branding_config';
  end if;

  if p_patch?'feature_flags' then
    if jsonb_typeof(p_patch->'feature_flags')<>'object' then
      raise exception 'feature_flags must be a JSON object';
    end if;
    v_flags:=p_patch->'feature_flags';
  end if;

  if p_patch?'settings' then
    if jsonb_typeof(p_patch->'settings')<>'object' then
      raise exception 'settings must be a JSON object';
    end if;
    v_settings:=p_patch->'settings';
  end if;

  update public.organizations
  set display_name=v_display_name,
      legal_name=v_legal_name,
      locale=v_locale,
      timezone=v_timezone,
      currency=v_currency,
      branding_config=v_branding,
      feature_flags=v_flags,
      settings=v_settings,
      updated_at=now()
  where id=p_organization_id;

  return public.get_organization_configuration_v1(p_organization_id);
end;
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
  v_member public.organization_members%rowtype;
  v_config jsonb;
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

  v_config:=public.get_organization_configuration_v1(p_organization_id);
  v_is_platform_admin:=coalesce(
    (v_config->'permissions'->>'is_platform_admin')::boolean,
    false
  );
  v_is_org_admin:=coalesce(
    (v_config->'permissions'->>'is_org_admin')::boolean,
    false
  );

  if v_uid is not null then
    select * into v_member
    from public.organization_members om
    where om.organization_id=p_organization_id
      and om.user_id=v_uid;
    v_is_active_member:=found and v_member.status='active'::public.organization_member_status;
    if v_is_active_member then v_role:=v_member.role; end if;
  end if;

  return jsonb_build_object(
    'organization',v_config->'member_config',
    'membership',case
      when v_uid is null then null
      else jsonb_build_object(
        'user_id',v_uid,
        'role',v_member.role,
        'status',v_member.status,
        'joined_at',v_member.joined_at
      )
    end,
    'permissions',jsonb_build_object(
      'is_platform_admin',v_is_platform_admin,
      'is_org_admin',v_is_org_admin,
      'can_manage_organization',v_is_org_admin,
      'can_manage_configuration',v_is_org_admin,
      'can_view_all_members',v_is_org_admin,
      'can_manage_members',v_is_org_admin,
      'can_manage_coaches',v_is_org_admin,
      'can_manage_all_clients',v_is_org_admin,
      'can_manage_assignments',v_is_org_admin,
      'can_manage_assigned_clients',v_is_org_admin or v_role='coach'::public.organization_member_role,
      'can_submit_client_state',v_role='client'::public.organization_member_role,
      'can_view_active_coach_directory',v_is_platform_admin or v_is_active_member
    ),
    'admin',v_config->'admin_config',
    'version','F1.M1.S7_PERMISSION_CONTEXT_V1'
  );
end;
$function$;

revoke all on function public.get_organization_configuration_v1(uuid) from public,anon;
grant execute on function public.get_organization_configuration_v1(uuid) to authenticated,service_role;

revoke all on function public.update_organization_configuration_v1(uuid,jsonb) from public,anon;
grant execute on function public.update_organization_configuration_v1(uuid,jsonb) to authenticated,service_role;

comment on function public.get_organization_configuration_v1(uuid)
is 'F1.M1.S7 safe tenant configuration contract. Member config excludes billing/settings; admin config is returned only to org/platform admins.';

comment on function public.update_organization_configuration_v1(uuid,jsonb)
is 'F1.M1.S7 validated admin configuration mutation. Slug, owner, status, plan and billing account cannot be changed through this RPC.';
