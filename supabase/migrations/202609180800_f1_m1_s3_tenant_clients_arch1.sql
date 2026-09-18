-- ARCH-1.0 · F1.M1.S3 Clients
-- Canonical tenant-scoped ClientProfile foundation.
-- The legacy public.client_profiles table remains untouched for backward compatibility.

do $$ begin
  create type public.tenant_client_status as enum ('lead','invited','active','paused','archived');
exception when duplicate_object then null;
end $$;

create table if not exists public.tenant_client_profiles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  user_id uuid references public.profiles(id) on delete set null,
  status public.tenant_client_status not null default 'lead',
  display_name text not null,
  contact_email text,
  contact_phone text,
  contact_metadata jsonb not null default '{}'::jsonb,
  onboarding_state text not null default 'not_started',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  constraint tenant_client_profiles_org_id_unique unique (organization_id,id),
  constraint tenant_client_profiles_org_user_unique unique (organization_id,user_id),
  constraint tenant_client_profiles_display_name_not_blank check (length(btrim(display_name)) > 0),
  constraint tenant_client_profiles_contact_metadata_object check (jsonb_typeof(contact_metadata) = 'object'),
  constraint tenant_client_profiles_onboarding_not_blank check (length(btrim(onboarding_state)) > 0),
  constraint tenant_client_profiles_archive_consistency check (
    (status = 'archived' and archived_at is not null)
    or (status <> 'archived' and archived_at is null)
  )
);

create index if not exists idx_tenant_client_profiles_org_status
  on public.tenant_client_profiles(organization_id,status);
create index if not exists idx_tenant_client_profiles_user
  on public.tenant_client_profiles(user_id)
  where user_id is not null;
create index if not exists idx_tenant_client_profiles_org_email
  on public.tenant_client_profiles(organization_id,lower(contact_email))
  where contact_email is not null;

create or replace function private.can_view_tenant_client(
  target_organization uuid,
  target_user uuid
)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select coalesce(
    private.is_org_admin(target_organization)
    or private.is_org_professional(target_organization)
    or (
      target_user is not null
      and target_user = (select auth.uid())
      and private.is_org_member(target_organization)
    ),
    false
  )
$function$;

create or replace function private.guard_tenant_client_profile_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not exists(
    select 1
    from public.organizations o
    where o.id = new.organization_id
      and o.status in ('trial'::public.organization_status,'active'::public.organization_status)
  ) then
    raise exception 'client profile requires an operational organization';
  end if;

  if new.user_id is not null then
    if not exists(
      select 1
      from public.profiles p
      where p.id = new.user_id
        and p.status = 'active'::public.profile_status
    ) then
      raise exception 'linked client user must be an active platform user';
    end if;
    if not exists(
      select 1
      from public.organization_members om
      where om.organization_id = new.organization_id
        and om.user_id = new.user_id
        and om.status = 'active'::public.organization_member_status
    ) then
      raise exception 'linked client user requires an active organization membership';
    end if;
  end if;

  if tg_op = 'UPDATE' then
    if new.organization_id is distinct from old.organization_id then
      raise exception 'client profile organization is immutable';
    end if;
    if old.user_id is not null and new.user_id is distinct from old.user_id then
      raise exception 'linked client user is immutable';
    end if;
    if old.status = 'archived'::public.tenant_client_status
       and new.status <> 'archived'::public.tenant_client_status then
      raise exception 'archived client profile is terminal';
    end if;
  end if;

  new.display_name := btrim(new.display_name);
  new.onboarding_state := btrim(new.onboarding_state);
  if new.contact_email is not null then
    new.contact_email := nullif(lower(btrim(new.contact_email)),'');
  end if;
  if new.contact_phone is not null then
    new.contact_phone := nullif(btrim(new.contact_phone),'');
  end if;

  if new.status = 'archived'::public.tenant_client_status then
    new.archived_at := coalesce(new.archived_at,now());
  else
    new.archived_at := null;
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_tenant_client_profiles_guard_v1 on public.tenant_client_profiles;
create trigger trg_tenant_client_profiles_guard_v1
before insert or update on public.tenant_client_profiles
for each row execute function private.guard_tenant_client_profile_v1();

drop trigger if exists trg_tenant_client_profiles_updated_at_v1 on public.tenant_client_profiles;
create trigger trg_tenant_client_profiles_updated_at_v1
before update on public.tenant_client_profiles
for each row execute function private.set_updated_at();

alter table public.tenant_client_profiles enable row level security;

drop policy if exists tenant_client_profiles_select_v1 on public.tenant_client_profiles;
create policy tenant_client_profiles_select_v1
on public.tenant_client_profiles for select
to authenticated
using (private.can_view_tenant_client(organization_id,user_id));

