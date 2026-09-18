-- ARCH-1.0 · F1.M1.S5 Data Isolation — canonical DB hardening
-- Makes tenant ownership explicit on professional child tables, adds same-tenant
-- membership foreign keys, and reduces authenticated table privileges to least privilege.

-- 1) Explicit tenant ownership for coach child tables.
alter table public.coach_profile_disciplines
  add column if not exists organization_id uuid;

alter table public.coach_credentials
  add column if not exists organization_id uuid;

update public.coach_profile_disciplines d
set organization_id=cp.organization_id
from public.coach_profiles cp
where cp.id=d.coach_profile_id
  and d.organization_id is null;

update public.coach_credentials c
set organization_id=cp.organization_id
from public.coach_profiles cp
where cp.id=c.coach_profile_id
  and c.organization_id is null;

do $$
begin
  if exists(
    select 1 from public.coach_profile_disciplines where organization_id is null
  ) then
    raise exception 'F1.M1.S5: coach_profile_disciplines tenant backfill incomplete';
  end if;
  if exists(
    select 1 from public.coach_credentials where organization_id is null
  ) then
    raise exception 'F1.M1.S5: coach_credentials tenant backfill incomplete';
  end if;
end $$;

alter table public.coach_profile_disciplines
  alter column organization_id set not null;
alter table public.coach_credentials
  alter column organization_id set not null;

alter table public.coach_profile_disciplines
  add constraint coach_profile_disciplines_organization_id_fkey
  foreign key (organization_id)
  references public.organizations(id)
  on delete restrict;

alter table public.coach_profile_disciplines
  add constraint coach_profile_disciplines_same_org
  foreign key (organization_id,coach_profile_id)
  references public.coach_profiles(organization_id,id)
  on delete cascade;

alter table public.coach_credentials
  add constraint coach_credentials_organization_id_fkey
  foreign key (organization_id)
  references public.organizations(id)
  on delete restrict;

alter table public.coach_credentials
  add constraint coach_credentials_same_org
  foreign key (organization_id,coach_profile_id)
  references public.coach_profiles(organization_id,id)
  on delete cascade;

create index if not exists idx_coach_disciplines_org_profile
  on public.coach_profile_disciplines(organization_id,coach_profile_id,discipline);

create index if not exists idx_coach_credentials_org_profile_status
  on public.coach_credentials(organization_id,coach_profile_id,verification_status);

-- 2) Child-table guards keep older backend call sites compatible while making
-- organization_id immutable and derived from the canonical parent.
create or replace function private.guard_coach_discipline_tenant_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_organization_id uuid;
begin
  select cp.organization_id into v_organization_id
  from public.coach_profiles cp
  where cp.id=new.coach_profile_id;

  if v_organization_id is null then
    raise exception 'coach discipline requires a valid coach profile';
  end if;

  if new.organization_id is null then
    new.organization_id:=v_organization_id;
  elsif new.organization_id<>v_organization_id then
    raise exception 'coach discipline cannot cross organization boundary';
  end if;

  if tg_op='UPDATE' and (
    new.organization_id is distinct from old.organization_id
    or new.coach_profile_id is distinct from old.coach_profile_id
  ) then
    raise exception 'coach discipline tenant identity is immutable';
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_coach_disciplines_tenant_v1
  on public.coach_profile_disciplines;
create trigger trg_coach_disciplines_tenant_v1
before insert or update on public.coach_profile_disciplines
for each row execute function private.guard_coach_discipline_tenant_v1();

create or replace function private.guard_coach_credential_v2()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_organization_id uuid;
begin
  select cp.organization_id into v_organization_id
  from public.coach_profiles cp
  where cp.id=new.coach_profile_id;

  if v_organization_id is null then
    raise exception 'coach credential requires a valid coach profile';
  end if;

  if new.organization_id is null then
    new.organization_id:=v_organization_id;
  elsif new.organization_id<>v_organization_id then
    raise exception 'coach credential cannot cross organization boundary';
  end if;

  if tg_op='UPDATE' and (
    new.organization_id is distinct from old.organization_id
    or new.coach_profile_id is distinct from old.coach_profile_id
  ) then
    raise exception 'coach credential tenant identity is immutable';
  end if;

  new.credential_type:=btrim(new.credential_type);
  if new.country_code is not null then
    new.country_code:=upper(btrim(new.country_code));
  end if;
  if new.verification_status='verified'::public.credential_verification_status
     and new.verified_at is null then
    new.verified_at:=now();
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_coach_credentials_guard_v1
  on public.coach_credentials;
