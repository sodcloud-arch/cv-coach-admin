-- ARCH-1.0 · F1.M1.S5 Data Isolation — Wave 2: legacy business roots
-- Adds explicit tenant context to high-value legacy roots while preserving current
-- single-tenant call sites. Ambiguous multi-tenant writes must provide organization_id.

alter table public.clients
  add constraint clients_org_user_unique_all unique (organization_id,user_id);

create or replace function private.resolve_legacy_client_organization_v1(
  target_client_user uuid,
  requested_organization uuid default null
)
returns uuid
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_organization uuid;
  v_count integer;
begin
  if target_client_user is null then
    raise exception 'legacy client user id is required';
  end if;

  if requested_organization is not null then
    if not exists(
      select 1
      from public.clients c
      join public.organization_members om
        on om.organization_id=c.organization_id
       and om.user_id=c.user_id
      where c.organization_id=requested_organization
        and c.user_id=target_client_user
        and c.status<>'archived'::public.client_status
        and om.status='active'::public.organization_member_status
    ) then
      raise exception 'legacy client is not active in requested organization';
    end if;
    return requested_organization;
  end if;

  select count(*),min(c.organization_id)
    into v_count,v_organization
  from public.clients c
  join public.organization_members om
    on om.organization_id=c.organization_id
   and om.user_id=c.user_id
  where c.user_id=target_client_user
    and c.status<>'archived'::public.client_status
    and om.status='active'::public.organization_member_status;

  if v_count=1 then
    return v_organization;
  elsif v_count=0 then
    raise exception 'legacy client has no active canonical tenant';
  end if;

  raise exception 'legacy client belongs to multiple organizations; organization_id is required';
end;
$function$;

create or replace function private.can_view_client_in_org(
  target_organization uuid,
  target_client_user uuid
)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select coalesce(exists(
    select 1
    from public.clients c
    where c.organization_id=target_organization
      and c.user_id=target_client_user
      and private.can_view_client_entity(c.id)
  ),false)
$function$;

create or replace function private.can_manage_client_in_org(
  target_organization uuid,
  target_client_user uuid
)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select coalesce(
    private.is_org_admin(target_organization)
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
        and cp.user_id=(select auth.uid())
    ),
    false
  )
$function$;

-- Root tables: explicit tenant column.
alter table public.programs add column if not exists organization_id uuid;
alter table public.workout_sessions add column if not exists organization_id uuid;
alter table public.coach_alerts add column if not exists organization_id uuid;
alter table public.progression_suggestions add column if not exists organization_id uuid;
alter table public.weekly_checkins add column if not exists organization_id uuid;
alter table public.nutrition_daily_logs add column if not exists organization_id uuid;
alter table public.client_subscriptions add column if not exists organization_id uuid;

-- Existing production data is unambiguous and already mapped to canonical Clients.
update public.programs p
set organization_id=c.organization_id
from public.clients c
where c.user_id=p.client_id
  and p.organization_id is null;

update public.workout_sessions s
set organization_id=p.organization_id
from public.programs p
where p.id=s.program_id
  and s.organization_id is null;

update public.coach_alerts a
set organization_id=c.organization_id
from public.clients c
where c.user_id=a.client_id
  and a.organization_id is null;

update public.progression_suggestions s
set organization_id=c.organization_id
from public.clients c
where c.user_id=s.client_id
  and s.organization_id is null;

update public.weekly_checkins w
set organization_id=c.organization_id
from public.clients c
where c.user_id=w.client_id
  and w.organization_id is null;

update public.nutrition_daily_logs n
set organization_id=c.organization_id
from public.clients c
where c.user_id=n.client_id
  and n.organization_id is null;

update public.client_subscriptions s
set organization_id=c.organization_id
from public.clients c
where c.user_id=s.client_id
  and s.organization_id is null;

do $$
begin
  if exists(select 1 from public.programs where organization_id is null)
     or exists(select 1 from public.workout_sessions where organization_id is null)
     or exists(select 1 from public.coach_alerts where organization_id is null)
     or exists(select 1 from public.progression_suggestions where organization_id is null)
     or exists(select 1 from public.weekly_checkins where organization_id is null)
     or exists(select 1 from public.nutrition_daily_logs where organization_id is null)
     or exists(select 1 from public.client_subscriptions where organization_id is null) then
    raise exception 'F1.M1.S5 wave 2 tenant backfill incomplete';
  end if;
