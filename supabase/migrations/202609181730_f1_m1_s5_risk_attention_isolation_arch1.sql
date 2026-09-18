-- ARCH-1.0 · F1.M1.S5 Wave C2 — Risk / Attention tenant isolation
-- Converts client risk state from global-user scope to Organization + Client scope,
-- preserves public RPC signatures, and rewires alert/attention flows to canonical tenant relations.

-- ---------------------------------------------------------------------------
-- 1) Explicit tenant ownership
-- ---------------------------------------------------------------------------

alter table public.client_risk_state
  add column if not exists organization_id uuid;

alter table private.weekly_checkin_risk_assessments
  add column if not exists organization_id uuid;

-- Prefer canonical session ownership; fall back to tenant-aware Event Outbox;
-- only use the legacy resolver when neither source is available.
update public.client_risk_state r
set organization_id=coalesce(
  (
    select ws.organization_id
    from public.workout_sessions ws
    where ws.id=r.source_session_id
      and ws.client_id=r.client_id
  ),
  (
    select e.organization_id
    from public.event_outbox e
    where e.id=r.source_event_id
      and e.client_id=r.client_id
  ),
  private.resolve_legacy_client_organization_v1(r.client_id,null)
)
where r.organization_id is null;

update private.weekly_checkin_risk_assessments r
set organization_id=c.organization_id
from public.weekly_checkins c
where c.id=r.checkin_id
  and c.client_id=r.client_id
  and r.organization_id is null;

do $$
begin
  if exists(
    select 1
    from public.client_risk_state r
    where r.organization_id is null
       or not exists(
         select 1
         from public.clients c
         where c.organization_id=r.organization_id
           and c.user_id=r.client_id
           and c.status<>'archived'::public.client_status
       )
       or (
         r.source_session_id is not null
         and not exists(
           select 1
           from public.workout_sessions ws
           where ws.id=r.source_session_id
             and ws.organization_id=r.organization_id
             and ws.client_id=r.client_id
         )
       )
       or (
         r.source_event_id is not null
         and not exists(
           select 1
           from public.event_outbox e
           where e.id=r.source_event_id
             and e.organization_id=r.organization_id
             and e.client_id=r.client_id
         )
       )
  ) then
    raise exception 'F1.M1.S5: client_risk_state tenant validation failed';
  end if;

  if exists(
    select 1
    from private.weekly_checkin_risk_assessments r
    join public.weekly_checkins c on c.id=r.checkin_id
    join public.event_outbox e on e.id=r.source_event_id
    where r.organization_id is null
       or r.organization_id<>c.organization_id
       or r.organization_id<>e.organization_id
       or r.client_id<>c.client_id
       or r.client_id<>e.client_id
  ) then
    raise exception 'F1.M1.S5: weekly risk tenant validation failed';
  end if;
end $$;

alter table public.client_risk_state
  alter column organization_id set not null;

alter table private.weekly_checkin_risk_assessments
  alter column organization_id set not null;

-- ---------------------------------------------------------------------------
-- 2) Tenant-scoped identity and physical boundaries
-- ---------------------------------------------------------------------------

alter table public.client_risk_state
  drop constraint if exists client_risk_state_pkey;

alter table public.client_risk_state
  add constraint client_risk_state_pkey
  primary key (organization_id,client_id);

do $$
begin
  if not exists(
    select 1 from pg_constraint
    where conname='client_risk_state_organization_id_fkey'
  ) then
    alter table public.client_risk_state
      add constraint client_risk_state_organization_id_fkey
      foreign key (organization_id)
      references public.organizations(id)
      on delete restrict;
  end if;

  if not exists(
    select 1 from pg_constraint
    where conname='client_risk_state_client_same_org'
  ) then
    alter table public.client_risk_state
      add constraint client_risk_state_client_same_org
      foreign key (organization_id,client_id)
      references public.clients(organization_id,user_id)
      on delete cascade;
  end if;

  if not exists(
    select 1 from pg_constraint
    where conname='weekly_checkin_risk_assessments_organization_id_fkey'
  ) then
    alter table private.weekly_checkin_risk_assessments
      add constraint weekly_checkin_risk_assessments_organization_id_fkey
      foreign key (organization_id)
      references public.organizations(id)
      on delete restrict;
  end if;

  if not exists(
    select 1 from pg_constraint
    where conname='weekly_checkin_risk_assessments_checkin_same_org_client'
  ) then
    alter table private.weekly_checkin_risk_assessments
      add constraint weekly_checkin_risk_assessments_checkin_same_org_client
      foreign key (organization_id,checkin_id,client_id)
      references public.weekly_checkins(organization_id,id,client_id)
      on delete cascade;
  end if;

  if not exists(
    select 1 from pg_constraint
    where conname='weekly_checkin_risk_assessments_event_same_org_client'
  ) then
    alter table private.weekly_checkin_risk_assessments
      add constraint weekly_checkin_risk_assessments_event_same_org_client
      foreign key (organization_id,source_event_id,client_id)
      references public.event_outbox(organization_id,id,client_id)
      on delete cascade;
  end if;
end $$;

create index if not exists idx_client_risk_state_org_level
  on public.client_risk_state(organization_id,level,updated_at desc);

create index if not exists idx_client_risk_state_org_score
  on public.client_risk_state(organization_id,score desc,updated_at desc);

create index if not exists idx_client_risk_state_org_source_session
  on public.client_risk_state(organization_id,source_session_id)
  where source_session_id is not null;

create index if not exists idx_client_risk_state_org_source_event
  on public.client_risk_state(organization_id,source_event_id)
  where source_event_id is not null;

create index if not exists idx_weekly_risk_org_client
  on private.weekly_checkin_risk_assessments(organization_id,client_id,created_at desc);

-- ---------------------------------------------------------------------------
-- 3) Immutable tenant guards
-- ---------------------------------------------------------------------------

create or replace function private.guard_client_risk_state_tenant_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_org uuid;
  v_client uuid;
