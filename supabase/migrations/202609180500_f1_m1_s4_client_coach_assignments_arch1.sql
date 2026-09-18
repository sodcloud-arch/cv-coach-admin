-- ARCH-1.0 · F1.M1.S4 Organization -> Coach -> Client
-- Canonical tenant-scoped coach/client assignment layer with preserved history.

do $$ begin
  create type public.client_coach_assignment_role as enum ('primary','secondary');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.client_coach_assignment_status as enum ('active','ended');
exception when duplicate_object then null;
end $$;

-- Composite uniqueness supports database-enforced same-tenant foreign keys.
create unique index if not exists idx_clients_org_id_unique
  on public.clients(organization_id,id);

create unique index if not exists idx_coach_profiles_org_id_unique
  on public.coach_profiles(organization_id,id);

create table if not exists public.client_coach_assignments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  client_id uuid not null,
  coach_profile_id uuid not null,
  assignment_role public.client_coach_assignment_role not null default 'primary',
  status public.client_coach_assignment_status not null default 'active',
  assigned_at timestamptz not null default now(),
  unassigned_at timestamptz,
  assigned_by uuid references public.profiles(id) on delete set null,
  unassigned_by uuid references public.profiles(id) on delete set null,
  end_reason text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint client_coach_assignments_client_tenant_fk
    foreign key (organization_id,client_id)
    references public.clients(organization_id,id)
    on delete restrict,

  constraint client_coach_assignments_coach_tenant_fk
    foreign key (organization_id,coach_profile_id)
    references public.coach_profiles(organization_id,id)
    on delete restrict,

  constraint client_coach_assignments_metadata_object
    check (jsonb_typeof(metadata)='object'),

  constraint client_coach_assignments_lifecycle_consistency
    check (
      (status='active' and unassigned_at is null)
      or
      (status='ended' and unassigned_at is not null)
    )
);

create unique index if not exists idx_client_coach_one_active_primary
  on public.client_coach_assignments(organization_id,client_id)
  where status='active'::public.client_coach_assignment_status
    and assignment_role='primary'::public.client_coach_assignment_role;

create unique index if not exists idx_client_coach_one_active_pair
  on public.client_coach_assignments(organization_id,client_id,coach_profile_id)
  where status='active'::public.client_coach_assignment_status;

create index if not exists idx_client_coach_by_coach_active
  on public.client_coach_assignments(organization_id,coach_profile_id,client_id)
  where status='active'::public.client_coach_assignment_status;

create index if not exists idx_client_coach_by_client_history
  on public.client_coach_assignments(organization_id,client_id,assigned_at desc);

create index if not exists idx_client_coach_assigned_by
  on public.client_coach_assignments(assigned_by)
  where assigned_by is not null;

create index if not exists idx_client_coach_unassigned_by
  on public.client_coach_assignments(unassigned_by)
  where unassigned_by is not null;

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

  if not exists(
    select 1 from public.clients c
    where c.id=new.client_id
      and c.organization_id=new.organization_id
      and c.status<>'archived'::public.client_status
  ) then
    raise exception 'assignment client must belong to the same organization and be non-archived';
  end if;

  if not exists(
    select 1
    from public.coach_profiles cp
    join public.organization_members om
      on om.organization_id=cp.organization_id
     and om.user_id=cp.user_id
    where cp.id=new.coach_profile_id
      and cp.organization_id=new.organization_id
      and cp.status='active'::public.coach_profile_status
      and om.status='active'::public.organization_member_status
  ) then
    raise exception 'assignment coach must be an active professional in the same organization';
  end if;

  if tg_op='UPDATE' then
    if new.organization_id is distinct from old.organization_id
       or new.client_id is distinct from old.client_id
       or new.coach_profile_id is distinct from old.coach_profile_id
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
    new.end_reason:=null;
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

create or replace function private.can_view_client_assignment(target_assignment uuid)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select coalesce(
    auth.role()='service_role'
    or exists(
      select 1
      from public.client_coach_assignments a
      join public.coach_profiles cp
        on cp.id=a.coach_profile_id
       and cp.organization_id=a.organization_id
      join public.clients c
        on c.id=a.client_id
       and c.organization_id=a.organization_id
      where a.id=target_assignment
        and (
          private.is_platform_admin()
          or private.is_org_admin(a.organization_id)
          or (
            cp.user_id=(select auth.uid())
            and private.is_org_member(a.organization_id)
          )
          or (
            c.user_id=(select auth.uid())
            and private.is_org_member(a.organization_id)
          )
        )
    ),
    false
  )
$function$;

alter table public.client_coach_assignments enable row level security;

drop policy if exists client_coach_assignments_select_v1 on public.client_coach_assignments;
create policy client_coach_assignments_select_v1
on public.client_coach_assignments for select
to authenticated
using (private.can_view_client_assignment(id));

