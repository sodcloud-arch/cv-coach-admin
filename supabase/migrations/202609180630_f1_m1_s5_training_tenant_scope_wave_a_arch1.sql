-- ARCH-1.0 · F1.M1.S5 Data Isolation · Wave A
-- Propagates tenant scope through the critical training graph while preserving
-- legacy client_id/coach_id semantics and existing application write contracts.

create or replace function private.resolve_training_organization_v1(
  p_client_user_id uuid,
  p_coach_user_id uuid
)
returns uuid
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_organizations uuid[];
begin
  if p_client_user_id is null or p_coach_user_id is null then
    raise exception 'client and coach user ids are required to resolve organization';
  end if;

  select array_agg(distinct c.organization_id)
    into v_organizations
  from public.clients c
  join public.coach_profiles cp
    on cp.organization_id=c.organization_id
   and cp.user_id=p_coach_user_id
   and cp.status='active'::public.coach_profile_status
  join public.client_coach_assignments a
    on a.organization_id=c.organization_id
   and a.client_id=c.id
   and a.coach_id=cp.id
   and a.status='active'::public.client_coach_assignment_status
  join public.organization_members cm
    on cm.organization_id=c.organization_id
   and cm.user_id=p_client_user_id
   and cm.status='active'::public.organization_member_status
  join public.organization_members pm
    on pm.organization_id=c.organization_id
   and pm.user_id=p_coach_user_id
   and pm.status='active'::public.organization_member_status
  join public.organizations o
    on o.id=c.organization_id
   and o.status in ('trial'::public.organization_status,'active'::public.organization_status)
  where c.user_id=p_client_user_id
    and c.status<>'archived'::public.client_status;

  if v_organizations is null or cardinality(v_organizations)=0 then
    raise exception 'no active tenant context resolves client % and coach %',
      p_client_user_id,p_coach_user_id;
  end if;

  if cardinality(v_organizations)<>1 then
    raise exception 'ambiguous tenant context for client % and coach %',
      p_client_user_id,p_coach_user_id;
  end if;

  return v_organizations[1];
end;
$function$;

alter table public.programs
  add column if not exists organization_id uuid;
alter table public.program_days
  add column if not exists organization_id uuid;
alter table public.program_exercises
  add column if not exists organization_id uuid;
alter table public.workout_sessions
  add column if not exists organization_id uuid;
alter table public.session_exercises
  add column if not exists organization_id uuid;
alter table public.set_logs
  add column if not exists organization_id uuid;

-- Backfill without firing business side-effect triggers.
alter table public.programs disable trigger user;
update public.programs p
set organization_id=private.resolve_training_organization_v1(p.client_id,p.coach_id)
where p.organization_id is null;
alter table public.programs enable trigger user;

alter table public.program_days disable trigger user;
update public.program_days d
set organization_id=p.organization_id
from public.programs p
where p.id=d.program_id
  and d.organization_id is null;
alter table public.program_days enable trigger user;

alter table public.program_exercises disable trigger user;
update public.program_exercises pe
set organization_id=d.organization_id
from public.program_days d
where d.id=pe.program_day_id
  and pe.organization_id is null;
alter table public.program_exercises enable trigger user;

alter table public.workout_sessions disable trigger user;
update public.workout_sessions ws
set organization_id=p.organization_id
from public.programs p
where p.id=ws.program_id
  and ws.organization_id is null;
alter table public.workout_sessions enable trigger user;

alter table public.session_exercises disable trigger user;
update public.session_exercises se
set organization_id=ws.organization_id
from public.workout_sessions ws
where ws.id=se.workout_session_id
  and se.organization_id is null;
alter table public.session_exercises enable trigger user;

alter table public.set_logs disable trigger user;
update public.set_logs sl
set organization_id=se.organization_id
from public.session_exercises se
where se.id=sl.session_exercise_id
  and sl.organization_id is null;
alter table public.set_logs enable trigger user;