begin
  if new.source_session_id is not null then
    select ws.organization_id,ws.client_id
      into v_org,v_client
    from public.workout_sessions ws
    where ws.id=new.source_session_id;

    if v_org is null then
      raise exception 'risk state source session not found';
    end if;
    if new.client_id<>v_client then
      raise exception 'risk state client must match source session client';
    end if;

    if new.organization_id is null then
      new.organization_id:=v_org;
    elsif new.organization_id<>v_org then
      raise exception 'risk state cannot cross session organization boundary';
    end if;
  end if;

  if new.source_event_id is not null then
    select e.organization_id,e.client_id
      into v_org,v_client
    from public.event_outbox e
    where e.id=new.source_event_id;

    if v_org is null then
      raise exception 'risk state source event not found';
    end if;
    if new.client_id<>v_client then
      raise exception 'risk state client must match source event client';
    end if;

    if new.organization_id is null then
      new.organization_id:=v_org;
    elsif new.organization_id<>v_org then
      raise exception 'risk state cannot cross event organization boundary';
    end if;
  end if;

  if new.organization_id is null then
    new.organization_id:=private.resolve_legacy_client_organization_v1(
      new.client_id,null
    );
  end if;

  if not exists(
    select 1
    from public.clients c
    where c.organization_id=new.organization_id
      and c.user_id=new.client_id
      and c.status<>'archived'::public.client_status
  ) then
    raise exception 'risk state client is not canonical in organization';
  end if;

  if tg_op='UPDATE' and (
    new.organization_id is distinct from old.organization_id
    or new.client_id is distinct from old.client_id
  ) then
    raise exception 'risk state tenant identity is immutable';
  end if;

  return new;
end;
$function$;

create or replace function private.guard_weekly_risk_tenant_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_org uuid;
  v_client uuid;
begin
  select c.organization_id,c.client_id
    into v_org,v_client
  from public.weekly_checkins c
  where c.id=new.checkin_id;

  if v_org is null then
    raise exception 'weekly risk check-in not found';
  end if;
  if new.client_id<>v_client then
    raise exception 'weekly risk client must match check-in client';
  end if;

  if new.organization_id is null then
    new.organization_id:=v_org;
  elsif new.organization_id<>v_org then
    raise exception 'weekly risk cannot cross check-in organization boundary';
  end if;

  if not exists(
    select 1
    from public.event_outbox e
    where e.id=new.source_event_id
      and e.organization_id=new.organization_id
      and e.client_id=new.client_id
  ) then
    raise exception 'weekly risk source event crosses organization/client boundary';
  end if;

  if tg_op='UPDATE' and (
    new.organization_id is distinct from old.organization_id
    or new.client_id is distinct from old.client_id
    or new.checkin_id is distinct from old.checkin_id
  ) then
    raise exception 'weekly risk tenant identity is immutable';
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_client_risk_state_tenant_v1
  on public.client_risk_state;

create trigger trg_client_risk_state_tenant_v1
before insert or update on public.client_risk_state
for each row execute function private.guard_client_risk_state_tenant_v1();

drop trigger if exists trg_weekly_risk_tenant_v1
  on private.weekly_checkin_risk_assessments;

create trigger trg_weekly_risk_tenant_v1
before insert or update on private.weekly_checkin_risk_assessments
for each row execute function private.guard_weekly_risk_tenant_v1();

-- ---------------------------------------------------------------------------
-- 4) Tenant-aware RLS for risk state
-- ---------------------------------------------------------------------------

drop policy if exists client_risk_state_insert_manage
  on public.client_risk_state;
drop policy if exists client_risk_state_select_manage
  on public.client_risk_state;
drop policy if exists client_risk_state_update_manage
  on public.client_risk_state;

create policy client_risk_state_insert_manage_v2
on public.client_risk_state for insert
to authenticated
with check (
  private.can_manage_client_in_org(organization_id,client_id)
);

create policy client_risk_state_select_manage_v2
on public.client_risk_state for select
to authenticated
using (
  private.can_manage_client_in_org(organization_id,client_id)
);

create policy client_risk_state_update_manage_v2
on public.client_risk_state for update
to authenticated
using (
  private.can_manage_client_in_org(organization_id,client_id)
)
with check (
  private.can_manage_client_in_org(organization_id,client_id)
);

revoke truncate,trigger,references
on table public.client_risk_state
from public,anon,authenticated;

-- ---------------------------------------------------------------------------
-- 5) Weekly recovery context: explicit tenant helper + safe legacy wrapper
-- ---------------------------------------------------------------------------

create or replace function private.latest_weekly_recovery_context_in_org(
  p_organization_id uuid,
  p_client_id uuid,
  p_as_of timestamp with time zone default now()
)
returns table(
  checkin_id uuid,
  submitted_at timestamp with time zone,
  sleep_hours_avg numeric,
  sleep_quality integer,
  energy_level integer,
  stress_level integer,
  soreness_score integer,
  pain_score integer,
  pain_notes text,
  motivation_level integer,
  available_days_next_week integer,
  workouts_completed_7d integer,
  habit_logs_7d integer,
  habit_completion_pct_7d numeric,
  nutrition_days_7d integer,
  nutrition_adherence_pct_7d numeric,
  risk_level public.risk_level,
  risk_score integer,
  risk_reason_code text,
  risk_reason_text text,
  risk_requires_coach boolean
)
language sql
stable security definer
set search_path to ''
as $function$
  select
    c.id,
    c.submitted_at,
    c.sleep_hours_avg,
    c.sleep_quality,
    c.energy_level,
    c.stress_level,
    c.soreness_score,
    c.pain_score,
    c.pain_notes,
    c.motivation_level,
    c.available_days_next_week,
    c.workouts_completed_7d,
    c.habit_logs_7d,
    c.habit_completion_pct_7d,
    c.nutrition_days_7d,
    c.nutrition_adherence_pct_7d,
    r.level,
    r.score,
    r.reason_code,
    r.reason_text,
    r.requires_coach
  from public.weekly_checkins c
  left join private.weekly_checkin_risk_assessments r
    on r.organization_id=c.organization_id
   and r.checkin_id=c.id
   and r.client_id=c.client_id
  where c.organization_id=p_organization_id
    and c.client_id=p_client_id
    and c.submitted_at<=coalesce(p_as_of,now())
    and c.submitted_at>=coalesce(p_as_of,now())-interval '8 days'
  order by c.submitted_at desc
  limit 1
$function$;

