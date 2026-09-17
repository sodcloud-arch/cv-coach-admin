-- ARCH-1.0 · F1.M1.S1 Organization tenant root
-- Additive, backward-compatible multi-tenant foundation.
-- Existing CV Coach tables are intentionally unchanged in this migration.

do $$ begin
  create type public.organization_status as enum ('trial','active','suspended','archived');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.organization_member_role as enum ('owner','org_admin','coach','client');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.organization_member_status as enum ('invited','active','suspended','removed');
exception when duplicate_object then null;
end $$;

create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  display_name text not null,
  legal_name text,
  status public.organization_status not null default 'trial',
  locale text not null default 'en-US',
  timezone text not null default 'UTC',
  currency text not null default 'USD',
  owner_user_id uuid not null references public.profiles(id) on delete restrict,
  branding_config jsonb not null default '{}'::jsonb,
  feature_flags jsonb not null default '{}'::jsonb,
  settings jsonb not null default '{}'::jsonb,
  plan_id uuid,
  billing_account_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  constraint organizations_slug_format check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  constraint organizations_display_name_not_blank check (length(btrim(display_name)) > 0),
  constraint organizations_locale_not_blank check (length(btrim(locale)) > 0),
  constraint organizations_timezone_not_blank check (length(btrim(timezone)) > 0),
  constraint organizations_currency_format check (currency ~ '^[A-Z]{3}$'),
  constraint organizations_branding_object check (jsonb_typeof(branding_config) = 'object'),
  constraint organizations_feature_flags_object check (jsonb_typeof(feature_flags) = 'object'),
  constraint organizations_settings_object check (jsonb_typeof(settings) = 'object'),
  constraint organizations_archive_consistency check (
    (status = 'archived' and archived_at is not null)
    or (status <> 'archived' and archived_at is null)
  )
);

create table if not exists public.organization_members (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  user_id uuid not null references public.profiles(id) on delete restrict,
  role public.organization_member_role not null,
  status public.organization_member_status not null default 'active',
  joined_at timestamptz,
  ended_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint organization_members_unique_user unique (organization_id,user_id),
  constraint organization_members_membership_dates check (
    (status in ('invited','active','suspended') and ended_at is null)
    or (status = 'removed' and ended_at is not null)
  )
);

create index if not exists idx_organization_members_user_active
  on public.organization_members(user_id,organization_id)
  where status = 'active';

create index if not exists idx_organization_members_org_role
  on public.organization_members(organization_id,role,status);

create or replace function private.is_platform_admin()
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select coalesce(auth.role() = 'service_role' or private.is_admin(), false)
$function$;

create or replace function private.is_org_member(target_organization uuid)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select coalesce(
    auth.role() = 'service_role'
    or exists (
      select 1
      from public.organization_members om
      where om.organization_id = target_organization
        and om.user_id = auth.uid()
        and om.status = 'active'::public.organization_member_status
    ),
    false
  )
$function$;

create or replace function private.is_org_admin(target_organization uuid)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select coalesce(
    private.is_platform_admin()
    or exists (
      select 1
      from public.organization_members om
      where om.organization_id = target_organization
        and om.user_id = auth.uid()
        and om.status = 'active'::public.organization_member_status
        and om.role in ('owner'::public.organization_member_role,'org_admin'::public.organization_member_role)
    ),
    false
  )
$function$;

create or replace function private.can_view_organization(target_organization uuid)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select coalesce(private.is_platform_admin() or private.is_org_member(target_organization), false)
$function$;

create or replace function private.guard_organization_identity_v1()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
  if tg_op = 'UPDATE' then
    if new.slug is distinct from old.slug then
      raise exception 'organization slug is immutable; use a controlled migration';
    end if;
    if new.owner_user_id is distinct from old.owner_user_id then
      raise exception 'organization owner is immutable through direct updates';
    end if;
    if old.status = 'archived'::public.organization_status
       and new.status <> 'archived'::public.organization_status then
      raise exception 'archived organization is terminal';
    end if;
  end if;

  if new.status = 'archived'::public.organization_status then
    new.archived_at := coalesce(new.archived_at, now());
  else
    new.archived_at := null;
  end if;

  return new;
end;
$function$;

create or replace function private.guard_organization_owner_membership_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_owner uuid;
begin
  if new.role = 'owner'::public.organization_member_role then
    select o.owner_user_id into v_owner
    from public.organizations o
    where o.id = new.organization_id;
    if v_owner is null or new.user_id <> v_owner then
      raise exception 'owner membership must match organizations.owner_user_id';
    end if;
    if new.status <> 'active'::public.organization_member_status then
      raise exception 'organization owner membership must remain active';
    end if;
  end if;

  if tg_op = 'UPDATE'
     and old.role = 'owner'::public.organization_member_role
     and (new.role <> old.role or new.user_id <> old.user_id or new.organization_id <> old.organization_id) then
    raise exception 'owner membership identity is immutable through direct updates';
  end if;

  if new.status = 'active'::public.organization_member_status and new.joined_at is null then
    new.joined_at := now();
  elsif new.status = 'removed'::public.organization_member_status then
    new.ended_at := coalesce(new.ended_at, now());
  elsif new.status <> 'removed'::public.organization_member_status then
    new.ended_at := null;
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_organizations_guard_identity_v1 on public.organizations;
create trigger trg_organizations_guard_identity_v1
before insert or update on public.organizations
for each row execute function private.guard_organization_identity_v1();