end $$;

alter table public.programs alter column organization_id set not null;
alter table public.workout_sessions alter column organization_id set not null;
alter table public.coach_alerts alter column organization_id set not null;
alter table public.progression_suggestions alter column organization_id set not null;
alter table public.weekly_checkins alter column organization_id set not null;
alter table public.nutrition_daily_logs alter column organization_id set not null;
alter table public.client_subscriptions alter column organization_id set not null;

-- Parent composite identities for same-tenant foreign keys.
create unique index if not exists ux_programs_org_id
  on public.programs(organization_id,id);
create unique index if not exists ux_programs_org_id_client
  on public.programs(organization_id,id,client_id);
create unique index if not exists ux_workout_sessions_org_id
  on public.workout_sessions(organization_id,id);
create unique index if not exists ux_workout_sessions_org_id_client
  on public.workout_sessions(organization_id,id,client_id);

-- Same-tenant relational constraints.
alter table public.programs
  add constraint programs_organization_id_fkey
  foreign key (organization_id) references public.organizations(id) on delete restrict;
alter table public.programs
  add constraint programs_client_same_org
  foreign key (organization_id,client_id)
  references public.clients(organization_id,user_id) on delete restrict;
alter table public.programs
  add constraint programs_coach_same_org
  foreign key (organization_id,coach_id)
  references public.coach_profiles(organization_id,user_id) on delete restrict;

alter table public.workout_sessions
  add constraint workout_sessions_organization_id_fkey
  foreign key (organization_id) references public.organizations(id) on delete restrict;
alter table public.workout_sessions
  add constraint workout_sessions_client_same_org
  foreign key (organization_id,client_id)
  references public.clients(organization_id,user_id) on delete restrict;
alter table public.workout_sessions
  add constraint workout_sessions_program_same_org_client
  foreign key (organization_id,program_id,client_id)
  references public.programs(organization_id,id,client_id) on delete restrict;

alter table public.coach_alerts
  add constraint coach_alerts_organization_id_fkey
  foreign key (organization_id) references public.organizations(id) on delete restrict;
alter table public.coach_alerts
  add constraint coach_alerts_client_same_org
  foreign key (organization_id,client_id)
  references public.clients(organization_id,user_id) on delete restrict;
alter table public.coach_alerts
  add constraint coach_alerts_coach_same_org
  foreign key (organization_id,coach_id)
  references public.coach_profiles(organization_id,user_id) on delete restrict;

alter table public.progression_suggestions
  add constraint progression_suggestions_organization_id_fkey
  foreign key (organization_id) references public.organizations(id) on delete restrict;
alter table public.progression_suggestions
  add constraint progression_suggestions_client_same_org
  foreign key (organization_id,client_id)
  references public.clients(organization_id,user_id) on delete restrict;
alter table public.progression_suggestions
  add constraint progression_suggestions_source_session_same_org_client
  foreign key (organization_id,source_session_id,client_id)
  references public.workout_sessions(organization_id,id,client_id) on delete restrict;
alter table public.progression_suggestions
  add constraint progression_suggestions_reviewed_by_same_org
  foreign key (organization_id,reviewed_by)
  references public.organization_members(organization_id,user_id) on delete restrict;

alter table public.weekly_checkins
  add constraint weekly_checkins_organization_id_fkey
  foreign key (organization_id) references public.organizations(id) on delete restrict;
alter table public.weekly_checkins
  add constraint weekly_checkins_client_same_org
  foreign key (organization_id,client_id)
  references public.clients(organization_id,user_id) on delete restrict;

alter table public.nutrition_daily_logs
  add constraint nutrition_daily_logs_organization_id_fkey
  foreign key (organization_id) references public.organizations(id) on delete restrict;
alter table public.nutrition_daily_logs
  add constraint nutrition_daily_logs_client_same_org
  foreign key (organization_id,client_id)
  references public.clients(organization_id,user_id) on delete restrict;

