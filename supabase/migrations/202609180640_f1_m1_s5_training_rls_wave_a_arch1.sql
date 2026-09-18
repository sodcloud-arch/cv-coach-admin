-- ARCH-1.0 · F1.M1.S5 Data Isolation · Wave A RLS hardening
-- Moves the critical training graph from legacy global-user authorization
-- to explicit tenant + canonical assignment authorization.

create or replace function private.can_manage_tenant_client(
  target_organization uuid,
  target_client_user uuid
)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select coalesce(
    auth.role()='service_role'
    or private.is_platform_admin()
    or private.is_org_admin(target_organization)
    or exists(
      select 1
      from public.clients c
      join public.client_coach_assignments a
        on a.organization_id=c.organization_id
       and a.client_id=c.id
       and a.status='active'::public.client_coach_assignment_status
      join public.coach_profiles cp
        on cp.organization_id=a.organization_id
       and cp.id=a.coach_id
       and cp.status='active'::public.coach_profile_status
      join public.organization_members om
        on om.organization_id=cp.organization_id
       and om.user_id=cp.user_id
       and om.status='active'::public.organization_member_status
      where c.organization_id=target_organization
        and c.user_id=target_client_user
        and c.status<>'archived'::public.client_status
        and cp.user_id=(select auth.uid())
    ),
    false
  )
$function$;

create or replace function private.can_view_tenant_client(
  target_organization uuid,
  target_client_user uuid
)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select coalesce(
    private.can_manage_tenant_client(target_organization,target_client_user)
    or exists(
      select 1
      from public.clients c
      join public.organization_members om
        on om.organization_id=c.organization_id
       and om.user_id=c.user_id
       and om.status='active'::public.organization_member_status
      where c.organization_id=target_organization
        and c.user_id=target_client_user
        and c.status<>'archived'::public.client_status
        and c.user_id=(select auth.uid())
    ),
    false
  )
$function$;

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
      and private.can_view_tenant_client(p.organization_id,p.client_id)
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
      and private.can_manage_tenant_client(p.organization_id,p.client_id)
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
      and private.can_view_tenant_client(p.organization_id,p.client_id)
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
      and private.can_manage_tenant_client(p.organization_id,p.client_id)
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
      and private.can_view_tenant_client(ws.organization_id,ws.client_id)
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
        or private.can_manage_tenant_client(ws.organization_id,ws.client_id)
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
      and private.can_view_tenant_client(ws.organization_id,ws.client_id)
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
        or private.can_manage_tenant_client(ws.organization_id,ws.client_id)
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
      and private.can_manage_tenant_client(ws.organization_id,ws.client_id)
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

drop policy if exists programs_select on public.programs;
create policy programs_select
on public.programs for select
to authenticated
using (private.can_view_tenant_client(organization_id,client_id));

drop policy if exists programs_insert on public.programs;
create policy programs_insert
on public.programs for insert
to authenticated
with check (
  private.can_manage_tenant_client(organization_id,client_id)
  and (
    coach_id=(select auth.uid())
    or private.is_org_admin(organization_id)
  )
);

drop policy if exists programs_update on public.programs;
create policy programs_update
on public.programs for update
to authenticated
using (private.can_manage_tenant_client(organization_id,client_id))
with check (
  private.can_manage_tenant_client(organization_id,client_id)
  and (
    coach_id=(select auth.uid())
    or private.is_org_admin(organization_id)
  )
);

drop policy if exists programs_delete on public.programs;
create policy programs_delete
on public.programs for delete
to authenticated
using (private.can_manage_tenant_client(organization_id,client_id));

-- Child policies retain their names/interfaces but helpers are now tenant-aware.
drop policy if exists program_days_select on public.program_days;
create policy program_days_select
on public.program_days for select
to authenticated
using (private.can_view_program(program_id));

drop policy if exists program_days_insert on public.program_days;
create policy program_days_insert
on public.program_days for insert
to authenticated
with check (private.can_manage_program(program_id));

drop policy if exists program_days_update on public.program_days;
create policy program_days_update
on public.program_days for update
to authenticated
using (private.can_manage_program(program_id))
with check (private.can_manage_program(program_id));

drop policy if exists program_days_delete on public.program_days;
create policy program_days_delete
on public.program_days for delete
to authenticated
using (private.can_manage_program(program_id));

drop policy if exists program_exercises_select on public.program_exercises;
create policy program_exercises_select
on public.program_exercises for select
to authenticated
using (private.can_view_program_day(program_day_id));

drop policy if exists program_exercises_insert on public.program_exercises;
create policy program_exercises_insert
on public.program_exercises for insert
to authenticated
with check (private.can_manage_program_day(program_day_id));

drop policy if exists program_exercises_update on public.program_exercises;
create policy program_exercises_update
on public.program_exercises for update
to authenticated
using (private.can_manage_program_day(program_day_id))
with check (private.can_manage_program_day(program_day_id));

drop policy if exists program_exercises_delete on public.program_exercises;
create policy program_exercises_delete
on public.program_exercises for delete
to authenticated
using (private.can_manage_program_day(program_day_id));

drop policy if exists workout_sessions_select on public.workout_sessions;
create policy workout_sessions_select
on public.workout_sessions for select
to authenticated
using (private.can_view_tenant_client(organization_id,client_id));

drop policy if exists workout_sessions_insert on public.workout_sessions;
create policy workout_sessions_insert
on public.workout_sessions for insert
to authenticated
with check (
  (
    (
      client_id=(select auth.uid())
      and private.is_org_member(organization_id)
    )
    or private.can_manage_tenant_client(organization_id,client_id)
  )
  and private.program_day_belongs_to_client(program_day_id,client_id)
);

drop policy if exists workout_sessions_update on public.workout_sessions;
create policy workout_sessions_update
on public.workout_sessions for update
to authenticated
using (
  (
    client_id=(select auth.uid())
    and private.is_org_member(organization_id)
    and status<>'completed'::public.workout_session_status
  )
  or private.can_manage_tenant_client(organization_id,client_id)
)
with check (
  private.program_day_belongs_to_client(program_day_id,client_id)
  and (
    (
      client_id=(select auth.uid())
      and private.is_org_member(organization_id)
      and status<>'completed'::public.workout_session_status
    )
    or private.can_manage_tenant_client(organization_id,client_id)
  )
);

drop policy if exists session_exercises_select on public.session_exercises;
create policy session_exercises_select
on public.session_exercises for select
to authenticated
using (private.can_view_workout_session(workout_session_id));

drop policy if exists session_exercises_insert on public.session_exercises;
create policy session_exercises_insert
on public.session_exercises for insert
to authenticated
with check (private.can_edit_workout_session(workout_session_id));

drop policy if exists session_exercises_update on public.session_exercises;
create policy session_exercises_update
on public.session_exercises for update
to authenticated
using (private.can_edit_workout_session(workout_session_id))
with check (private.can_edit_workout_session(workout_session_id));

drop policy if exists set_logs_select on public.set_logs;
create policy set_logs_select
on public.set_logs for select
to authenticated
using (private.can_view_session_exercise(session_exercise_id));

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

drop policy if exists set_logs_delete on public.set_logs;
create policy set_logs_delete
on public.set_logs for delete
to authenticated
using (private.can_edit_session_exercise(session_exercise_id));

comment on function private.can_manage_tenant_client(uuid,uuid) is
  'F1.M1.S5 tenant-aware client management via Org Admin or active canonical Coach assignment.';