do $$
begin
  if exists(select 1 from public.programs where organization_id is null)
     or exists(select 1 from public.program_days where organization_id is null)
     or exists(select 1 from public.program_exercises where organization_id is null)
     or exists(select 1 from public.workout_sessions where organization_id is null)
     or exists(select 1 from public.session_exercises where organization_id is null)
     or exists(select 1 from public.set_logs where organization_id is null) then
    raise exception 'Wave A tenant backfill left unscoped rows';
  end if;
end $$;

alter table public.programs alter column organization_id set not null;
alter table public.program_days alter column organization_id set not null;
alter table public.program_exercises alter column organization_id set not null;
alter table public.workout_sessions alter column organization_id set not null;
alter table public.session_exercises alter column organization_id set not null;
alter table public.set_logs alter column organization_id set not null;

-- Composite identities provide physical same-tenant FK boundaries.
create unique index if not exists ux_programs_organization_id_id
  on public.programs(organization_id,id);
create unique index if not exists ux_program_days_organization_id_id
  on public.program_days(organization_id,id);
create unique index if not exists ux_program_days_organization_id_id_program
  on public.program_days(organization_id,id,program_id);
create unique index if not exists ux_program_exercises_organization_id_id
  on public.program_exercises(organization_id,id);
create unique index if not exists ux_workout_sessions_organization_id_id
  on public.workout_sessions(organization_id,id);
create unique index if not exists ux_session_exercises_organization_id_id
  on public.session_exercises(organization_id,id);
create unique index if not exists ux_set_logs_organization_id_id
  on public.set_logs(organization_id,id);

alter table public.programs
  add constraint programs_organization_id_fkey
  foreign key (organization_id)
  references public.organizations(id)
  on delete restrict;

alter table public.program_days
  add constraint program_days_organization_id_fkey
  foreign key (organization_id)
  references public.organizations(id)
  on delete restrict;

alter table public.program_days
  add constraint program_days_program_same_org
  foreign key (organization_id,program_id)
  references public.programs(organization_id,id)
  on delete cascade;

alter table public.program_exercises
  add constraint program_exercises_organization_id_fkey
  foreign key (organization_id)
  references public.organizations(id)
  on delete restrict;

alter table public.program_exercises
  add constraint program_exercises_day_same_org
  foreign key (organization_id,program_day_id)
  references public.program_days(organization_id,id)
  on delete cascade;

alter table public.workout_sessions
  add constraint workout_sessions_organization_id_fkey
  foreign key (organization_id)
  references public.organizations(id)
  on delete restrict;

alter table public.workout_sessions
  add constraint workout_sessions_program_same_org
  foreign key (organization_id,program_id)
  references public.programs(organization_id,id)
  on delete restrict;

alter table public.workout_sessions
  add constraint workout_sessions_program_day_same_org
  foreign key (organization_id,program_day_id,program_id)
  references public.program_days(organization_id,id,program_id)
  on delete restrict;

alter table public.session_exercises
  add constraint session_exercises_organization_id_fkey
  foreign key (organization_id)
  references public.organizations(id)
  on delete restrict;

alter table public.session_exercises
  add constraint session_exercises_workout_same_org
  foreign key (organization_id,workout_session_id)
  references public.workout_sessions(organization_id,id)
  on delete cascade;

alter table public.session_exercises
  add constraint session_exercises_program_exercise_same_org
  foreign key (organization_id,program_exercise_id)
  references public.program_exercises(organization_id,id)
  on delete set null;

alter table public.session_exercises
  add constraint session_exercises_previous_session_same_org
  foreign key (organization_id,previous_session_id)
  references public.workout_sessions(organization_id,id)
  on delete set null;

alter table public.session_exercises
  add constraint session_exercises_previous_exercise_same_org
  foreign key (organization_id,previous_session_exercise_id)
  references public.session_exercises(organization_id,id)
  on delete set null;

alter table public.set_logs
  add constraint set_logs_organization_id_fkey
  foreign key (organization_id)
  references public.organizations(id)
  on delete restrict;

