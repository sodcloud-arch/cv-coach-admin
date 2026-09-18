-- ARCH-1.0 · F1.M1.S4 Organization -> Coach -> Client
-- Canonical tenant-scoped operational assignments with history preservation.

do $$ begin
  create type public.client_coach_assignment_role as enum ('primary','secondary');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.client_coach_assignment_status as enum ('active','ended');
exception when duplicate_object then null;
end $$;

-- Composite uniqueness gives future tenant-owned foreign keys a DB-level
-- organization boundary instead of relying on application filters alone.
create unique index if not exists ux_clients_organization_id_id
  on public.clients(organization_id,id);
create unique index if not exists ux_coach_profiles_organization_id_id
  on public.coach_profiles(organization_id,id);

create table if not exists public.client_coach_assignments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  client_id uuid not null,
  coach_id uuid not null,
  assignment_role public.client_coach_assignment_role not null default 'secondary',
  status public.client_coach_assignment_status not null default 'active',
  assigned_at timestamptz not null default now(),
  unassigned_at timestamptz,
  assigned_by uuid references public.profiles(id) on delete set null,
  unassigned_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint client_coach_assignments_client_same_org
    foreign key (organization_id,client_id)
    references public.clients(organization_id,id)
    on delete restrict,
  constraint client_coach_assignments_coach_same_org
    foreign key (organization_id,coach_id)
    references public.coach_profiles(organization_id,id)
    on delete restrict,
  constraint client_coach_assignments_lifecycle check (
    (status='active'::public.client_coach_assignment_status and unassigned_at is null)
    or
    (status='ended'::public.client_coach_assignment_status and unassigned_at is not null)
  )
);

create unique index if not exists ux_client_coach_assignments_one_active_pair
  on public.client_coach_assignments(organization_id,client_id,coach_id)
  where status='active'::public.client_coach_assignment_status;

create unique index if not exists ux_client_coach_assignments_one_active_primary
  on public.client_coach_assignments(organization_id,client_id)
  where status='active'::public.client_coach_assignment_status
    and assignment_role='primary'::public.client_coach_assignment_role;

create index if not exists idx_client_coach_assignments_client_history
  on public.client_coach_assignments(organization_id,client_id,assigned_at desc);
create index if not exists idx_client_coach_assignments_coach_active
  on public.client_coach_assignments(organization_id,coach_id,client_id)
  where status='active'::public.client_coach_assignment_status;
create index if not exists idx_client_coach_assignments_assigned_by
  on public.client_coach_assignments(assigned_by)
  where assigned_by is not null;
create index if not exists idx_client_coach_assignments_unassigned_by
  on public.client_coach_assignments(unassigned_by)
  where unassigned_by is not null;

create or replace function private.can_view_client_coach_assignment(
  target_organization uuid,
  target_client uuid,
  target_coach uuid
)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select coalesce(
    private.is_platform_admin()
    or private.is_org_admin(target_organization)
    or exists(
      select 1
      from public.coach_profiles cp
      where cp.id=target_coach
        and cp.organization_id=target_organization
        and cp.user_id=(select auth.uid())
        and cp.status='active'::public.coach_profile_status
        and private.is_org_member(target_organization)
    )
    or exists(
      select 1
      from public.clients c
      where c.id=target_client
        and c.organization_id=target_organization
        and c.user_id=(select auth.uid())
        and private.is_org_member(target_organization)
    ),
    false
  )
$function$;

create or replace function private.guard_client_coach_assignment_v1()
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
    raise exception 'assignment requires an operational organization';
  end if;

  if new.status='active'::public.client_coach_assignment_status then
    if not exists(
      select 1 from public.clients c
      where c.id=new.client_id
        and c.organization_id=new.organization_id
        and c.status<>'archived'::public.client_status
    ) then
      raise exception 'active assignment requires a non-archived client in the same organization';
    end if;

    if not exists(
      select 1 from public.coach_profiles cp
      join public.organization_members om
        on om.organization_id=cp.organization_id
       and om.user_id=cp.user_id
      where cp.id=new.coach_id
        and cp.organization_id=new.organization_id
        and cp.status='active'::public.coach_profile_status
        and om.status='active'::public.organization_member_status
    ) then
      raise exception 'active assignment requires an active coach and membership in the same organization';
    end if;
  end if;

  if tg_op='UPDATE' then
    if new.organization_id is distinct from old.organization_id
       or new.client_id is distinct from old.client_id
       or new.coach_id is distinct from old.coach_id
       or new.assignment_role is distinct from old.assignment_role
       or new.assigned_at is distinct from old.assigned_at then
      raise exception 'assignment identity is immutable; end it and create a new assignment';
    end if;

    if old.status='ended'::public.client_coach_assignment_status
       and new.status<>'ended'::public.client_coach_assignment_status then
      raise exception 'ended assignment is terminal';
    end if;
  end if;

  if new.status='ended'::public.client_coach_assignment_status then
    new.unassigned_at:=coalesce(new.unassigned_at,now());
  else
    new.unassigned_at:=null;
    new.unassigned_by:=null;
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_client_coach_assignments_guard_v1 on public.client_coach_assignments;
create trigger trg_client_coach_assignments_guard_v1
before insert or update on public.client_coach_assignments
for each row execute function private.guard_client_coach_assignment_v1();

