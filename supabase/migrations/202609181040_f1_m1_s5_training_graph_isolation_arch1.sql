-- ARCH-1.0 · F1.M1.S5 Data Isolation — training graph completion
-- Completes explicit tenant scope through Program -> Day -> Exercise -> Session -> Set.
-- Existing legacy identifiers remain compatible, but every professional training row
-- receives an immutable Organization boundary and same-tenant relational constraints.

-- 1) Explicit tenant ownership on the remaining critical training children.
alter table public.program_days
  add column if not exists organization_id uuid;
alter table public.program_exercises
  add column if not exists organization_id uuid;
alter table public.session_exercises
  add column if not exists organization_id uuid;
alter table public.set_logs
  add column if not exists organization_id uuid;

-- 2) Deterministic backfill from already-canonical tenant parents.
update public.program_days d
set organization_id=p.organization_id
from public.programs p
where p.id=d.program_id
  and d.organization_id is null;

update public.program_exercises pe
set organization_id=d.organization_id
from public.program_days d
where d.id=pe.program_day_id
  and pe.organization_id is null;

update public.session_exercises se
set organization_id=ws.organization_id
from public.workout_sessions ws
where ws.id=se.workout_session_id
  and se.organization_id is null;

update public.set_logs sl
set organization_id=se.organization_id
from public.session_exercises se
where se.id=sl.session_exercise_id
  and sl.organization_id is null;

do $$
begin
  if exists(select 1 from public.program_days where organization_id is null)
     or exists(select 1 from public.program_exercises where organization_id is null)
     or exists(select 1 from public.session_exercises where organization_id is null)
     or exists(select 1 from public.set_logs where organization_id is null) then
    raise exception 'F1.M1.S5 training graph backfill left unscoped rows';
  end if;
end $$;

alter table public.program_days alter column organization_id set not null;
alter table public.program_exercises alter column organization_id set not null;
alter table public.session_exercises alter column organization_id set not null;
alter table public.set_logs alter column organization_id set not null;

-- 3) Composite identities used by same-tenant foreign keys.
create unique index if not exists ux_program_days_org_id
  on public.program_days(organization_id,id);
create unique index if not exists ux_program_days_org_id_program
  on public.program_days(organization_id,id,program_id);
create unique index if not exists ux_program_exercises_org_id
  on public.program_exercises(organization_id,id);
create unique index if not exists ux_session_exercises_org_id
  on public.session_exercises(organization_id,id);
create unique index if not exists ux_set_logs_org_id
  on public.set_logs(organization_id,id);
create unique index if not exists ux_progression_suggestions_org_id
  on public.progression_suggestions(organization_id,id);