create or replace function public.assign_client_coach(
  p_client_id uuid,
  p_coach_profile_id uuid,
  p_assignment_role public.client_coach_assignment_role default 'primary'::public.client_coach_assignment_role,
  p_assigned_by uuid default null,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_client public.clients%rowtype;
  v_coach public.coach_profiles%rowtype;
  v_existing public.client_coach_assignments%rowtype;
  v_assignment_id uuid;
begin
  if auth.role()<>'service_role' then
    raise exception 'client/coach assignment is backend-only';
  end if;

  if jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then
    raise exception 'assignment metadata must be a JSON object';
  end if;

  select * into v_client
  from public.clients
  where id=p_client_id
  for update;

  if not found then raise exception 'client not found'; end if;
  if v_client.status='archived'::public.client_status then
    raise exception 'archived client cannot be assigned';
  end if;

  select * into v_coach
  from public.coach_profiles
  where id=p_coach_profile_id
  for update;

  if not found then raise exception 'coach profile not found'; end if;
  if v_coach.organization_id<>v_client.organization_id then
    raise exception 'coach and client must belong to the same organization';
  end if;
  if v_coach.status<>'active'::public.coach_profile_status then
    raise exception 'coach profile is not active';
  end if;
  if not exists(
    select 1 from public.organization_members om
    where om.organization_id=v_client.organization_id
      and om.user_id=v_coach.user_id
      and om.status='active'::public.organization_member_status
  ) then
    raise exception 'coach organization membership is not active';
  end if;
  if not exists(
    select 1 from public.organizations o
    where o.id=v_client.organization_id
      and o.status in ('trial'::public.organization_status,'active'::public.organization_status)
  ) then
    raise exception 'organization is not operational';
  end if;

  if p_assigned_by is not null
     and not exists(
       select 1 from public.profiles p
       where p.id=p_assigned_by and p.status='active'::public.profile_status
     ) then
    raise exception 'assigned_by must be an active platform user';
  end if;

  select * into v_existing
  from public.client_coach_assignments a
  where a.organization_id=v_client.organization_id
    and a.client_id=v_client.id
    and a.coach_profile_id=v_coach.id
    and a.status='active'::public.client_coach_assignment_status
  for update;

  if found then
    if v_existing.assignment_role=p_assignment_role then
      return v_existing.id;
    end if;

    update public.client_coach_assignments
    set status='ended'::public.client_coach_assignment_status,
        unassigned_by=p_assigned_by,
        end_reason='role_changed'
    where id=v_existing.id;
  end if;

  if p_assignment_role='primary'::public.client_coach_assignment_role then
    update public.client_coach_assignments
    set status='ended'::public.client_coach_assignment_status,
        unassigned_by=p_assigned_by,
        end_reason='primary_reassigned'
    where organization_id=v_client.organization_id
      and client_id=v_client.id
      and status='active'::public.client_coach_assignment_status
      and assignment_role='primary'::public.client_coach_assignment_role;
  end if;

  insert into public.client_coach_assignments(
    organization_id,client_id,coach_profile_id,assignment_role,status,
    assigned_at,assigned_by,metadata
  ) values (
    v_client.organization_id,v_client.id,v_coach.id,p_assignment_role,
    'active'::public.client_coach_assignment_status,now(),p_assigned_by,
    coalesce(p_metadata,'{}'::jsonb)
  )
  returning id into v_assignment_id;

  return v_assignment_id;
end;
$function$;

create or replace function public.end_client_coach_assignment(
  p_assignment_id uuid,
  p_unassigned_by uuid default null,
  p_reason text default null
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
    raise exception 'client/coach assignment updates are backend-only';
  end if;

  select * into v_assignment
  from public.client_coach_assignments
  where id=p_assignment_id
  for update;

  if not found then raise exception 'assignment not found'; end if;
  if v_assignment.status='ended'::public.client_coach_assignment_status then
    return v_assignment.id;
  end if;

  if p_unassigned_by is not null
     and not exists(
       select 1 from public.profiles p
       where p.id=p_unassigned_by and p.status='active'::public.profile_status
     ) then
    raise exception 'unassigned_by must be an active platform user';
  end if;

  update public.client_coach_assignments
  set status='ended'::public.client_coach_assignment_status,
      unassigned_by=p_unassigned_by,
      end_reason=nullif(btrim(coalesce(p_reason,'')),'')
  where id=v_assignment.id;

  return v_assignment.id;
end;
$function$;

revoke all on table public.client_coach_assignments from public,anon;
grant select on table public.client_coach_assignments to authenticated;
grant all on table public.client_coach_assignments to service_role;

revoke all on function public.assign_client_coach(uuid,uuid,public.client_coach_assignment_role,uuid,jsonb) from public;
grant execute on function public.assign_client_coach(uuid,uuid,public.client_coach_assignment_role,uuid,jsonb) to service_role;

revoke all on function public.end_client_coach_assignment(uuid,uuid,text) from public;
grant execute on function public.end_client_coach_assignment(uuid,uuid,text) to service_role;

comment on table public.client_coach_assignments is
  'ARCH-1.0 canonical tenant-scoped Coach<->Client assignments with history. F1.M1.S4.';
comment on function public.assign_client_coach(uuid,uuid,public.client_coach_assignment_role,uuid,jsonb) is
  'Creates primary/secondary assignment; assigning a new primary closes the old primary without deleting history.';