create or replace function private.latest_weekly_recovery_context(
  p_client_id uuid,
  p_as_of timestamp with time zone default now()
)
returns table(
  checkin_id uuid,
  submitted_at timestamp with time zone,
  sleep_hours_avg numeric,
  sleep_quality integer,
  energy_level integer,
  stress_level integer,
  soreness_score integer,
  pain_score integer,
  pain_notes text,
  motivation_level integer,
  available_days_next_week integer,
  workouts_completed_7d integer,
  habit_logs_7d integer,
  habit_completion_pct_7d numeric,
  nutrition_days_7d integer,
  nutrition_adherence_pct_7d numeric,
  risk_level public.risk_level,
  risk_score integer,
  risk_reason_code text,
  risk_reason_text text,
  risk_requires_coach boolean
)
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_organization uuid;
begin
  v_organization:=private.resolve_legacy_client_organization_v1(
    p_client_id,null
  );

  return query
  select *
  from private.latest_weekly_recovery_context_in_org(
    v_organization,p_client_id,p_as_of
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 6) Canonical Coach Alert helper
-- ---------------------------------------------------------------------------

create or replace function private.set_coach_alert_in_org(
  p_organization_id uuid,
  p_coach_id uuid,
  p_client_id uuid,
  p_alert_type text,
  p_active boolean,
  p_severity public.alert_severity,
  p_title text,
  p_message text,
  p_source_data jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_id uuid;
begin
  if not exists(
    select 1
    from public.clients c
    join public.coach_profiles cp
      on cp.organization_id=c.organization_id
     and cp.user_id=p_coach_id
     and cp.status='active'::public.coach_profile_status
    join public.client_coach_assignments a
      on a.organization_id=c.organization_id
     and a.client_id=c.id
     and a.coach_id=cp.id
     and a.status='active'::public.client_coach_assignment_status
    where c.organization_id=p_organization_id
      and c.user_id=p_client_id
      and c.status<>'archived'::public.client_status
  ) then
    raise exception 'coach/client assignment is not active in organization';
  end if;

  if private.is_demo_client(p_client_id) then
    update public.coach_alerts
    set status='resolved'::public.alert_status,
        resolved_at=coalesce(resolved_at,now()),
        updated_at=now()
    where organization_id=p_organization_id
      and coach_id=p_coach_id
      and client_id=p_client_id
      and status in (
        'open'::public.alert_status,
        'acknowledged'::public.alert_status
      );
    return;
  end if;

  if p_active then
    select ca.id into v_id
    from public.coach_alerts ca
    where ca.organization_id=p_organization_id
      and ca.coach_id=p_coach_id
      and ca.client_id=p_client_id
      and ca.alert_type=p_alert_type
      and ca.status in (
        'open'::public.alert_status,
        'acknowledged'::public.alert_status
      )
    order by ca.created_at desc
    limit 1;

    if v_id is null then
      insert into public.coach_alerts(
        organization_id,coach_id,client_id,alert_type,severity,
        title,message,source_data,status
      )
      values(
        p_organization_id,p_coach_id,p_client_id,p_alert_type,p_severity,
        p_title,p_message,
        jsonb_build_object('organization_id',p_organization_id)
          ||coalesce(p_source_data,'{}'::jsonb),
        'open'::public.alert_status
      );
    else
      update public.coach_alerts
      set severity=p_severity,
          title=p_title,
          message=p_message,
          source_data=jsonb_build_object(
            'organization_id',p_organization_id
          )||coalesce(p_source_data,'{}'::jsonb),
          updated_at=now()
      where id=v_id
        and organization_id=p_organization_id;
    end if;
  else
    update public.coach_alerts
    set status='resolved'::public.alert_status,
        resolved_at=coalesce(resolved_at,now()),
        updated_at=now()
    where organization_id=p_organization_id
      and coach_id=p_coach_id
      and client_id=p_client_id
      and alert_type=p_alert_type
      and status in (
        'open'::public.alert_status,
        'acknowledged'::public.alert_status
      );
  end if;
end;
$function$;

-- Safe compatibility wrapper for remaining legacy callers.
create or replace function private.set_coach_alert(
  p_coach_id uuid,
  p_client_id uuid,
  p_alert_type text,
  p_active boolean,
  p_severity public.alert_severity,
  p_title text,
  p_message text,
  p_source_data jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_organization uuid;
begin
  v_organization:=private.resolve_legacy_client_organization_v1(
    p_client_id,null
  );

  perform private.set_coach_alert_in_org(
    v_organization,p_coach_id,p_client_id,p_alert_type,p_active,
    p_severity,p_title,p_message,p_source_data
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 7) Weekly check-in risk engine
-- ---------------------------------------------------------------------------

create or replace function private.assess_weekly_checkin_risk(
  p_checkin_id uuid,
  p_event_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  c public.weekly_checkins%rowtype;
  v_level public.risk_level:='GREEN'::public.risk_level;
  v_score integer:=15;
  v_code text:='weekly_checkin_stable';
  v_text text:='Check-in semanal sin señales estructuradas que requieran intervención.';
  v_requires boolean:=false;
  v_current public.client_risk_state%rowtype;
  v_coach uuid;
begin
  select * into c
  from public.weekly_checkins
  where id=p_checkin_id;

  if not found then
    raise exception 'weekly check-in not found';
  end if;

  if not exists(
    select 1
    from public.event_outbox e
    where e.id=p_event_id
      and e.organization_id=c.organization_id
      and e.aggregate_id=p_checkin_id
      and e.client_id=c.client_id
      and e.event_key='CHECKIN_SUBMITTED'
  ) then
    raise exception 'check-in source event mismatch';
  end if;

  if coalesce(c.pain_score,0)>=7 then
    v_level:='RED';
    v_score:=85;
    v_code:='weekly_high_pain';
    v_text:='El alumno reportó dolor alto en el check-in semanal. Requiere revisión del coach antes de progresar.';
    v_requires:=true;
  elsif coalesce(c.pain_score,0)>=4 then
    v_level:='YELLOW';
    v_score:=60;
    v_code:='weekly_pain_review';
    v_text:='El alumno reportó dolor relevante en el check-in semanal. Revisar antes de progresar.';
    v_requires:=true;
  elsif coalesce(c.sleep_hours_avg,99)<5
        and coalesce(c.energy_level,5)<=2 then
    v_level:='YELLOW';
    v_score:=55;
    v_code:='weekly_low_sleep_energy';
    v_text:='El check-in muestra sueño bajo y energía baja. Conviene revisar recuperación antes de progresar carga.';
    v_requires:=true;
  elsif coalesce(c.stress_level,1)>=5
        and coalesce(c.energy_level,5)<=2 then
    v_level:='YELLOW';
    v_score:=55;
    v_code:='weekly_high_stress_low_energy';
    v_text:='El check-in muestra estrés muy alto junto con energía baja. Conviene revisar recuperación y carga.';
    v_requires:=true;
  elsif coalesce(c.soreness_score,0)>=8
        and coalesce(c.energy_level,5)<=2 then
    v_level:='YELLOW';
    v_score:=50;
    v_code:='weekly_high_soreness_low_energy';
    v_text:='El check-in muestra rigidez/fatiga muscular alta junto con energía baja. Conviene revisar recuperación.';
    v_requires:=true;
  end if;

  insert into private.weekly_checkin_risk_assessments(
    organization_id,checkin_id,client_id,source_event_id,
    level,score,reason_code,reason_text,requires_coach
  )
  values(
    c.organization_id,c.id,c.client_id,p_event_id,
    v_level,v_score,v_code,v_text,v_requires
  )
  on conflict(checkin_id) do update set
    organization_id=excluded.organization_id,
    source_event_id=excluded.source_event_id,
    level=excluded.level,
    score=excluded.score,
    reason_code=excluded.reason_code,
    reason_text=excluded.reason_text,
    requires_coach=excluded.requires_coach,
    created_at=now();

  select * into v_current
  from public.client_risk_state
  where organization_id=c.organization_id
    and client_id=c.client_id;

  if v_level<>'GREEN'::public.risk_level
     or v_current.client_id is null
     or not coalesce(v_current.requires_coach,false) then

    insert into public.client_risk_state(
      organization_id,client_id,level,score,reason_code,reason_text,
      source_event_id,source_session_id,requires_coach,assessed_at,updated_at
    )
    values(
      c.organization_id,c.client_id,v_level,v_score,v_code,v_text,
      p_event_id,null,v_requires,now(),now()
    )
    on conflict(organization_id,client_id) do update set
      level=case
        when public.client_risk_state.requires_coach
             and excluded.level='GREEN'::public.risk_level
          then public.client_risk_state.level
        when excluded.score>=public.client_risk_state.score
          then excluded.level
        else public.client_risk_state.level
      end,
      score=case
        when public.client_risk_state.requires_coach
             and excluded.level='GREEN'::public.risk_level
          then public.client_risk_state.score
        else greatest(public.client_risk_state.score,excluded.score)
      end,
      reason_code=case
        when excluded.score>=public.client_risk_state.score
          then excluded.reason_code
        else public.client_risk_state.reason_code
      end,
      reason_text=case
        when excluded.score>=public.client_risk_state.score
          then excluded.reason_text
        else public.client_risk_state.reason_text
      end,
      source_event_id=case
        when excluded.score>=public.client_risk_state.score
          then excluded.source_event_id
        else public.client_risk_state.source_event_id
      end,
      source_session_id=case
        when excluded.score>=public.client_risk_state.score
          then null
        else public.client_risk_state.source_session_id
      end,
      requires_coach=
        public.client_risk_state.requires_coach
        or excluded.requires_coach,
      assessed_at=now(),
      updated_at=now();
  end if;

  select cp.user_id into v_coach
  from public.clients cl
  join public.client_coach_assignments a
    on a.organization_id=cl.organization_id
   and a.client_id=cl.id
   and a.status='active'::public.client_coach_assignment_status
  join public.coach_profiles cp
    on cp.organization_id=a.organization_id
   and cp.id=a.coach_id
   and cp.status='active'::public.coach_profile_status
  where cl.organization_id=c.organization_id
    and cl.user_id=c.client_id
    and cl.status<>'archived'::public.client_status
  order by
    (a.assignment_role='primary'::public.client_coach_assignment_role) desc,
    a.assigned_at desc
  limit 1;

  if v_coach is not null then
    perform private.set_coach_alert_in_org(
      c.organization_id,
      v_coach,
      c.client_id,
      'weekly_recovery',
      v_requires,
      case
        when v_level='RED' then 'critical'::public.alert_severity
        when v_level='YELLOW' then 'warning'::public.alert_severity
        else 'info'::public.alert_severity
      end,
      case
        when v_level='RED' then 'Check-in semanal: recuperación crítica'
        when v_level='YELLOW' then 'Check-in semanal: revisar recuperación'
        else 'Check-in semanal estable'
      end,
      v_text,
      jsonb_build_object(
        'organization_id',c.organization_id,
        'checkin_id',c.id,
        'event_id',p_event_id,
        'risk_level',v_level,
        'risk_score',v_score,
        'reason_code',v_code,
        'sleep_hours_avg',c.sleep_hours_avg,
        'sleep_quality',c.sleep_quality,
        'energy_level',c.energy_level,
        'stress_level',c.stress_level,
        'soreness_score',c.soreness_score,
        'pain_score',c.pain_score,
        'motivation_level',c.motivation_level,
        'available_days_next_week',c.available_days_next_week
      )
    );
  end if;

  return jsonb_build_object(
    'organization_id',c.organization_id,
    'checkin_id',c.id,
    'level',v_level,
    'score',v_score,
    'reason_code',v_code,
    'requires_coach',v_requires
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 8) Workout risk engine
-- ---------------------------------------------------------------------------

create or replace function public.apply_workout_risk_assessment(
  p_client_id uuid,
  p_session_id uuid,
  p_event_id uuid,
  p_level public.risk_level,
  p_score integer,
  p_reason_code text,
  p_reason_text text,
  p_requires_coach boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_coach_id uuid;
  v_severity public.alert_severity;
  v_active boolean;
  v_session public.workout_sessions%rowtype;
  v_recovery record;
  v_level public.risk_level:=p_level;
  v_score integer:=p_score;
  v_reason_code text:=p_reason_code;
  v_reason_text text:=p_reason_text;
  v_requires_coach boolean:=coalesce(p_requires_coach,false);
  v_weekly_floor boolean:=false;
  v_weekly_reason_used boolean:=false;
begin
  if p_score is null or p_score<0 or p_score>100 then
    raise exception 'risk score must be between 0 and 100';
  end if;

  select * into v_session
  from public.workout_sessions ws
  where ws.id=p_session_id
    and ws.client_id=p_client_id;

  if not found then
    raise exception 'session/client mismatch';
  end if;

  if not exists(
    select 1
    from public.event_outbox e
    where e.id=p_event_id
      and e.organization_id=v_session.organization_id
      and e.aggregate_id=p_session_id
      and e.client_id=p_client_id
      and e.event_key in ('WORKOUT_COMPLETED','WORKOUT_ABANDONED')
  ) then
    raise exception 'source event mismatch';
  end if;

  if coalesce(v_session.pain_score,0)>=7 then
    v_level:='RED';
    v_score:=greatest(v_score,85);
    v_requires_coach:=true;
    v_reason_code:='high_pain_feedback';
    v_reason_text:='El alumno reportó dolor alto al finalizar la sesión. Requiere revisión del coach antes de progresar.';
  elsif coalesce(v_session.pain_score,0)>=4 then
    if v_level='GREEN' then v_level:='YELLOW'; end if;
    v_score:=greatest(v_score,60);
    v_requires_coach:=true;
    v_reason_code:='pain_feedback_review';
    v_reason_text:='El alumno reportó dolor relevante al finalizar la sesión. Revisar antes de progresar.';
  elsif coalesce(v_session.fatigue_score,0)>=8
        or coalesce(v_session.client_effort,0)>=9 then
    if v_level='GREEN' then v_level:='YELLOW'; end if;
    v_score:=greatest(v_score,50);
    v_requires_coach:=true;

    if coalesce(v_session.fatigue_score,0)>=8
       and coalesce(v_session.client_effort,0)>=9 then
      v_reason_code:='high_effort_and_fatigue_feedback';
      v_reason_text:='El alumno reportó RPE global y fatiga altos al finalizar la sesión. Revisar recuperación antes de progresar.';
    elsif coalesce(v_session.fatigue_score,0)>=8 then
      v_reason_code:='high_fatigue_feedback';
      v_reason_text:='El alumno reportó fatiga alta al finalizar la sesión. Revisar recuperación antes de progresar.';
    else
      v_reason_code:='high_session_effort';
      v_reason_text:='El alumno reportó RPE global alto al finalizar la sesión. Revisar recuperación antes de progresar.';
    end if;
  end if;

  select * into v_recovery
  from private.latest_weekly_recovery_context_in_org(
    v_session.organization_id,
    p_client_id,
    coalesce(v_session.finished_at,v_session.started_at)
  );

  if v_recovery.checkin_id is not null
     and v_recovery.risk_level is not null
     and v_recovery.risk_level<>'GREEN'::public.risk_level then
    v_weekly_floor:=true;

    if v_recovery.risk_level='RED'::public.risk_level
       and (
         v_level<>'RED'::public.risk_level
         or coalesce(v_recovery.risk_score,0)>v_score
       ) then
      v_level:='RED'::public.risk_level;
      v_reason_code:=coalesce(
        v_recovery.risk_reason_code,'weekly_recovery_red'
      );
      v_reason_text:=coalesce(
        v_recovery.risk_reason_text,
        'El check-in semanal requiere revisión antes de progresar.'
      );
      v_weekly_reason_used:=true;
    elsif v_recovery.risk_level='YELLOW'::public.risk_level
          and v_level='GREEN'::public.risk_level then
      v_level:='YELLOW'::public.risk_level;
      v_reason_code:=coalesce(
        v_recovery.risk_reason_code,'weekly_recovery_yellow'
      );
      v_reason_text:=coalesce(
        v_recovery.risk_reason_text,
        'El check-in semanal requiere revisar recuperación antes de progresar.'
      );
      v_weekly_reason_used:=true;
    end if;

    v_score:=greatest(v_score,coalesce(v_recovery.risk_score,0));
    v_requires_coach:=
      v_requires_coach or coalesce(v_recovery.risk_requires_coach,false);
  end if;

  insert into public.client_risk_state(
    organization_id,client_id,level,score,reason_code,reason_text,
    source_event_id,source_session_id,requires_coach,assessed_at,updated_at
  )
  values(
    v_session.organization_id,p_client_id,v_level,v_score,
    left(v_reason_code,120),left(v_reason_text,1000),
    p_event_id,p_session_id,v_requires_coach,now(),now()
  )
  on conflict(organization_id,client_id) do update set
    level=excluded.level,
    score=excluded.score,
    reason_code=excluded.reason_code,
    reason_text=excluded.reason_text,
    source_event_id=excluded.source_event_id,
    source_session_id=excluded.source_session_id,
    requires_coach=excluded.requires_coach,
    assessed_at=now(),
    updated_at=now();

  select cp.user_id into v_coach_id
  from public.clients cl
  join public.client_coach_assignments a
    on a.organization_id=cl.organization_id
   and a.client_id=cl.id
   and a.status='active'::public.client_coach_assignment_status
  join public.coach_profiles cp
    on cp.organization_id=a.organization_id
   and cp.id=a.coach_id
   and cp.status='active'::public.coach_profile_status
  where cl.organization_id=v_session.organization_id
    and cl.user_id=p_client_id
    and cl.status<>'archived'::public.client_status
  order by
    (a.assignment_role='primary'::public.client_coach_assignment_role) desc,
    a.assigned_at desc
  limit 1;

  v_active:=
    (v_level<>'GREEN'::public.risk_level) or v_requires_coach;

  v_severity:=case
    when v_level='RED' then 'critical'::public.alert_severity
    when v_level='YELLOW' then 'warning'::public.alert_severity
    else 'info'::public.alert_severity
  end;

  if v_coach_id is not null then
    perform private.set_coach_alert_in_org(
      v_session.organization_id,
      v_coach_id,
      p_client_id,
      'training_risk',
      v_active,
      v_severity,
      case
        when v_level='RED' then 'Riesgo alto de entrenamiento'
        when v_level='YELLOW' then 'Revisión de entrenamiento requerida'
        else 'Riesgo de entrenamiento normalizado'
      end,
      left(coalesce(v_reason_text,'Evaluación automática CV Coach'),1000),
      jsonb_build_object(
        'organization_id',v_session.organization_id,
        'risk_level',v_level,
        'risk_score',v_score,
        'reason_code',v_reason_code,
        'source_event_id',p_event_id,
        'source_session_id',p_session_id,
        'client_effort',v_session.client_effort,
        'fatigue_score',v_session.fatigue_score,
        'pain_score',v_session.pain_score,
        'feedback_safety_floor_applied',(
          coalesce(v_session.pain_score,0)>=4
          or coalesce(v_session.fatigue_score,0)>=8
          or coalesce(v_session.client_effort,0)>=9
        ),
        'weekly_recovery_floor_applied',v_weekly_floor,
        'weekly_reason_used',v_weekly_reason_used,
        'weekly_checkin_id',v_recovery.checkin_id,
        'weekly_sleep_hours_avg',v_recovery.sleep_hours_avg,
        'weekly_energy_level',v_recovery.energy_level,
        'weekly_stress_level',v_recovery.stress_level,
        'weekly_soreness_score',v_recovery.soreness_score,
        'weekly_pain_score',v_recovery.pain_score
      )
    );
  end if;

  return jsonb_build_object(
    'organization_id',v_session.organization_id,
    'client_id',p_client_id,
    'level',v_level,
    'score',v_score,
    'reason_code',v_reason_code,
    'requires_coach',v_requires_coach,
    'coach_alert_active',v_active and v_coach_id is not null,
    'coach_id',v_coach_id,
    'feedback_safety_floor_applied',(
      coalesce(v_session.pain_score,0)>=4
      or coalesce(v_session.fatigue_score,0)>=8
      or coalesce(v_session.client_effort,0)>=9
    ),
    'weekly_recovery_floor_applied',v_weekly_floor,
    'weekly_checkin_id',v_recovery.checkin_id
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 9) Green auto-approval remains inside the source Session tenant
-- ---------------------------------------------------------------------------

create or replace function private.auto_approve_green_progressions(
  p_session_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_risk public.client_risk_state%rowtype;
  v_session public.workout_sessions%rowtype;
  r record;
  v_approved integer:=0;
  v_action text;
  v_safe boolean;
begin
  select * into v_session
  from public.workout_sessions
  where id=p_session_id;

  if not found then
    return jsonb_build_object(
      'status','skipped','reason','session_missing','approved',0
    );
  end if;

  select * into v_risk
  from public.client_risk_state
  where organization_id=v_session.organization_id
    and client_id=v_session.client_id
    and source_session_id=p_session_id;

  if not found then
    return jsonb_build_object(
      'status','skipped','reason','risk_missing','approved',0
    );
  end if;

  if v_risk.level<>'GREEN'::public.risk_level
     or coalesce(v_risk.requires_coach,false)
     or coalesce(v_risk.score,100)>25 then
    return jsonb_build_object(
      'status','skipped',
      'reason','risk_not_green_autoapprove',
      'approved',0
    );
  end if;

  if coalesce(v_session.pain_score,0)>=3
     or coalesce(v_session.fatigue_score,0)>=8
     or coalesce(v_session.client_effort,0)>=9 then
    return jsonb_build_object(
      'status','skipped',
      'reason','session_feedback_requires_review',
      'approved',0
    );
  end if;

  for r in
    select
      s.id as suggestion_id,
      s.client_id,
      s.exercise_id,
      s.previous_load,
      s.suggested_load,
      ad.id as decision_id,
      ad.structured_output,
      ad.deterministic_signal,
      ad.confidence,
      ad.requires_coach,
      lower(coalesce(ad.structured_output->>'action','')) as action
    from public.progression_suggestions s
    join lateral (
      select x.*
      from private.ai_decisions x
      where x.source_session_id=s.source_session_id
        and x.exercise_id=s.exercise_id
        and x.decision_type='training_progression'
        and x.validation_status='accepted'
      order by x.created_at desc
      limit 1
    ) ad on true
    where s.organization_id=v_session.organization_id
      and s.source_session_id=p_session_id
      and s.client_id=v_session.client_id
      and s.status='pending'::public.progression_status
      and coalesce(ad.requires_coach,true)=false
      and coalesce(ad.confidence,0)>=90
  loop
    v_action:=r.action;
    v_safe:=false;

    if v_action in ('maintain','build_reps') then
      v_safe:=true;
    elsif v_action='increase_load'
      and r.deterministic_signal='eligible_load_increase'
      and r.previous_load is not null
      and r.previous_load>0
      and r.suggested_load is not null
      and r.suggested_load>r.previous_load
      and r.suggested_load<=r.previous_load*1.05
      and (r.suggested_load-r.previous_load)<=2.5 then
      v_safe:=true;
    end if;

    if v_safe then
      update public.progression_suggestions
      set status='approved'::public.progression_status,
          reviewed_at=now(),
          reviewed_by=null,
          updated_at=now()
      where id=r.suggestion_id
        and organization_id=v_session.organization_id
        and status='pending'::public.progression_status;

      if found then
        insert into private.progression_auto_approval_audit(
          suggestion_id,decision_id,source_session_id,client_id,
          exercise_id,action,deterministic_signal,confidence,rule_version
        )
        values(
          r.suggestion_id,r.decision_id,p_session_id,r.client_id,
          r.exercise_id,v_action,r.deterministic_signal,r.confidence,
          'GREEN_AUTOAPPROVAL_V2_FEEDBACK'
        )
        on conflict(suggestion_id) do nothing;

        v_approved:=v_approved+1;
      end if;
    end if;
  end loop;

  return jsonb_build_object(
    'status','ok',
    'organization_id',v_session.organization_id,
    'approved',v_approved,
    'rule_version','GREEN_AUTOAPPROVAL_V2_FEEDBACK'
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 10) Alert-close reconciliation is tenant-local
-- ---------------------------------------------------------------------------

create or replace function private.reconcile_risk_attention_on_alert_close_v59()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if old.status in (
       'open'::public.alert_status,
       'acknowledged'::public.alert_status
     )
     and new.status in (
       'resolved'::public.alert_status,
       'dismissed'::public.alert_status
     )
     and new.alert_type in ('training_risk','weekly_recovery')
     and not exists(
       select 1
       from public.coach_alerts a
       where a.organization_id=new.organization_id
         and a.client_id=new.client_id
         and a.id<>new.id
         and a.alert_type in ('training_risk','weekly_recovery')
         and a.status in (
           'open'::public.alert_status,
           'acknowledged'::public.alert_status
         )
     ) then

    update public.client_risk_state
    set requires_coach=false,
        updated_at=now()
    where organization_id=new.organization_id
      and client_id=new.client_id
      and requires_coach=true;
  end if;

  return new;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 11) Coach attention queue: canonical assignments, tenant-local joins
-- ---------------------------------------------------------------------------

create or replace function public.get_coach_attention_queue()
returns table(
  client_id uuid,
  first_name text,
  last_name text,
  risk_level public.risk_level,
  risk_score integer,
  risk_reason text,
  requires_coach boolean,
  open_alerts integer,
  critical_alerts integer,
  warning_alerts integer,
  pending_progressions integer,
  last_workout_at timestamp with time zone,
  days_since_workout integer,
  attention_score integer,
  priority text,
  next_action text
)
language sql
stable security definer
set search_path to ''
as $function$
  with canonical_assignments as (
    select
      a.organization_id,
      cl.user_id as client_user_id,
      cp.user_id as coach_user_id,
      a.assignment_role,
      a.assigned_at
    from public.client_coach_assignments a
    join public.clients cl
      on cl.organization_id=a.organization_id
     and cl.id=a.client_id
     and cl.status<>'archived'::public.client_status
     and cl.user_id is not null
    join public.coach_profiles cp
      on cp.organization_id=a.organization_id
     and cp.id=a.coach_id
     and cp.status='active'::public.coach_profile_status
    where a.status='active'::public.client_coach_assignment_status
      and (
        cp.user_id=(select auth.uid())
        or private.is_org_admin(a.organization_id)
        or (select auth.role())='service_role'
      )
  ),
  base as (
    select
      ca.organization_id,
      ca.client_user_id as client_id,
      p.first_name,
      p.last_name,
      coalesce(r.level,'GREEN'::public.risk_level) as risk_level,
      coalesce(r.score,0) as risk_score,
      r.reason_text as risk_reason,
      coalesce(r.requires_coach,false) as requires_coach,
      coalesce(a.open_alerts,0)::integer as open_alerts,
      coalesce(a.critical_alerts,0)::integer as critical_alerts,
      coalesce(a.warning_alerts,0)::integer as warning_alerts,
      coalesce(a.weekly_program_review_alerts,0)::integer
        as weekly_program_review_alerts,
      coalesce(a.active_risk_alerts,0)::integer as active_risk_alerts,
      coalesce(ps.pending_progressions,0)::integer as pending_progressions,
      w.last_workout_at,
      case
        when w.last_workout_at is null then null
        else floor(
          extract(epoch from (now()-w.last_workout_at))/86400
        )::integer
      end as days_since_workout
    from canonical_assignments ca
    join public.profiles p
      on p.id=ca.client_user_id
    left join public.client_risk_state r
      on r.organization_id=ca.organization_id
     and r.client_id=ca.client_user_id
    left join lateral (
      select
        count(*) filter(
          where alert.status in (
            'open'::public.alert_status,
            'acknowledged'::public.alert_status
          )
        )::integer as open_alerts,
        count(*) filter(
          where alert.status in (
            'open'::public.alert_status,
            'acknowledged'::public.alert_status
          )
          and alert.severity='critical'::public.alert_severity
        )::integer as critical_alerts,
        count(*) filter(
          where alert.status in (
            'open'::public.alert_status,
            'acknowledged'::public.alert_status
          )
          and alert.severity='warning'::public.alert_severity
        )::integer as warning_alerts,
        count(*) filter(
          where alert.status in (
            'open'::public.alert_status,
            'acknowledged'::public.alert_status
          )
          and alert.alert_type='weekly_program_review'
        )::integer as weekly_program_review_alerts,
        count(*) filter(
          where alert.status in (
            'open'::public.alert_status,
            'acknowledged'::public.alert_status
          )
          and alert.alert_type in ('training_risk','weekly_recovery')
        )::integer as active_risk_alerts
      from public.coach_alerts alert
      where alert.organization_id=ca.organization_id
        and alert.client_id=ca.client_user_id
        and alert.coach_id=ca.coach_user_id
    ) a on true
    left join lateral (
      select count(*)::integer as pending_progressions
      from public.progression_suggestions s
      where s.organization_id=ca.organization_id
        and s.client_id=ca.client_user_id
        and s.status='pending'::public.progression_status
    ) ps on true
    left join lateral (
      select max(coalesce(ws.finished_at,ws.started_at)) as last_workout_at
      from public.workout_sessions ws
      where ws.organization_id=ca.organization_id
        and ws.client_id=ca.client_user_id
        and ws.status::text in ('completed','partial','abandoned')
    ) w on true
  ),
  scored as (
    select
      b.*,
      greatest(
        (
          case
            when b.requires_coach or b.active_risk_alerts>0 then
              (
                case b.risk_level
                  when 'RED'::public.risk_level then 100
                  when 'YELLOW'::public.risk_level then 60
                  else 0
                end
              )+b.risk_score
            else 0
          end
          + b.critical_alerts*40
          + b.warning_alerts*15
          + least(b.pending_progressions,5)*3
          + case
              when b.days_since_workout is null then 20
              when b.days_since_workout>=14 then 25
              when b.days_since_workout>=7 then 10
              else 0
            end
        )::integer,
        case
          when b.weekly_program_review_alerts>0 then 20
          else 0
        end
      )::integer as attention_score
    from base b
  )
  select
    s.client_id,
    s.first_name,
    s.last_name,
    s.risk_level,
    s.risk_score,
    s.risk_reason,
    s.requires_coach,
    s.open_alerts,
    s.critical_alerts,
    s.warning_alerts,
    s.pending_progressions,
    s.last_workout_at,
    s.days_since_workout,
    s.attention_score,
    case
      when s.attention_score>=120 then 'CRITICAL'
      when s.attention_score>=60 then 'HIGH'
      when s.attention_score>=20 then 'MEDIUM'
      else 'NORMAL'
    end as priority,
    case
      when (s.requires_coach or s.active_risk_alerts>0)
           and (
             s.risk_level='RED'::public.risk_level
             or s.critical_alerts>0
           ) then 'Revisar inmediatamente'
      when s.weekly_program_review_alerts>0
        then 'Revisar programación semanal'
      when (s.requires_coach or s.active_risk_alerts>0)
           and (
             s.risk_level='YELLOW'::public.risk_level
             or s.warning_alerts>0
           ) then 'Revisar señales de entrenamiento'
      when s.days_since_workout is null or s.days_since_workout>=14
        then 'Contactar por inactividad'
      when s.pending_progressions>0
        then 'Revisar progresiones pendientes'
      else 'Sin acción prioritaria'
    end as next_action
  from scored s
  order by
    s.attention_score desc,
    s.last_name,
    s.first_name
$function$;

-- ---------------------------------------------------------------------------
-- 12) Alert resolution preserves tenant boundary
-- ---------------------------------------------------------------------------

create or replace function public.resolve_coach_alert_backend(
  p_actor_id uuid,
  p_alert_id uuid,
  p_resolution text default 'resolved'::text,
  p_note text default null::text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_alert public.coach_alerts%rowtype;
  v_actor_role text;
  v_request_role text:=coalesce(auth.role(),'');
  v_request_user uuid:=auth.uid();
  v_resolution public.alert_status;
  v_other_active_risk boolean:=false;
  v_risk_attention_cleared boolean:=false;
begin
  if p_actor_id is null or p_alert_id is null then
    raise exception 'actor_id and alert_id are required';
  end if;

  if v_request_role<>'service_role'
     and (v_request_user is null or v_request_user<>p_actor_id) then
    raise exception 'actor identity mismatch';
  end if;

  if lower(coalesce(p_resolution,'')) not in ('resolved','dismissed') then
    raise exception 'resolution must be resolved or dismissed';
  end if;

  if char_length(coalesce(p_note,''))>500 then
    raise exception 'resolution note too long';
  end if;

  v_resolution:=lower(p_resolution)::public.alert_status;

  select role::text into v_actor_role
  from public.profiles
  where id=p_actor_id
    and status::text='active';

  if v_actor_role not in ('admin','coach') then
    raise exception 'actor is not authorized to resolve coach alerts';
  end if;

  select * into v_alert
  from public.coach_alerts
  where id=p_alert_id
  for update;

  if not found then
    raise exception 'coach alert not found';
  end if;

  if v_request_role<>'service_role' then
    if v_actor_role='admin' then
      if not private.is_org_admin(v_alert.organization_id) then
        raise exception 'admin is not authorized in alert organization';
      end if;
    elsif v_actor_role='coach' then
      if v_alert.coach_id<>p_actor_id
         or not exists(
           select 1
           from public.clients cl
           join public.coach_profiles cp
             on cp.organization_id=cl.organization_id
            and cp.user_id=p_actor_id
            and cp.status='active'::public.coach_profile_status
           join public.client_coach_assignments a
             on a.organization_id=cl.organization_id
            and a.client_id=cl.id
            and a.coach_id=cp.id
            and a.status='active'::public.client_coach_assignment_status
           where cl.organization_id=v_alert.organization_id
             and cl.user_id=v_alert.client_id
             and cl.status<>'archived'::public.client_status
         ) then
        raise exception 'coach is not assigned to this alert client in organization';
      end if;
    end if;
  end if;

  if v_alert.status not in (
    'open'::public.alert_status,
    'acknowledged'::public.alert_status
  ) then
    return jsonb_build_object(
      'organization_id',v_alert.organization_id,
      'alert_id',v_alert.id,
      'client_id',v_alert.client_id,
      'status',v_alert.status::text,
      'idempotent',true,
      'risk_attention_cleared',false
    );
  end if;

  update public.coach_alerts
  set status=v_resolution,
      resolved_at=coalesce(resolved_at,now()),
      updated_at=now(),
      source_data=
        coalesce(source_data,'{}'::jsonb)
        ||jsonb_strip_nulls(jsonb_build_object(
          'organization_id',v_alert.organization_id,
          'resolved_by',p_actor_id,
          'resolution',v_resolution::text,
          'resolution_note',nullif(btrim(coalesce(p_note,'')),''),
          'resolved_at',now()
        ))
  where id=v_alert.id
    and organization_id=v_alert.organization_id;

  if v_alert.alert_type in ('training_risk','weekly_recovery') then
    select exists(
      select 1
      from public.coach_alerts a
      where a.organization_id=v_alert.organization_id
        and a.client_id=v_alert.client_id
        and a.id<>v_alert.id
        and a.alert_type in ('training_risk','weekly_recovery')
        and a.status in (
          'open'::public.alert_status,
          'acknowledged'::public.alert_status
        )
    ) into v_other_active_risk;

    if not v_other_active_risk then
      update public.client_risk_state
      set requires_coach=false,
          updated_at=now()
      where organization_id=v_alert.organization_id
        and client_id=v_alert.client_id
        and requires_coach=true;

      v_risk_attention_cleared:=found;
    end if;
  end if;

  return jsonb_build_object(
    'organization_id',v_alert.organization_id,
    'alert_id',v_alert.id,
    'client_id',v_alert.client_id,
    'status',v_resolution::text,
    'idempotent',false,
    'risk_attention_cleared',v_risk_attention_cleared,
    'risk_level_preserved',(
      select level::text
      from public.client_risk_state
      where organization_id=v_alert.organization_id
        and client_id=v_alert.client_id
    ),
    'risk_score_preserved',(
      select score
      from public.client_risk_state
      where organization_id=v_alert.organization_id
        and client_id=v_alert.client_id
    )
  );
end;
$function$;

comment on column public.client_risk_state.organization_id is
  'F1.M1.S5 tenant boundary for client risk state.';
comment on function public.get_coach_attention_queue() is
  'F1.M1.S5 compatibility queue: return shape preserved; every joined signal is tenant-local through canonical assignments.';