drop trigger if exists trg_coach_credentials_guard_v2
  on public.coach_credentials;
create trigger trg_coach_credentials_guard_v2
before insert or update on public.coach_credentials
for each row execute function private.guard_coach_credential_v2();

-- 3) RLS now scopes professional child records directly by organization_id.
drop policy if exists coach_profile_disciplines_select_v1
  on public.coach_profile_disciplines;
create policy coach_profile_disciplines_select_v2
on public.coach_profile_disciplines for select
to authenticated
using (private.can_view_organization(organization_id));

drop policy if exists coach_credentials_select_v1
  on public.coach_credentials;
create policy coach_credentials_select_v2
on public.coach_credentials for select
to authenticated
using (
  private.is_org_admin(organization_id)
  or exists(
    select 1
    from public.coach_profiles cp
    where cp.organization_id=coach_credentials.organization_id
      and cp.id=coach_credentials.coach_profile_id
      and cp.user_id=(select auth.uid())
  )
);

-- 4) Same-tenant membership constraints. A global User id alone is never
-- enough to create a tenant relationship.
alter table public.coach_profiles
  add constraint coach_profiles_member_same_org
  foreign key (organization_id,user_id)
  references public.organization_members(organization_id,user_id)
  on delete restrict;

alter table public.clients
  add constraint clients_user_member_same_org
  foreign key (organization_id,user_id)
  references public.organization_members(organization_id,user_id)
  on delete restrict;

alter table public.clients
  add constraint clients_created_by_member_same_org
  foreign key (organization_id,created_by)
  references public.organization_members(organization_id,user_id)
  on delete restrict;

alter table public.coach_credentials
  add constraint coach_credentials_verified_by_member_same_org
  foreign key (organization_id,verified_by)
  references public.organization_members(organization_id,user_id)
  on delete restrict;

alter table public.client_coach_assignments
  add constraint client_coach_assignments_assigned_by_member_same_org
  foreign key (organization_id,assigned_by)
  references public.organization_members(organization_id,user_id)
  on delete restrict;

alter table public.client_coach_assignments
  add constraint client_coach_assignments_unassigned_by_member_same_org
  foreign key (organization_id,unassigned_by)
  references public.organization_members(organization_id,user_id)
  on delete restrict;

-- 5) Least privilege. RLS is not a substitute for removing dangerous table
-- privileges such as TRUNCATE/TRIGGER/REFERENCES from browser roles.
revoke all privileges on table public.organizations
  from public,anon,authenticated;
revoke all privileges on table public.organization_members
  from public,anon,authenticated;
revoke all privileges on table public.coach_profiles
  from public,anon,authenticated;
revoke all privileges on table public.coach_profile_disciplines
  from public,anon,authenticated;
revoke all privileges on table public.coach_credentials
  from public,anon,authenticated;
revoke all privileges on table public.clients
  from public,anon,authenticated;
revoke all privileges on table public.client_coach_assignments
  from public,anon,authenticated;

grant select on table public.organizations to authenticated;
grant update (
  display_name,
  legal_name,
  locale,
  timezone,
  currency,
  branding_config,
  settings
) on table public.organizations to authenticated;

grant select on table public.organization_members to authenticated;
grant select on table public.coach_profiles to authenticated;
grant select on table public.coach_profile_disciplines to authenticated;
grant select on table public.coach_credentials to authenticated;
grant select on table public.clients to authenticated;
grant select on table public.client_coach_assignments to authenticated;

-- Service role remains the only general-purpose mutation principal.
grant all privileges on table public.organizations to service_role;
grant all privileges on table public.organization_members to service_role;
grant all privileges on table public.coach_profiles to service_role;
grant all privileges on table public.coach_profile_disciplines to service_role;
grant all privileges on table public.coach_credentials to service_role;
grant all privileges on table public.clients to service_role;
grant all privileges on table public.client_coach_assignments to service_role;

comment on column public.coach_profile_disciplines.organization_id is
  'ARCH-1.0 F1.M1.S5 explicit tenant boundary; must match coach_profile.organization_id.';
comment on column public.coach_credentials.organization_id is
  'ARCH-1.0 F1.M1.S5 explicit tenant boundary; must match coach_profile.organization_id.';