alter table public.set_logs
  add constraint set_logs_session_exercise_same_org
  foreign key (organization_id,session_exercise_id)
  references public.session_exercises(organization_id,id)
  on delete cascade;

alter table public.set_logs
  add constraint set_logs_reference_same_org
  foreign key (organization_id,reference_set_log_id)
  references public.set_logs(organization_id,id)
  on delete set null;

create or replace function private.sync_program_organization_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_resolved uuid;
begin
  if tg_op='UPDATE' and new.organization_id is distinct from old.organization_id then
    raise exception 'program organization is immutable';
  end if;

  if tg_op='INSERT'
     or new.client_id is distinct from old.client_id
     or new.coach_id is distinct from old.coach_id then
    v_resolved:=private.resolve_training_organization_v1(new.client_id,new.coach_id);
    if new.organization_id is null then
      new.organization_id:=v_resolved;
    elsif new.organization_id<>v_resolved then
      raise exception 'program client/coach do not resolve to supplied organization';
    end if;
  end if;

  return new;
end;
$function$;

create or replace function private.sync_program_day_organization_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_parent_org uuid;
begin
  select p.organization_id into v_parent_org
  from public.programs p
  where p.id=new.program_id;

  if v_parent_org is null then
    raise exception 'program day parent program not found';
  end if;

  if tg_op='UPDATE' and new.organization_id is distinct from old.organization_id then
    raise exception 'program day organization is immutable';
  end if;

  if new.organization_id is null then
    new.organization_id:=v_parent_org;
  elsif new.organization_id<>v_parent_org then
    raise exception 'program day cannot cross organization boundary';
  end if;

  return new;
end;
$function$;

create or replace function private.sync_program_exercise_organization_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_parent_org uuid;
begin
  select d.organization_id into v_parent_org
  from public.program_days d
  where d.id=new.program_day_id;

  if v_parent_org is null then
    raise exception 'program exercise parent day not found';
  end if;

  if tg_op='UPDATE' and new.organization_id is distinct from old.organization_id then
    raise exception 'program exercise organization is immutable';
  end if;

  if new.organization_id is null then
    new.organization_id:=v_parent_org;
  elsif new.organization_id<>v_parent_org then
    raise exception 'program exercise cannot cross organization boundary';
  end if;

  return new;
end;
$function$;

create or replace function private.sync_workout_session_organization_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_program public.programs%rowtype;
  v_day public.program_days%rowtype;
begin
  select * into v_program
  from public.programs p
  where p.id=new.program_id;

  if not found then raise exception 'workout program not found'; end if;

  select * into v_day
  from public.program_days d
  where d.id=new.program_day_id;

  if not found then raise exception 'workout program day not found'; end if;

  if v_day.program_id<>v_program.id
     or v_day.organization_id<>v_program.organization_id then
    raise exception 'workout program day does not belong to program tenant';
  end if;

  if new.client_id<>v_program.client_id then
    raise exception 'workout client does not match program client';
  end if;

  if tg_op='UPDATE' and new.organization_id is distinct from old.organization_id then
    raise exception 'workout organization is immutable';
  end if;

  if new.organization_id is null then
    new.organization_id:=v_program.organization_id;
  elsif new.organization_id<>v_program.organization_id then
    raise exception 'workout session cannot cross organization boundary';
  end if;

  return new;
end;
$function$;

create or replace function private.sync_session_exercise_organization_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_session_org uuid;
  v_program_exercise_org uuid;
  v_previous_session_org uuid;
  v_previous_exercise_org uuid;
