-- ARCH-1.0 · F1.M1.S2 Coaches / Professionals
-- Adds tenant-scoped professional identity without changing legacy coach relations.

do $$ begin
  create type public.coach_profile_status as enum ('active','inactive','suspended','archived');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.professional_discipline as enum ('training','nutrition','integrated','other');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.credential_verification_status as enum ('self_reported','pending','verified','rejected','expired');
exception when duplicate_object then null;
end $$;

create table if not exists public.coach_profiles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  user_id uuid not null references public.profiles(id) on delete restrict,
  display_name text not null,
  status public.coach_profile_status not null default 'active',
  bio text,
  capacity_clients integer,
  media jsonb not null default '{}'::jsonb,
  capabilities jsonb not null default '{}'::jsonb,
  practice_scope jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  constraint coach_profiles_org_user_unique unique (organization_id,user_id),
  constraint coach_profiles_display_name_not_blank check (length(btrim(display_name)) > 0),
  constraint coach_profiles_capacity_nonnegative check (capacity_clients is null or capacity_clients >= 0),
  constraint coach_profiles_media_object check (jsonb_typeof(media) = 'object'),
  constraint coach_profiles_capabilities_object check (jsonb_typeof(capabilities) = 'object'),
  constraint coach_profiles_scope_object check (jsonb_typeof(practice_scope) = 'object'),
  constraint coach_profiles_archive_consistency check (
    (status = 'archived' and archived_at is not null)
    or (status <> 'archived' and archived_at is null)
  )
);

create table if not exists public.coach_profile_disciplines (
  id uuid primary key default gen_random_uuid(),
  coach_profile_id uuid not null references public.coach_profiles(id) on delete cascade,
  discipline public.professional_discipline not null,
  is_primary boolean not null default false,
  practice_scope jsonb not null default '{}'::jsonb,
  capabilities jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint coach_profile_disciplines_unique unique (coach_profile_id,discipline),
  constraint coach_profile_disciplines_scope_object check (jsonb_typeof(practice_scope) = 'object'),
  constraint coach_profile_disciplines_capabilities_object check (jsonb_typeof(capabilities) = 'object')
);

create unique index if not exists idx_coach_profile_one_primary_discipline
  on public.coach_profile_disciplines(coach_profile_id)
  where is_primary;

create table if not exists public.coach_credentials (
  id uuid primary key default gen_random_uuid(),
  coach_profile_id uuid not null references public.coach_profiles(id) on delete cascade,
  discipline public.professional_discipline,
  credential_type text not null,
  issuing_authority text,
  credential_number text,
  jurisdiction text,
  country_code text,
  verification_status public.credential_verification_status not null default 'self_reported',
  verification_source text,
  verified_by uuid references public.profiles(id) on delete set null,
  verified_at timestamptz,
  expires_on date,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint coach_credentials_type_not_blank check (length(btrim(credential_type)) > 0),
  constraint coach_credentials_country_format check (country_code is null or country_code ~ '^[A-Z]{2}$'),
  constraint coach_credentials_metadata_object check (jsonb_typeof(metadata) = 'object'),
  constraint coach_credentials_verified_consistency check (
    verification_status <> 'verified' or verified_at is not null
  )
);

create index if not exists idx_coach_profiles_organization_status
  on public.coach_profiles(organization_id,status);
create index if not exists idx_coach_profiles_user
  on public.coach_profiles(user_id);
create index if not exists idx_coach_disciplines_profile
  on public.coach_profile_disciplines(coach_profile_id,discipline);
create index if not exists idx_coach_credentials_profile_status
  on public.coach_credentials(coach_profile_id,verification_status);
create index if not exists idx_coach_credentials_verified_by
  on public.coach_credentials(verified_by)
  where verified_by is not null;

create or replace function private.is_org_professional(
  target_organization uuid,
  target_user uuid default auth.uid()
)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select coalesce(exists(
    select 1
    from public.coach_profiles cp
    where cp.organization_id = target_organization
      and cp.user_id = target_user
      and cp.status = 'active'::public.coach_profile_status
  ),false)