alter table public.client_subscriptions
  add constraint client_subscriptions_organization_id_fkey
  foreign key (organization_id) references public.organizations(id) on delete restrict;
alter table public.client_subscriptions
  add constraint client_subscriptions_client_same_org
  foreign key (organization_id,client_id)
  references public.clients(organization_id,user_id) on delete restrict;

-- Compatibility triggers. Missing organization_id may only be inferred when
-- the legacy client identity belongs to exactly one active tenant.
create or replace function private.guard_legacy_client_scoped_row_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  new.organization_id:=private.resolve_legacy_client_organization_v1(
    new.client_id,new.organization_id
  );

  if tg_op='UPDATE' and (
    new.organization_id is distinct from old.organization_id
    or new.client_id is distinct from old.client_id
  ) then
    raise exception 'tenant-scoped legacy client identity is immutable';
  end if;

  return new;
end;
$function$;

create or replace function private.guard_program_tenant_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  new.organization_id:=private.resolve_legacy_client_organization_v1(
    new.client_id,new.organization_id
  );

  if not exists(
    select 1
    from public.coach_profiles cp
    join public.organization_members om
      on om.organization_id=cp.organization_id
     and om.user_id=cp.user_id
    where cp.organization_id=new.organization_id
      and cp.user_id=new.coach_id
      and cp.status='active'::public.coach_profile_status
      and om.status='active'::public.organization_member_status
  ) then
    raise exception 'program coach must be active in the same organization';
  end if;

  if tg_op='UPDATE' and (
    new.organization_id is distinct from old.organization_id
    or new.client_id is distinct from old.client_id
    or new.coach_id is distinct from old.coach_id
  ) then
    raise exception 'program tenant/client/coach identity is immutable';
  end if;

  return new;
end;
$function$;

create or replace function private.guard_workout_session_tenant_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_program_org uuid;
  v_program_client uuid;
begin
  select p.organization_id,p.client_id
    into v_program_org,v_program_client
  from public.programs p
  where p.id=new.program_id;

  if v_program_org is null then
    raise exception 'workout session requires a valid program';
  end if;
  if v_program_client<>new.client_id then
    raise exception 'workout session client must match program client';
  end if;

  if new.organization_id is null then
    new.organization_id:=v_program_org;
  elsif new.organization_id<>v_program_org then
    raise exception 'workout session cannot cross program organization';
  end if;

  if tg_op='UPDATE' and (
    new.organization_id is distinct from old.organization_id
    or new.client_id is distinct from old.client_id
    or new.program_id is distinct from old.program_id
  ) then
    raise exception 'workout session tenant/client/program identity is immutable';
  end if;

  return new;
end;
$function$;

create or replace function private.guard_coach_alert_tenant_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  new.organization_id:=private.resolve_legacy_client_organization_v1(
    new.client_id,new.organization_id
  );

  if not exists(
    select 1 from public.coach_profiles cp
    where cp.organization_id=new.organization_id
      and cp.user_id=new.coach_id
      and cp.status='active'::public.coach_profile_status
  ) then
    raise exception 'coach alert coach must be active in the same organization';
  end if;

  if tg_op='UPDATE' and (
    new.organization_id is distinct from old.organization_id
    or new.client_id is distinct from old.client_id
    or new.coach_id is distinct from old.coach_id
  ) then
    raise exception 'coach alert tenant/client/coach identity is immutable';
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_programs_tenant_v1 on public.programs;
create trigger trg_programs_tenant_v1
before insert or update on public.programs
for each row execute function private.guard_program_tenant_v1();

drop trigger if exists trg_workout_sessions_tenant_v1 on public.workout_sessions;
create trigger trg_workout_sessions_tenant_v1
before insert or update on public.workout_sessions
for each row execute function private.guard_workout_session_tenant_v1();

drop trigger if exists trg_coach_alerts_tenant_v1 on public.coach_alerts;
create trigger trg_coach_alerts_tenant_v1
before insert or update on public.coach_alerts
for each row execute function private.guard_coach_alert_tenant_v1();

drop trigger if exists trg_progression_suggestions_tenant_v1 on public.progression_suggestions;
create trigger trg_progression_suggestions_tenant_v1
before insert or update on public.progression_suggestions
for each row execute function private.guard_legacy_client_scoped_row_v1();