begin
  select ws.organization_id into v_session_org
  from public.workout_sessions ws
  where ws.id=new.workout_session_id;

  if v_session_org is null then
    raise exception 'session exercise workout session not found';
  end if;

  if new.program_exercise_id is not null then
    select pe.organization_id into v_program_exercise_org
    from public.program_exercises pe
    where pe.id=new.program_exercise_id;
    if v_program_exercise_org is null or v_program_exercise_org<>v_session_org then
      raise exception 'session exercise program exercise crosses organization boundary';
    end if;
  end if;

  if new.previous_session_id is not null then
    select ws.organization_id into v_previous_session_org
    from public.workout_sessions ws
    where ws.id=new.previous_session_id;
    if v_previous_session_org is null or v_previous_session_org<>v_session_org then
      raise exception 'previous workout session crosses organization boundary';
    end if;
  end if;

  if new.previous_session_exercise_id is not null then
    select se.organization_id into v_previous_exercise_org
    from public.session_exercises se
    where se.id=new.previous_session_exercise_id;
    if v_previous_exercise_org is null or v_previous_exercise_org<>v_session_org then
      raise exception 'previous session exercise crosses organization boundary';
    end if;
  end if;

  if tg_op='UPDATE' and new.organization_id is distinct from old.organization_id then
    raise exception 'session exercise organization is immutable';
  end if;

  if new.organization_id is null then
    new.organization_id:=v_session_org;
  elsif new.organization_id<>v_session_org then
    raise exception 'session exercise cannot cross organization boundary';
  end if;

  return new;
end;
$function$;

create or replace function private.sync_set_log_organization_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_session_org uuid;
  v_reference_org uuid;
begin
  select se.organization_id into v_session_org
  from public.session_exercises se
  where se.id=new.session_exercise_id;

  if v_session_org is null then
    raise exception 'set log session exercise not found';
  end if;

  if new.reference_set_log_id is not null then
    select sl.organization_id into v_reference_org
    from public.set_logs sl
    where sl.id=new.reference_set_log_id;
    if v_reference_org is null or v_reference_org<>v_session_org then
      raise exception 'reference set log crosses organization boundary';
    end if;
  end if;

  if tg_op='UPDATE' and new.organization_id is distinct from old.organization_id then
    raise exception 'set log organization is immutable';
  end if;

  if new.organization_id is null then
    new.organization_id:=v_session_org;
  elsif new.organization_id<>v_session_org then
    raise exception 'set log cannot cross organization boundary';
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_programs_tenant_scope_v1 on public.programs;
create trigger trg_programs_tenant_scope_v1
before insert or update on public.programs
for each row execute function private.sync_program_organization_v1();

drop trigger if exists trg_program_days_tenant_scope_v1 on public.program_days;
create trigger trg_program_days_tenant_scope_v1
before insert or update on public.program_days
for each row execute function private.sync_program_day_organization_v1();

drop trigger if exists trg_program_exercises_tenant_scope_v1 on public.program_exercises;
create trigger trg_program_exercises_tenant_scope_v1
before insert or update on public.program_exercises
for each row execute function private.sync_program_exercise_organization_v1();

drop trigger if exists trg_workout_sessions_tenant_scope_v1 on public.workout_sessions;
create trigger trg_workout_sessions_tenant_scope_v1
before insert or update on public.workout_sessions
for each row execute function private.sync_workout_session_organization_v1();

drop trigger if exists trg_session_exercises_tenant_scope_v1 on public.session_exercises;
create trigger trg_session_exercises_tenant_scope_v1
before insert or update on public.session_exercises
for each row execute function private.sync_session_exercise_organization_v1();

drop trigger if exists trg_set_logs_tenant_scope_v1 on public.set_logs;
create trigger trg_set_logs_tenant_scope_v1
before insert or update on public.set_logs
for each row execute function private.sync_set_log_organization_v1();

create index if not exists idx_programs_organization_client_status
  on public.programs(organization_id,client_id,status);
create index if not exists idx_workout_sessions_organization_client_started
  on public.workout_sessions(organization_id,client_id,started_at desc);
create index if not exists idx_session_exercises_organization_workout
  on public.session_exercises(organization_id,workout_session_id);
create index if not exists idx_set_logs_organization_session_exercise
  on public.set_logs(organization_id,session_exercise_id);

comment on column public.programs.organization_id is 'F1.M1.S5 tenant boundary; legacy client_id remains global User during compatibility migration.';
comment on column public.workout_sessions.organization_id is 'F1.M1.S5 tenant scope inherited from Program and enforced by composite FKs.';