-- 4) Physical same-tenant boundaries. Constraint creation is guarded so this
-- migration also reconciles environments where an earlier S5 experiment ran.
do $$
begin
  if not exists(select 1 from pg_constraint where conname='program_days_organization_id_fkey') then
    alter table public.program_days
      add constraint program_days_organization_id_fkey
      foreign key (organization_id) references public.organizations(id) on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='program_days_program_same_org') then
    alter table public.program_days
      add constraint program_days_program_same_org
      foreign key (organization_id,program_id)
      references public.programs(organization_id,id) on delete cascade;
  end if;

  if not exists(select 1 from pg_constraint where conname='program_exercises_organization_id_fkey') then
    alter table public.program_exercises
      add constraint program_exercises_organization_id_fkey
      foreign key (organization_id) references public.organizations(id) on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='program_exercises_day_same_org') then
    alter table public.program_exercises
      add constraint program_exercises_day_same_org
      foreign key (organization_id,program_day_id)
      references public.program_days(organization_id,id) on delete cascade;
  end if;

  if not exists(select 1 from pg_constraint where conname='workout_sessions_program_day_same_org') then
    alter table public.workout_sessions
      add constraint workout_sessions_program_day_same_org
      foreign key (organization_id,program_day_id,program_id)
      references public.program_days(organization_id,id,program_id) on delete restrict;
  end if;

  if not exists(select 1 from pg_constraint where conname='session_exercises_organization_id_fkey') then
    alter table public.session_exercises
      add constraint session_exercises_organization_id_fkey
      foreign key (organization_id) references public.organizations(id) on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='session_exercises_workout_same_org') then
    alter table public.session_exercises
      add constraint session_exercises_workout_same_org
      foreign key (organization_id,workout_session_id)
      references public.workout_sessions(organization_id,id) on delete cascade;
  end if;
  if not exists(select 1 from pg_constraint where conname='session_exercises_program_exercise_same_org') then
    alter table public.session_exercises
      add constraint session_exercises_program_exercise_same_org
      foreign key (organization_id,program_exercise_id)
      references public.program_exercises(organization_id,id) on delete set null;
  end if;
  if not exists(select 1 from pg_constraint where conname='session_exercises_previous_session_same_org') then
    alter table public.session_exercises
      add constraint session_exercises_previous_session_same_org
      foreign key (organization_id,previous_session_id)
      references public.workout_sessions(organization_id,id) on delete set null;
  end if;
  if not exists(select 1 from pg_constraint where conname='session_exercises_previous_exercise_same_org') then
    alter table public.session_exercises
      add constraint session_exercises_previous_exercise_same_org
      foreign key (organization_id,previous_session_exercise_id)
      references public.session_exercises(organization_id,id) on delete set null;
  end if;
  if not exists(select 1 from pg_constraint where conname='session_exercises_progression_same_org') then
    alter table public.session_exercises
      add constraint session_exercises_progression_same_org
      foreign key (organization_id,progression_suggestion_id)
      references public.progression_suggestions(organization_id,id) on delete set null;
  end if;

  if not exists(select 1 from pg_constraint where conname='set_logs_organization_id_fkey') then
    alter table public.set_logs
      add constraint set_logs_organization_id_fkey
      foreign key (organization_id) references public.organizations(id) on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='set_logs_session_exercise_same_org') then
    alter table public.set_logs
      add constraint set_logs_session_exercise_same_org
      foreign key (organization_id,session_exercise_id)
      references public.session_exercises(organization_id,id) on delete cascade;
  end if;
  if not exists(select 1 from pg_constraint where conname='set_logs_reference_same_org') then
    alter table public.set_logs
      add constraint set_logs_reference_same_org
      foreign key (organization_id,reference_set_log_id)
      references public.set_logs(organization_id,id) on delete set null;
  end if;
end $$;

-- 5) Compatibility guards: older call sites may omit organization_id, but it
-- is always derived from the canonical parent and cannot be changed later.
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

  if new.organization_id is null then
    new.organization_id:=v_parent_org;
  elsif new.organization_id<>v_parent_org then
    raise exception 'program day cannot cross organization boundary';
  end if;

  if tg_op='UPDATE' and (
    new.organization_id is distinct from old.organization_id
    or new.program_id is distinct from old.program_id
  ) then
    raise exception 'program day tenant identity is immutable';
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

  if new.organization_id is null then
    new.organization_id:=v_parent_org;
  elsif new.organization_id<>v_parent_org then
    raise exception 'program exercise cannot cross organization boundary';
  end if;

  if tg_op='UPDATE' and (
    new.organization_id is distinct from old.organization_id
    or new.program_day_id is distinct from old.program_day_id
  ) then
    raise exception 'program exercise tenant identity is immutable';
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
  v_reference_org uuid;