$function$;

create or replace function private.guard_coach_profile_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not exists(
    select 1 from public.organizations o
    where o.id=new.organization_id
      and o.status in ('trial'::public.organization_status,'active'::public.organization_status)
  ) then
    raise exception 'coach profile requires an operational organization';
  end if;

  if not exists(
    select 1 from public.organization_members om
    where om.organization_id=new.organization_id
      and om.user_id=new.user_id
      and om.status='active'::public.organization_member_status
  ) then
    raise exception 'coach profile requires an active organization membership';
  end if;

  if tg_op='UPDATE' then
    if new.organization_id is distinct from old.organization_id or new.user_id is distinct from old.user_id then
      raise exception 'coach profile organization and user are immutable';
    end if;
    if old.status='archived'::public.coach_profile_status
       and new.status<>'archived'::public.coach_profile_status then
      raise exception 'archived coach profile is terminal';
    end if;
  end if;

  new.display_name:=btrim(new.display_name);
  if new.status='archived'::public.coach_profile_status then
    new.archived_at:=coalesce(new.archived_at,now());
  else
    new.archived_at:=null;
  end if;
  return new;
end;
$function$;

create or replace function private.guard_coach_credential_v1()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
  new.credential_type:=btrim(new.credential_type);
  if new.country_code is not null then new.country_code:=upper(btrim(new.country_code)); end if;
  if new.verification_status='verified'::public.credential_verification_status and new.verified_at is null then
    new.verified_at:=now();
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_coach_profiles_guard_v1 on public.coach_profiles;
create trigger trg_coach_profiles_guard_v1
before insert or update on public.coach_profiles
for each row execute function private.guard_coach_profile_v1();

drop trigger if exists trg_coach_profiles_updated_at_v1 on public.coach_profiles;
create trigger trg_coach_profiles_updated_at_v1
before update on public.coach_profiles
for each row execute function private.set_updated_at();

drop trigger if exists trg_coach_disciplines_updated_at_v1 on public.coach_profile_disciplines;
create trigger trg_coach_disciplines_updated_at_v1
before update on public.coach_profile_disciplines
for each row execute function private.set_updated_at();

drop trigger if exists trg_coach_credentials_guard_v1 on public.coach_credentials;
create trigger trg_coach_credentials_guard_v1
before insert or update on public.coach_credentials
for each row execute function private.guard_coach_credential_v1();

drop trigger if exists trg_coach_credentials_updated_at_v1 on public.coach_credentials;
create trigger trg_coach_credentials_updated_at_v1
before update on public.coach_credentials
for each row execute function private.set_updated_at();

alter table public.coach_profiles enable row level security;
alter table public.coach_profile_disciplines enable row level security;
alter table public.coach_credentials enable row level security;

drop policy if exists coach_profiles_select_v1 on public.coach_profiles;
create policy coach_profiles_select_v1
on public.coach_profiles for select
to authenticated
using (private.can_view_organization(organization_id));

drop policy if exists coach_profile_disciplines_select_v1 on public.coach_profile_disciplines;
create policy coach_profile_disciplines_select_v1
on public.coach_profile_disciplines for select
to authenticated
using (
  exists(
    select 1 from public.coach_profiles cp
    where cp.id=coach_profile_id
      and private.can_view_organization(cp.organization_id)
  )
);

drop policy if exists coach_credentials_select_v1 on public.coach_credentials;
create policy coach_credentials_select_v1
on public.coach_credentials for select
to authenticated
using (
  exists(
    select 1 from public.coach_profiles cp
    where cp.id=coach_profile_id
      and (cp.user_id=auth.uid() or private.is_org_admin(cp.organization_id))
  )
);