drop trigger if exists trg_client_coach_assignments_updated_at_v1 on public.client_coach_assignments;
create trigger trg_client_coach_assignments_updated_at_v1
before update on public.client_coach_assignments
for each row execute function private.set_updated_at();

alter table public.client_coach_assignments enable row level security;

drop policy if exists client_coach_assignments_select_v1 on public.client_coach_assignments;
create policy client_coach_assignments_select_v1
on public.client_coach_assignments for select
to authenticated
using (
  private.can_view_client_coach_assignment(organization_id,client_id,coach_id)
);

create or replace function public.assign_client_coach(
  p_organization_id uuid,
  p_client_id uuid,
  p_coach_id uuid,
  p_assignment_role public.client_coach_assignment_role default 'secondary'::public.client_coach_assignment_role,
  p_assigned_by uuid default null
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_existing public.client_coach_assignments%rowtype;
  v_assignment_id uuid;
begin
  if auth.role()<>'service_role' then
    raise exception 'client coach assignment is backend-only';
  end if;

  if p_assigned_by is not null and not exists(
    select 1 from public.profiles p
    where p.id=p_assigned_by and p.status='active'::public.profile_status
  ) then
    raise exception 'assigned_by must reference an active platform user';
  end if;

  if not exists(
    select 1 from public.clients c
    where c.id=p_client_id
      and c.organization_id=p_organization_id
      and c.status<>'archived'::public.client_status
  ) then
    raise exception 'client is not assignable in this organization';
  end if;

  if not exists(
    select 1
    from public.coach_profiles cp
    join public.organization_members om
      on om.organization_id=cp.organization_id
     and om.user_id=cp.user_id
    where cp.id=p_coach_id
      and cp.organization_id=p_organization_id
      and cp.status='active'::public.coach_profile_status
      and om.status='active'::public.organization_member_status
  ) then
    raise exception 'coach is not assignable in this organization';
  end if;

  select * into v_existing
  from public.client_coach_assignments a
  where a.organization_id=p_organization_id
    and a.client_id=p_client_id
    and a.coach_id=p_coach_id
    and a.status='active'::public.client_coach_assignment_status
  for update;

  if found and v_existing.assignment_role=p_assignment_role then
    return v_existing.id;
  elsif found then
    update public.client_coach_assignments
    set status='ended'::public.client_coach_assignment_status,
        unassigned_at=now(),
        unassigned_by=p_assigned_by
    where id=v_existing.id;
  end if;

  if p_assignment_role='primary'::public.client_coach_assignment_role then
    update public.client_coach_assignments
    set status='ended'::public.client_coach_assignment_status,
        unassigned_at=now(),
        unassigned_by=p_assigned_by
    where organization_id=p_organization_id
      and client_id=p_client_id
      and assignment_role='primary'::public.client_coach_assignment_role
      and status='active'::public.client_coach_assignment_status;
  end if;

  insert into public.client_coach_assignments(
    organization_id,client_id,coach_id,assignment_role,status,assigned_at,assigned_by
  ) values(
    p_organization_id,p_client_id,p_coach_id,p_assignment_role,
    'active'::public.client_coach_assignment_status,now(),p_assigned_by
  )
  returning id into v_assignment_id;

  return v_assignment_id;
end;
$function$;

create or replace function public.end_client_coach_assignment(
  p_assignment_id uuid,
  p_unassigned_by uuid default null
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_assignment public.client_coach_assignments%rowtype;
begin
  if auth.role()<>'service_role' then
    raise exception 'client coach unassignment is backend-only';
  end if;

  if p_unassigned_by is not null and not exists(
    select 1 from public.profiles p
    where p.id=p_unassigned_by and p.status='active'::public.profile_status
  ) then
    raise exception 'unassigned_by must reference an active platform user';
  end if;

  select * into v_assignment
  from public.client_coach_assignments
  where id=p_assignment_id
  for update;

  if not found then
    raise exception 'assignment not found';
  end if;

  if v_assignment.status='ended'::public.client_coach_assignment_status then
    return v_assignment.id;
  end if;

  update public.client_coach_assignments
  set status='ended'::public.client_coach_assignment_status,
      unassigned_at=now(),
      unassigned_by=p_unassigned_by
  where id=p_assignment_id;

  return p_assignment_id;
end;
$function$;

revoke all on table public.client_coach_assignments from public,anon;
grant select on table public.client_coach_assignments to authenticated;
grant all on table public.client_coach_assignments to service_role;

revoke all on function public.assign_client_coach(uuid,uuid,uuid,public.client_coach_assignment_role,uuid) from public;
grant execute on function public.assign_client_coach(uuid,uuid,uuid,public.client_coach_assignment_role,uuid) to service_role;

revoke all on function public.end_client_coach_assignment(uuid,uuid) from public;
grant execute on function public.end_client_coach_assignment(uuid,uuid) to service_role;

comment on table public.client_coach_assignments is
  'ARCH-1.0 tenant-scoped Coach-to-Client operational assignments with preserved history. F1.M1.S4.';
comment on function public.assign_client_coach(uuid,uuid,uuid,public.client_coach_assignment_role,uuid) is
  'Creates or replaces a tenant-safe assignment. Primary reassignment ends the previous primary instead of deleting history.';