begin
  select ws.organization_id into v_session_org
  from public.workout_sessions ws
  where ws.id=new.workout_session_id;

  if v_session_org is null then
    raise exception 'session exercise workout session not found';
  end if;

  if new.organization_id is null then
    new.organization_id:=v_session_org;
  elsif new.organization_id<>v_session_org then
    raise exception 'session exercise cannot cross workout organization';
  end if;

  if new.program_exercise_id is not null then
    select pe.organization_id into v_reference_org
    from public.program_exercises pe
    where pe.id=new.program_exercise_id;
    if v_reference_org is null or v_reference_org<>v_session_org then
      raise exception 'session exercise program exercise crosses organization boundary';
    end if;
  end if;

  if new.previous_session_id is not null then
    select ws.organization_id into v_reference_org
    from public.workout_sessions ws
    where ws.id=new.previous_session_id;
    if v_reference_org is null or v_reference_org<>v_session_org then
      raise exception 'previous workout session crosses organization boundary';
    end if;
  end if;

  if new.previous_session_exercise_id is not null then
    select se.organization_id into v_reference_org
    from public.session_exercises se
    where se.id=new.previous_session_exercise_id;
    if v_reference_org is null or v_reference_org<>v_session_org then
      raise exception 'previous session exercise crosses organization boundary';
    end if;
  end if;

  if new.progression_suggestion_id is not null then
    select ps.organization_id into v_reference_org
    from public.progression_suggestions ps
    where ps.id=new.progression_suggestion_id;
    if v_reference_org is null or v_reference_org<>v_session_org then
      raise exception 'progression suggestion crosses organization boundary';
    end if;
  end if;

  if tg_op='UPDATE' and (
    new.organization_id is distinct from old.organization_id
    or new.workout_session_id is distinct from old.workout_session_id
  ) then
    raise exception 'session exercise tenant identity is immutable';
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

  if new.organization_id is null then
    new.organization_id:=v_session_org;
  elsif new.organization_id<>v_session_org then
    raise exception 'set log cannot cross organization boundary';
  end if;

  if new.reference_set_log_id is not null then
    select sl.organization_id into v_reference_org
    from public.set_logs sl
    where sl.id=new.reference_set_log_id;
    if v_reference_org is null or v_reference_org<>v_session_org then
      raise exception 'reference set log crosses organization boundary';
    end if;
  end if;

  if tg_op='UPDATE' and (
    new.organization_id is distinct from old.organization_id
    or new.session_exercise_id is distinct from old.session_exercise_id
  ) then
    raise exception 'set log tenant identity is immutable';
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_program_days_tenant_scope_v1 on public.program_days;
create trigger trg_program_days_tenant_scope_v1
before insert or update on public.program_days
for each row execute function private.sync_program_day_organization_v1();

drop trigger if exists trg_program_exercises_tenant_scope_v1 on public.program_exercises;
create trigger trg_program_exercises_tenant_scope_v1
before insert or update on public.program_exercises
for each row execute function private.sync_program_exercise_organization_v1();

drop trigger if exists trg_session_exercises_tenant_scope_v1 on public.session_exercises;
create trigger trg_session_exercises_tenant_scope_v1
before insert or update on public.session_exercises
for each row execute function private.sync_session_exercise_organization_v1();

drop trigger if exists trg_set_logs_tenant_scope_v1 on public.set_logs;
create trigger trg_set_logs_tenant_scope_v1
before insert or update on public.set_logs
for each row execute function private.sync_set_log_organization_v1();

-- 6) Tenant-aware helper layer. Existing policy interfaces stay stable so
-- current application code does not need a simultaneous client release.
create or replace function private.can_view_program(target_program uuid)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select coalesce(exists(
    select 1
    from public.programs p
    where p.id=target_program
      and private.can_view_client_in_org(p.organization_id,p.client_id)
  ),false)
$function$;

create or replace function private.can_manage_program(target_program uuid)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select coalesce(exists(
    select 1
    from public.programs p
    where p.id=target_program
      and private.can_manage_client_in_org(p.organization_id,p.client_id)
  ),false)
$function$;

create or replace function private.can_view_program_day(target_day uuid)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select coalesce(exists(
    select 1
    from public.program_days d
    join public.programs p
      on p.organization_id=d.organization_id
     and p.id=d.program_id
    where d.id=target_day
      and private.can_view_client_in_org(p.organization_id,p.client_id)
  ),false)
$function$;

create or replace function private.can_manage_program_day(target_day uuid)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select coalesce(exists(
    select 1
    from public.program_days d
    join public.programs p
      on p.organization_id=d.organization_id
     and p.id=d.program_id
    where d.id=target_day
      and private.can_manage_client_in_org(p.organization_id,p.client_id)
  ),false)
$function$;

create or replace function private.program_day_belongs_to_client(
  target_day uuid,
  target_client uuid
)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select coalesce(exists(
    select 1
    from public.program_days d
    join public.programs p
      on p.organization_id=d.organization_id
     and p.id=d.program_id
    where d.id=target_day
      and p.client_id=target_client
  ),false)
$function$;

create or replace function private.can_view_workout_session(target_session uuid)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select coalesce(exists(
    select 1
    from public.workout_sessions ws
    where ws.id=target_session
      and private.can_view_client_in_org(ws.organization_id,ws.client_id)
  ),false)