create or replace function public.create_tenant_client_profile(
  p_organization_id uuid,
  p_display_name text,
  p_user_id uuid default null,
  p_status public.tenant_client_status default 'lead'::public.tenant_client_status,
  p_contact_email text default null,
  p_contact_phone text default null,
  p_contact_metadata jsonb default '{}'::jsonb,
  p_onboarding_state text default 'not_started'
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_client_id uuid;
  v_member public.organization_members%rowtype;
  v_display_name text := btrim(coalesce(p_display_name,''));
begin
  if auth.role() <> 'service_role' then
    raise exception 'tenant client creation is backend-only';
  end if;

  if v_display_name = '' then
    raise exception 'display_name is required';
  end if;
  if btrim(coalesce(p_onboarding_state,'')) = '' then
    raise exception 'onboarding_state is required';
  end if;
  if jsonb_typeof(coalesce(p_contact_metadata,'{}'::jsonb)) <> 'object' then
    raise exception 'contact_metadata must be a JSON object';
  end if;
  if not exists(
    select 1
    from public.organizations o
    where o.id = p_organization_id
      and o.status in ('trial'::public.organization_status,'active'::public.organization_status)
  ) then
    raise exception 'organization is not operational';
  end if;

  if p_user_id is not null then
    if not exists(
      select 1 from public.profiles p
      where p.id = p_user_id
        and p.status = 'active'::public.profile_status
    ) then
      raise exception 'client user must be an active platform user';
    end if;

    if exists(
      select 1 from public.tenant_client_profiles cp
      where cp.organization_id = p_organization_id
        and cp.user_id = p_user_id
    ) then
      raise exception 'user is already linked to a client profile in this organization';
    end if;

    select * into v_member
    from public.organization_members om
    where om.organization_id = p_organization_id
      and om.user_id = p_user_id;

    if not found then
      insert into public.organization_members(
        organization_id,user_id,role,status,joined_at
      ) values(
        p_organization_id,p_user_id,'client'::public.organization_member_role,
        'active'::public.organization_member_status,now()
      );
    elsif v_member.status <> 'active'::public.organization_member_status then
      raise exception 'client organization membership is not active';
    end if;
  end if;

  insert into public.tenant_client_profiles(
    organization_id,user_id,status,display_name,
    contact_email,contact_phone,contact_metadata,onboarding_state
  ) values(
    p_organization_id,p_user_id,p_status,v_display_name,
    nullif(lower(btrim(coalesce(p_contact_email,''))),''),
    nullif(btrim(coalesce(p_contact_phone,'')),''),
    coalesce(p_contact_metadata,'{}'::jsonb),
    btrim(p_onboarding_state)
  )
  returning id into v_client_id;

  return v_client_id;
end;
$function$;

create or replace function public.link_tenant_client_user(
  p_client_id uuid,
  p_user_id uuid
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_client public.tenant_client_profiles%rowtype;
  v_member public.organization_members%rowtype;
begin
  if auth.role() <> 'service_role' then
    raise exception 'tenant client account linking is backend-only';
  end if;

  select * into v_client
  from public.tenant_client_profiles cp
  where cp.id = p_client_id
  for update;

  if not found then
    raise exception 'client profile not found';
  end if;
  if v_client.status = 'archived'::public.tenant_client_status then
    raise exception 'archived client profile cannot be linked';
  end if;
  if v_client.user_id is not null and v_client.user_id <> p_user_id then
    raise exception 'client profile is already linked to another user';
  end if;
  if not exists(
    select 1 from public.profiles p
    where p.id = p_user_id
      and p.status = 'active'::public.profile_status
  ) then
    raise exception 'client user must be an active platform user';
  end if;
  if exists(
    select 1 from public.tenant_client_profiles cp
    where cp.organization_id = v_client.organization_id
      and cp.user_id = p_user_id
      and cp.id <> p_client_id
  ) then
    raise exception 'user is already linked to another client profile in this organization';
  end if;

  select * into v_member
  from public.organization_members om
  where om.organization_id = v_client.organization_id
    and om.user_id = p_user_id;

  if not found then
    insert into public.organization_members(
      organization_id,user_id,role,status,joined_at
    ) values(
      v_client.organization_id,p_user_id,'client'::public.organization_member_role,
      'active'::public.organization_member_status,now()
    );
  elsif v_member.status <> 'active'::public.organization_member_status then
    raise exception 'client organization membership is not active';
  end if;

  update public.tenant_client_profiles
  set user_id = p_user_id,
      status = case
        when status in ('lead'::public.tenant_client_status,'invited'::public.tenant_client_status)
          then 'active'::public.tenant_client_status
        else status
      end
  where id = p_client_id;

  return p_client_id;
end;
$function$;

revoke all on table public.tenant_client_profiles from public,anon;
grant select on table public.tenant_client_profiles to authenticated;
grant all on table public.tenant_client_profiles to service_role;

revoke all on function public.create_tenant_client_profile(uuid,text,uuid,public.tenant_client_status,text,text,jsonb,text) from public;
grant execute on function public.create_tenant_client_profile(uuid,text,uuid,public.tenant_client_status,text,text,jsonb,text) to service_role;

revoke all on function public.link_tenant_client_user(uuid,uuid) from public;
grant execute on function public.link_tenant_client_user(uuid,uuid) to service_role;

comment on table public.tenant_client_profiles is
  'ARCH-1.0 canonical tenant-scoped ClientProfile. F1.M1.S3. Legacy public.client_profiles remains operational until controlled cutover.';
comment on column public.tenant_client_profiles.user_id is
  'Nullable global account link. A client can exist before login/account provisioning.';