drop trigger if exists trg_weekly_checkins_tenant_v1 on public.weekly_checkins;
create trigger trg_weekly_checkins_tenant_v1
before insert or update on public.weekly_checkins
for each row execute function private.guard_legacy_client_scoped_row_v1();

drop trigger if exists trg_nutrition_daily_logs_tenant_v1 on public.nutrition_daily_logs;
create trigger trg_nutrition_daily_logs_tenant_v1
before insert or update on public.nutrition_daily_logs
for each row execute function private.guard_legacy_client_scoped_row_v1();

drop trigger if exists trg_client_subscriptions_tenant_v1 on public.client_subscriptions;
create trigger trg_client_subscriptions_tenant_v1
before insert or update on public.client_subscriptions
for each row execute function private.guard_legacy_client_scoped_row_v1();

-- Tenant-aware RLS policies for migrated roots.
drop policy if exists programs_select on public.programs;
drop policy if exists programs_insert on public.programs;
drop policy if exists programs_update on public.programs;
drop policy if exists programs_delete on public.programs;
create policy programs_select_v2 on public.programs for select to authenticated
using (private.can_view_client_in_org(organization_id,client_id));
create policy programs_insert_v2 on public.programs for insert to authenticated
with check (
  private.can_manage_client_in_org(organization_id,client_id)
  and (coach_id=(select auth.uid()) or private.is_org_admin(organization_id))
);
create policy programs_update_v2 on public.programs for update to authenticated
using (private.can_manage_client_in_org(organization_id,client_id))
with check (
  private.can_manage_client_in_org(organization_id,client_id)
  and (coach_id=(select auth.uid()) or private.is_org_admin(organization_id))
);
create policy programs_delete_v2 on public.programs for delete to authenticated
using (private.can_manage_client_in_org(organization_id,client_id));

drop policy if exists workout_sessions_select on public.workout_sessions;
drop policy if exists workout_sessions_insert on public.workout_sessions;
drop policy if exists workout_sessions_update on public.workout_sessions;
create policy workout_sessions_select_v2 on public.workout_sessions for select to authenticated
using (private.can_view_client_in_org(organization_id,client_id));
create policy workout_sessions_insert_v2 on public.workout_sessions for insert to authenticated
with check (
  (
    (client_id=(select auth.uid()) and private.is_org_member(organization_id))
    or private.can_manage_client_in_org(organization_id,client_id)
  )
  and private.program_day_belongs_to_client(program_day_id,client_id)
);
create policy workout_sessions_update_v2 on public.workout_sessions for update to authenticated
using (
  (
    client_id=(select auth.uid())
    and private.is_org_member(organization_id)
    and status<>'completed'::public.workout_session_status
  )
  or private.can_manage_client_in_org(organization_id,client_id)
)
with check (
  private.program_day_belongs_to_client(program_day_id,client_id)
  and (
    (
      client_id=(select auth.uid())
      and private.is_org_member(organization_id)
      and status<>'completed'::public.workout_session_status
    )
    or private.can_manage_client_in_org(organization_id,client_id)
  )
);

drop policy if exists coach_alerts_select on public.coach_alerts;
drop policy if exists coach_alerts_update on public.coach_alerts;
create policy coach_alerts_select_v2 on public.coach_alerts for select to authenticated
using (
  private.is_org_admin(organization_id)
  or (
    coach_id=(select auth.uid())
    and private.is_org_professional(organization_id)
  )
);
create policy coach_alerts_update_v2 on public.coach_alerts for update to authenticated
using (
  private.is_org_admin(organization_id)
  or (
    coach_id=(select auth.uid())
    and private.is_org_professional(organization_id)
  )
)
with check (
  private.is_org_admin(organization_id)
  or (
    coach_id=(select auth.uid())
    and private.is_org_professional(organization_id)
  )
);