create or replace function public.create_coach_profile(
  p_organization_id uuid,
  p_user_id uuid,
  p_display_name text default null,
  p_primary_discipline public.professional_discipline default 'training'::public.professional_discipline,
  p_additional_disciplines public.professional_discipline[] default '{}'::public.professional_discipline[],
  p_bio text default null,
  p_capacity_clients integer default null,
  p_media jsonb default '{}'::jsonb,
  p_capabilities jsonb default '{}'::jsonb,
  p_practice_scope jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_coach_profile_id uuid;
  v_display_name text;
  v_discipline public.professional_discipline;
  v_member public.organization_members%rowtype;
begin
  if auth.role()<>'service_role' then
    raise exception 'coach profile creation is backend-only';
  end if;

  if not exists(
    select 1 from public.organizations o
    where o.id=p_organization_id
      and o.status in ('trial'::public.organization_status,'active'::public.organization_status)
  ) then
    raise exception 'organization is not operational';
  end if;

  if not exists(
    select 1 from public.profiles p
    where p.id=p_user_id and p.status='active'::public.profile_status
  ) then
    raise exception 'professional must be an active platform user';
  end if;

  select * into v_member
  from public.organization_members om
  where om.organization_id=p_organization_id and om.user_id=p_user_id;

  if not found then
    insert into public.organization_members(organization_id,user_id,role,status,joined_at)
    values(p_organization_id,p_user_id,'coach'::public.organization_member_role,'active'::public.organization_member_status,now());
  elsif v_member.status<>'active'::public.organization_member_status then
    raise exception 'professional organization membership is not active';
  end if;

  select coalesce(
    nullif(btrim(coalesce(p_display_name,'')),''),
    nullif(btrim(concat_ws(' ',p.first_name,p.last_name)),''),
    'Professional'
  ) into v_display_name
  from public.profiles p where p.id=p_user_id;

  insert into public.coach_profiles(
    organization_id,user_id,display_name,status,bio,capacity_clients,media,capabilities,practice_scope
  ) values(
    p_organization_id,p_user_id,v_display_name,'active'::public.coach_profile_status,
    nullif(btrim(coalesce(p_bio,'')),''),p_capacity_clients,
    coalesce(p_media,'{}'::jsonb),coalesce(p_capabilities,'{}'::jsonb),coalesce(p_practice_scope,'{}'::jsonb)
  ) returning id into v_coach_profile_id;

  insert into public.coach_profile_disciplines(coach_profile_id,discipline,is_primary)
  values(v_coach_profile_id,p_primary_discipline,true);

  foreach v_discipline in array coalesce(p_additional_disciplines,'{}'::public.professional_discipline[])
  loop
    if v_discipline<>p_primary_discipline then
      insert into public.coach_profile_disciplines(coach_profile_id,discipline,is_primary)
      values(v_coach_profile_id,v_discipline,false)
      on conflict (coach_profile_id,discipline) do nothing;
    end if;
  end loop;

  return v_coach_profile_id;
end;
$function$;

revoke all on table public.coach_profiles from public,anon;
revoke all on table public.coach_profile_disciplines from public,anon;
revoke all on table public.coach_credentials from public,anon;
grant select on table public.coach_profiles to authenticated;
grant select on table public.coach_profile_disciplines to authenticated;
grant select on table public.coach_credentials to authenticated;
grant all on table public.coach_profiles to service_role;
grant all on table public.coach_profile_disciplines to service_role;
grant all on table public.coach_credentials to service_role;

revoke all on function public.create_coach_profile(uuid,uuid,text,public.professional_discipline,public.professional_discipline[],text,integer,jsonb,jsonb,jsonb) from public;
grant execute on function public.create_coach_profile(uuid,uuid,text,public.professional_discipline,public.professional_discipline[],text,integer,jsonb,jsonb,jsonb) to service_role;

comment on table public.coach_profiles is 'ARCH-1.0 tenant-scoped professional identity. F1.M1.S2.';
comment on table public.coach_profile_disciplines is 'Professional disciplines are descriptive scope, not authorization by themselves.';
comment on table public.coach_credentials is 'Professional credential records with self-reported vs verified state.';