$function$;

create or replace function private.can_edit_workout_session(target_session uuid)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select coalesce(exists(
    select 1
    from public.workout_sessions ws
    where ws.id=target_session
      and (
        (
          ws.client_id=(select auth.uid())
          and private.is_org_member(ws.organization_id)
        )
        or private.can_manage_client_in_org(ws.organization_id,ws.client_id)
      )
  ),false)
$function$;

create or replace function private.can_view_session_exercise(target_session_exercise uuid)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select coalesce(exists(
    select 1
    from public.session_exercises se
    join public.workout_sessions ws
      on ws.organization_id=se.organization_id
     and ws.id=se.workout_session_id
    where se.id=target_session_exercise
      and private.can_view_client_in_org(ws.organization_id,ws.client_id)
  ),false)
$function$;

create or replace function private.can_edit_session_exercise(target_session_exercise uuid)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select coalesce(exists(
    select 1
    from public.session_exercises se
    join public.workout_sessions ws
      on ws.organization_id=se.organization_id
     and ws.id=se.workout_session_id
    where se.id=target_session_exercise
      and (
        (
          ws.client_id=(select auth.uid())
          and private.is_org_member(ws.organization_id)
        )
        or private.can_manage_client_in_org(ws.organization_id,ws.client_id)
      )
  ),false)
$function$;

create or replace function private.can_manage_session_exercise(target_session_exercise uuid)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select coalesce(exists(
    select 1
    from public.session_exercises se
    join public.workout_sessions ws
      on ws.organization_id=se.organization_id
     and ws.id=se.workout_session_id
    where se.id=target_session_exercise
      and private.can_manage_client_in_org(ws.organization_id,ws.client_id)
  ),false)
$function$;

create or replace function private.session_exercise_client_id(target_session_exercise uuid)
returns uuid
language sql
stable security definer
set search_path to ''
as $function$
  select ws.client_id
  from public.session_exercises se
  join public.workout_sessions ws
    on ws.organization_id=se.organization_id
   and ws.id=se.workout_session_id
  where se.id=target_session_exercise
$function$;

create or replace function private.session_exercise_organization_id(target_session_exercise uuid)
returns uuid
language sql
stable security definer
set search_path to ''
as $function$
  select se.organization_id
  from public.session_exercises se
  where se.id=target_session_exercise
$function$;

-- 7) Set-log mutation policy is the remaining direct legacy authorization path.
drop policy if exists set_logs_insert on public.set_logs;
create policy set_logs_insert
on public.set_logs for insert
to authenticated
with check (
  private.can_edit_session_exercise(session_exercise_id)
  and (
    (
      private.session_exercise_client_id(session_exercise_id)=(select auth.uid())
      and source='manual'::public.log_source
    )
    or private.can_manage_session_exercise(session_exercise_id)
  )
);

drop policy if exists set_logs_update on public.set_logs;
create policy set_logs_update
on public.set_logs for update
to authenticated
using (private.can_edit_session_exercise(session_exercise_id))
with check (
  private.can_edit_session_exercise(session_exercise_id)
  and (
    (
      private.session_exercise_client_id(session_exercise_id)=(select auth.uid())
      and source='manual'::public.log_source
    )
    or private.can_manage_session_exercise(session_exercise_id)
  )
);

-- 8) Supporting indexes for tenant-filtered traversal.
create index if not exists idx_program_days_org_program
  on public.program_days(organization_id,program_id,day_number);
create index if not exists idx_program_exercises_org_day
  on public.program_exercises(organization_id,program_day_id,exercise_order);
create index if not exists idx_session_exercises_org_workout
  on public.session_exercises(organization_id,workout_session_id,exercise_order);
create index if not exists idx_set_logs_org_session_exercise
  on public.set_logs(organization_id,session_exercise_id,set_number);

comment on column public.program_days.organization_id is
  'F1.M1.S5 tenant boundary inherited from Program.';
comment on column public.program_exercises.organization_id is
  'F1.M1.S5 tenant boundary inherited from Program Day.';
comment on column public.session_exercises.organization_id is
  'F1.M1.S5 tenant boundary inherited from Workout Session.';
comment on column public.set_logs.organization_id is
  'F1.M1.S5 tenant boundary inherited from Session Exercise.';