drop policy if exists progression_select on public.progression_suggestions;
drop policy if exists progression_insert on public.progression_suggestions;
drop policy if exists progression_update on public.progression_suggestions;
drop policy if exists progression_delete on public.progression_suggestions;
create policy progression_select_v2 on public.progression_suggestions for select to authenticated
using (private.can_view_client_in_org(organization_id,client_id));
create policy progression_insert_v2 on public.progression_suggestions for insert to authenticated
with check (private.can_manage_client_in_org(organization_id,client_id));
create policy progression_update_v2 on public.progression_suggestions for update to authenticated
using (private.can_manage_client_in_org(organization_id,client_id))
with check (private.can_manage_client_in_org(organization_id,client_id));
create policy progression_delete_v2 on public.progression_suggestions for delete to authenticated
using (private.can_manage_client_in_org(organization_id,client_id));

drop policy if exists weekly_checkins_select on public.weekly_checkins;
create policy weekly_checkins_select_v2 on public.weekly_checkins for select to authenticated
using (private.can_view_client_in_org(organization_id,client_id));

drop policy if exists nutrition_daily_select on public.nutrition_daily_logs;
drop policy if exists nutrition_daily_insert on public.nutrition_daily_logs;
drop policy if exists nutrition_daily_update on public.nutrition_daily_logs;
drop policy if exists nutrition_daily_delete on public.nutrition_daily_logs;
create policy nutrition_daily_select_v2 on public.nutrition_daily_logs for select to authenticated
using (private.can_view_client_in_org(organization_id,client_id));
create policy nutrition_daily_insert_v2 on public.nutrition_daily_logs for insert to authenticated
with check (
  (
    client_id=(select auth.uid())
    and private.is_org_member(organization_id)
    and source='manual'::public.log_source
  )
  or private.can_manage_client_in_org(organization_id,client_id)
);
create policy nutrition_daily_update_v2 on public.nutrition_daily_logs for update to authenticated
using (
  (
    client_id=(select auth.uid())
    and private.is_org_member(organization_id)
  )
  or private.can_manage_client_in_org(organization_id,client_id)
)
with check (
  (
    client_id=(select auth.uid())
    and private.is_org_member(organization_id)
    and source='manual'::public.log_source
  )
  or private.can_manage_client_in_org(organization_id,client_id)
);
create policy nutrition_daily_delete_v2 on public.nutrition_daily_logs for delete to authenticated
using (
  (
    client_id=(select auth.uid())
    and private.is_org_member(organization_id)
  )
  or private.can_manage_client_in_org(organization_id,client_id)
);

drop policy if exists subscriptions_select on public.client_subscriptions;
create policy subscriptions_select_v2 on public.client_subscriptions for select to authenticated
using (private.can_view_client_in_org(organization_id,client_id));

-- Least privilege browser grants for these roots.
revoke all privileges on table public.programs from public,anon,authenticated;
revoke all privileges on table public.workout_sessions from public,anon,authenticated;
revoke all privileges on table public.coach_alerts from public,anon,authenticated;
revoke all privileges on table public.progression_suggestions from public,anon,authenticated;
revoke all privileges on table public.weekly_checkins from public,anon,authenticated;
revoke all privileges on table public.nutrition_daily_logs from public,anon,authenticated;
revoke all privileges on table public.client_subscriptions from public,anon,authenticated;

grant select,insert,update,delete on table public.programs to authenticated;
grant select,insert,update on table public.workout_sessions to authenticated;
grant select,update on table public.coach_alerts to authenticated;
grant select,insert,update,delete on table public.progression_suggestions to authenticated;
grant select on table public.weekly_checkins to authenticated;
grant select,insert,update,delete on table public.nutrition_daily_logs to authenticated;
grant select on table public.client_subscriptions to authenticated;

grant all privileges on table public.programs to service_role;
grant all privileges on table public.workout_sessions to service_role;
grant all privileges on table public.coach_alerts to service_role;
grant all privileges on table public.progression_suggestions to service_role;
grant all privileges on table public.weekly_checkins to service_role;
grant all privileges on table public.nutrition_daily_logs to service_role;
grant all privileges on table public.client_subscriptions to service_role;

comment on function private.resolve_legacy_client_organization_v1(uuid,uuid) is
  'F1.M1.S5 compatibility resolver: infers tenant only when legacy client identity maps to exactly one active Organization; multi-tenant writes must pass organization_id.';