drop trigger if exists trg_organizations_updated_at_v1 on public.organizations;
create trigger trg_organizations_updated_at_v1
before update on public.organizations
for each row execute function private.set_updated_at();

drop trigger if exists trg_organization_members_guard_owner_v1 on public.organization_members;
create trigger trg_organization_members_guard_owner_v1
before insert or update on public.organization_members
for each row execute function private.guard_organization_owner_membership_v1();

drop trigger if exists trg_organization_members_updated_at_v1 on public.organization_members;
create trigger trg_organization_members_updated_at_v1
before update on public.organization_members
for each row execute function private.set_updated_at();

alter table public.organizations enable row level security;
alter table public.organization_members enable row level security;

drop policy if exists organizations_select_v1 on public.organizations;
create policy organizations_select_v1
on public.organizations for select
to authenticated
using (private.can_view_organization(id));

drop policy if exists organizations_update_v1 on public.organizations;
create policy organizations_update_v1
on public.organizations for update
to authenticated
using (private.is_org_admin(id) and status <> 'archived'::public.organization_status)
with check (private.is_org_admin(id));

drop policy if exists organization_members_select_v1 on public.organization_members;
create policy organization_members_select_v1
on public.organization_members for select
to authenticated
using (private.can_view_organization(organization_id));

create or replace function public.create_organization(
  p_slug text,
  p_display_name text,
  p_owner_user_id uuid default auth.uid(),
  p_legal_name text default null,
  p_status public.organization_status default 'trial'::public.organization_status,
  p_locale text default 'en-US',
  p_timezone text default 'UTC',
  p_currency text default 'USD',
  p_branding_config jsonb default '{}'::jsonb,
  p_feature_flags jsonb default '{}'::jsonb,
  p_settings jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_organization_id uuid;
  v_slug text := btrim(coalesce(p_slug,''));
  v_display_name text := btrim(coalesce(p_display_name,''));
begin
  if auth.role() <> 'service_role' and not private.is_platform_admin() then
    raise exception 'only a platform admin can create an organization';
  end if;
  if p_owner_user_id is null then
    raise exception 'owner_user_id is required';
  end if;
  if not exists (
    select 1 from public.profiles p
    where p.id = p_owner_user_id and p.status = 'active'::public.profile_status
  ) then
    raise exception 'organization owner must be an active platform user';
  end if;
  if v_slug = '' or v_slug <> lower(v_slug) or v_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' then
    raise exception 'slug must be lowercase kebab-case';
  end if;
  if v_display_name = '' then
    raise exception 'display_name is required';
  end if;
  if p_currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be an ISO-style 3-letter uppercase code';
  end if;
  if jsonb_typeof(coalesce(p_branding_config,'{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(p_feature_flags,'{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(p_settings,'{}'::jsonb)) <> 'object' then
    raise exception 'branding_config, feature_flags and settings must be JSON objects';
  end if;

  insert into public.organizations(
    slug,display_name,legal_name,status,locale,timezone,currency,owner_user_id,
    branding_config,feature_flags,settings
  ) values (
    v_slug,v_display_name,nullif(btrim(coalesce(p_legal_name,'')),''),p_status,
    btrim(p_locale),btrim(p_timezone),p_currency,p_owner_user_id,
    coalesce(p_branding_config,'{}'::jsonb),coalesce(p_feature_flags,'{}'::jsonb),coalesce(p_settings,'{}'::jsonb)
  ) returning id into v_organization_id;

  insert into public.organization_members(
    organization_id,user_id,role,status,joined_at
  ) values (
    v_organization_id,p_owner_user_id,'owner'::public.organization_member_role,
    'active'::public.organization_member_status,now()
  );

  return v_organization_id;
end;
$function$;

revoke all on table public.organizations from public, anon;
revoke all on table public.organization_members from public, anon;
grant select,update on table public.organizations to authenticated;
grant select on table public.organization_members to authenticated;
grant all on table public.organizations to service_role;
grant all on table public.organization_members to service_role;

revoke all on function public.create_organization(text,text,uuid,text,public.organization_status,text,text,text,jsonb,jsonb,jsonb) from public;
grant execute on function public.create_organization(text,text,uuid,text,public.organization_status,text,text,text,jsonb,jsonb,jsonb) to authenticated,service_role;

comment on table public.organizations is 'ARCH-1.0 tenant root. F1.M1.S1.';
comment on table public.organization_members is 'ARCH-1.0 global-user to organization membership bridge. F1.M1.S1 foundation.';
