-- CV Coach V83 — Adaptive Progression System
-- Extiende V82 con progresión por tiempo, estado adaptativo de bloque y revisión segura del coach.
-- Regla: recomienda y prepara la siguiente sesión; nunca reescribe un programa publicado.

begin;

alter table public.progression_suggestions
  add column if not exists previous_duration_seconds integer,
  add column if not exists suggested_duration_seconds integer;

alter table public.progression_suggestions
  drop constraint if exists progression_action_v82_valid;

alter table public.progression_suggestions
  add constraint progression_action_v83_valid
  check (action is null or action in (
    'collect_more_data','maintain','build_reps','increase_load','build_time','review'
  ));

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.progression_suggestions'::regclass
      and conname='progression_duration_v83_valid'
  ) then
    alter table public.progression_suggestions
      add constraint progression_duration_v83_valid
      check (
        (previous_duration_seconds is null or previous_duration_seconds >= 0)
        and (suggested_duration_seconds is null or suggested_duration_seconds >= 0)
      );
  end if;
end;
$$;

create table if not exists public.training_adaptation_reviews (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.profiles(id) on delete cascade,
  program_id uuid not null references public.programs(id) on delete cascade,
  source_session_id uuid not null unique references public.workout_sessions(id) on delete cascade,
  state text not null check (state in ('progressing','stable','stagnating','recovery_limited','deload_recommended')),
  block_week integer null check (block_week is null or block_week >= 1),
  recent_sessions integer not null default 0 check (recent_sessions >= 0),
  progress_signals integer not null default 0 check (progress_signals >= 0),
  stagnation_signals integer not null default 0 check (stagnation_signals >= 0),
  data_gap_signals integer not null default 0 check (data_gap_signals >= 0),
  recovery_flags integer not null default 0 check (recovery_flags >= 0),
  average_completion_pct numeric null,
  deload_recommended boolean not null default false,
  reason_codes jsonb not null default '[]'::jsonb,
  evidence jsonb not null default '{}'::jsonb,
  status text not null default 'pending' check (status in ('pending','reviewed','dismissed','cleared')),
  reviewed_by uuid null references public.profiles(id) on delete set null,
  reviewed_at timestamptz null,
  coach_notes text null check (coach_notes is null or char_length(coach_notes) <= 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists ix_training_adaptation_reviews_client
  on public.training_adaptation_reviews(client_id, created_at desc);
create index if not exists ix_training_adaptation_reviews_program
  on public.training_adaptation_reviews(program_id, created_at desc);
create index if not exists ix_training_adaptation_reviews_status
  on public.training_adaptation_reviews(status, state, created_at desc);

alter table public.training_adaptation_reviews enable row level security;

drop policy if exists training_adaptation_reviews_staff_read on public.training_adaptation_reviews;
create policy training_adaptation_reviews_staff_read
on public.training_adaptation_reviews
for select to authenticated
using (
  exists (
    select 1
    from public.profiles actor
    where actor.id=(select auth.uid())
      and actor.status::text='active'
      and (
        actor.role='admin'::public.app_role
        or (
          actor.role='coach'::public.app_role
          and exists (
            select 1 from public.coach_clients cc
            where cc.coach_id=actor.id
              and cc.client_id=training_adaptation_reviews.client_id
              and cc.status='active'::public.coach_client_status
          )
        )
      )
  )
);

revoke insert, update, delete on public.training_adaptation_reviews from anon, authenticated;
grant select on public.training_adaptation_reviews to authenticated;

create or replace function private.progression_recommendation_v83(
  p_session_id uuid,
  p_exercise_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  c private.training_session_exercise_metrics%rowtype;
  ws public.workout_sessions%rowtype;
  rc record;
  r jsonb;
  v_evidence integer:=0;
  v_ceiling_evidence integer:=0;
  v_action text:='collect_more_data';
  v_signal text:='no_data';
  v_reason text:='Se requieren más datos antes de progresar.';
  v_conf numeric:=0;
  v_band text:='low';
  v_target integer:=null;
begin
  select * into ws from public.workout_sessions where id=p_session_id;
  if not found then
    return jsonb_build_object(
      'engine_version','PROGRESSION_ENGINE_V83',
      'action','collect_more_data','signal','no_session',
      'confidence',0,'confidence_band','low',
      'reason','Sesión no encontrada.'
    );
  end if;

  select * into c
  from private.training_session_exercise_metrics
  where session_id=p_session_id and exercise_id=p_exercise_id;

  if not found then
    return jsonb_build_object(
      'engine_version','PROGRESSION_ENGINE_V83',
      'action','collect_more_data','signal','no_exercise_data',
      'confidence',0,'confidence_band','low',
      'reason','No hay datos ejecutados para este ejercicio.'
    );
  end if;

  if coalesce(c.prescription_unit,'reps')='reps' then
    r:=private.progression_recommendation_v82(p_session_id,p_exercise_id);
    return r || jsonb_build_object(
      'engine_version','PROGRESSION_ENGINE_V83',
      'mode','reps',
      'previous_duration_seconds',null,
      'suggested_duration_seconds',null
    );
  end if;

  if c.prescription_unit<>'seconds' then
    return jsonb_build_object(
      'engine_version','PROGRESSION_ENGINE_V83',
      'mode',coalesce(c.prescription_unit,'unknown'),
      'session_id',p_session_id,
      'exercise_id',p_exercise_id,
      'exercise_name',c.exercise_name,
      'action','collect_more_data',
      'signal','unsupported_progression_unit',
      'confidence',0,
      'confidence_band','low',
      'reason','La unidad de prescripción todavía no tiene progresión automática.'
    );
  end if;

  select count(*)::integer into v_evidence
  from private.training_session_exercise_metrics m
  where m.client_id=c.client_id
    and m.exercise_id=c.exercise_id
    and m.prescription_unit='seconds'
    and m.workout_status in ('completed','partial')
    and m.done_sets>0
    and coalesce(m.finished_at,m.started_at)<=coalesce(c.finished_at,c.started_at);

  select * into rc
  from private.latest_weekly_recovery_context(ws.client_id,coalesce(ws.finished_at,ws.started_at));

  if coalesce(ws.pain_score,0)>=4 or coalesce(ws.had_pain,false) then
    v_action:='review';
    v_signal:='hold_pain_feedback';
    v_reason:='Hubo dolor relevante en la sesión. La progresión por tiempo queda detenida para revisión del coach.';
  elsif coalesce(ws.client_effort,0)>=9 or coalesce(ws.difficulty_level,0)>=5 then
    v_action:='review';
    v_signal:='hold_high_session_effort';
    v_reason:='El esfuerzo global fue alto. Revisar recuperación antes de aumentar el tiempo objetivo.';
  elsif rc.checkin_id is not null and (
    coalesce(rc.risk_requires_coach,false)
    or (rc.risk_level is not null and rc.risk_level<>'GREEN'::public.risk_level)
    or coalesce(rc.pain_score,0)>=4
    or (coalesce(rc.sleep_hours_avg,99)<5 and coalesce(rc.energy_level,5)<=2)
    or (coalesce(rc.stress_level,1)>=5 and coalesce(rc.energy_level,5)<=2)
    or (coalesce(rc.soreness_score,0)>=8 and coalesce(rc.energy_level,5)<=2)
  ) then
    v_action:='review';
    v_signal:='hold_low_recovery';
    v_reason:='La recuperación semanal no permite justificar una progresión por tiempo.';
  elsif c.done_sets=0 then
    v_action:='collect_more_data';
    v_signal:='no_data';
    v_reason:='No hay series completadas para progresar el tiempo.';
  elsif c.target_sets is not null and c.done_sets<c.target_sets then
    v_action:='review';
    v_signal:='partial_session';
    v_reason:='No se completaron todas las series objetivo. Mantener antes de aumentar duración.';
  elsif c.min_duration_seconds is null then
    v_action:='collect_more_data';
    v_signal:='missing_duration';
    v_reason:='Falta duración válida en las series completadas.';
  elsif c.rep_min is null or c.rep_max is null or c.rep_max<c.rep_min then
    v_action:='collect_more_data';
    v_signal:='missing_duration_range';
    v_reason:='El ejercicio por tiempo necesita un rango mínimo y máximo válido.';
  elsif c.min_duration_seconds<c.rep_min then
    v_action:='review';
    v_signal:='below_duration_range_review';
    v_reason:='Al menos una serie quedó bajo el tiempo mínimo prescrito. Revisar dificultad antes de progresar.';
  elsif c.min_duration_seconds>=c.rep_max then
    select count(*)::integer into v_ceiling_evidence
    from private.training_session_exercise_metrics m
    where m.client_id=c.client_id
      and m.exercise_id=c.exercise_id
      and m.prescription_unit='seconds'
      and m.workout_status in ('completed','partial')
      and m.done_sets>=coalesce(m.target_sets,m.done_sets)
      and m.min_duration_seconds>=coalesce(m.rep_max,2147483647)
      and coalesce(m.finished_at,m.started_at)<=coalesce(c.finished_at,c.started_at);

    if v_ceiling_evidence>=2 then
      v_action:='review';
      v_signal:='time_ceiling_reached';
      v_reason:='El techo de tiempo fue completado en exposiciones repetidas. Revisar una variante más exigente o el siguiente bloque; no superar el rango publicado automáticamente.';
    else
      v_action:='maintain';
      v_signal:='hold_collect_evidence';
      v_target:=c.rep_max;
      v_reason:='Se alcanzó el techo de tiempo una vez. Repetir la evidencia antes de cambiar la dificultad.';
    end if;
  else
    v_target:=least(
      c.rep_max,
      greatest(c.rep_min,((floor(c.min_duration_seconds/5.0)::integer)+1)*5)
    );
    if v_target>c.min_duration_seconds then
      v_action:='build_time';
      v_signal:='eligible_time_increase';
      v_reason:='Todas las series cumplieron el tiempo mínimo. Aumentar el objetivo en un paso de hasta 5 segundos sin superar el techo publicado.';
    else
      v_action:='maintain';
      v_signal:='hold_collect_evidence';
      v_reason:='Mantener el objetivo de tiempo y reunir otra exposición válida.';
    end if;
  end if;

  v_conf:=40+least(v_evidence,4)*8;
  if c.target_sets is not null and c.done_sets>=c.target_sets then v_conf:=v_conf+12; end if;
  if c.min_duration_seconds is not null then v_conf:=v_conf+10; end if;
  if c.rep_min is not null and c.rep_max is not null then v_conf:=v_conf+10; end if;
  if v_action='build_time' then v_conf:=v_conf+8; end if;
  if v_action='collect_more_data' then v_conf:=least(v_conf,64); end if;
  if v_action='review' then v_conf:=greatest(v_conf,85); end if;
  v_conf:=greatest(0,least(100,round(v_conf,2)));
  v_band:=case when v_conf>=85 then 'high' when v_conf>=65 then 'medium' else 'low' end;

  return jsonb_build_object(
    'engine_version','PROGRESSION_ENGINE_V83',
    'mode','seconds',
    'session_id',p_session_id,
    'exercise_id',p_exercise_id,
    'exercise_name',c.exercise_name,
    'prescription_unit','seconds',
    'signal',v_signal,
    'action',v_action,
    'reason',v_reason,
    'confidence',v_conf,
    'confidence_band',v_band,
    'evidence_sessions',v_evidence,
    'current_min_duration_seconds',c.min_duration_seconds,
    'current_max_duration_seconds',c.max_duration_seconds,
    'current_avg_duration_seconds',c.avg_duration_seconds,
    'target_duration_min',c.rep_min,
    'target_duration_max',c.rep_max,
    'previous_duration_seconds',c.max_duration_seconds,
    'suggested_duration_seconds',v_target,
    'suggested_load',null,
    'suggested_increment_kg',null,
    'suggested_rep_min',null,
    'suggested_rep_max',null,
    'session_feedback',jsonb_build_object(
      'difficulty_level',ws.difficulty_level,
      'client_effort',ws.client_effort,
      'pain_score',ws.pain_score,
      'had_pain',ws.had_pain
    ),
    'weekly_recovery',jsonb_build_object(
      'checkin_id',rc.checkin_id,
      'sleep_hours_avg',rc.sleep_hours_avg,
      'energy_level',rc.energy_level,
      'stress_level',rc.stress_level,
      'soreness_score',rc.soreness_score,
      'pain_score',rc.pain_score,
      'risk_level',case when rc.risk_level is null then null else rc.risk_level::text end,
      'requires_coach',rc.risk_requires_coach
    ),
    'rule','Time progression V83: +5 s máximo dentro del rango; nunca excede el techo publicado y el techo repetido exige revisión del coach.'
  );
end;
$$;

comment on function private.progression_recommendation_v83(uuid,uuid) is
  'V83 canonical progression recommendation for reps and seconds. Read-only and recovery-aware.';

create or replace function private.compute_training_adaptation_v83(
  p_client_id uuid,
  p_program_id uuid,
  p_as_of timestamptz default now()
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  pr public.programs%rowtype;
  rc record;
  m record;
  r jsonb;
  v_recent_sessions integer:=0;
  v_avg_completion numeric:=null;
  v_pain_sessions integer:=0;
  v_high_effort_sessions integer:=0;
  v_progress integer:=0;
  v_stagnation integer:=0;
  v_data_gaps integer:=0;
  v_recovery_flags integer:=0;
  v_time_ceiling integer:=0;
  v_block_week integer:=null;
  v_state text:='stable';
  v_deload boolean:=false;
  v_reasons jsonb:='[]'::jsonb;
begin
  select * into pr
  from public.programs
  where id=p_program_id and client_id=p_client_id;

  if not found then
    return jsonb_build_object(
      'engine_version','ADAPTATION_ENGINE_V83',
      'state','stable','recent_sessions',0,
      'deload_recommended',false,
      'reason_codes',jsonb_build_array('program_not_found')
    );
  end if;

  if pr.start_date is not null then
    v_block_week:=greatest(1,((greatest(0,(p_as_of::date-pr.start_date))/7)+1)::integer);
  end if;

  with recent as (
    select ws.*
    from public.workout_sessions ws
    where ws.client_id=p_client_id
      and ws.program_id=p_program_id
      and ws.status in ('completed'::public.workout_session_status,'partial'::public.workout_session_status)
      and coalesce(ws.finished_at,ws.started_at)<=p_as_of
    order by coalesce(ws.finished_at,ws.started_at) desc
    limit 4
  )
  select
    count(*)::integer,
    round(avg(completion_pct),2),
    count(*) filter (where coalesce(pain_score,0)>=4 or coalesce(had_pain,false))::integer,
    count(*) filter (where coalesce(client_effort,0)>=9 or coalesce(difficulty_level,0)>=5)::integer
  into v_recent_sessions,v_avg_completion,v_pain_sessions,v_high_effort_sessions
  from recent;

  select * into rc
  from private.latest_weekly_recovery_context(p_client_id,p_as_of);

  if rc.checkin_id is not null and (
    coalesce(rc.risk_requires_coach,false)
    or (rc.risk_level is not null and rc.risk_level<>'GREEN'::public.risk_level)
    or coalesce(rc.pain_score,0)>=4
    or (coalesce(rc.sleep_hours_avg,99)<5 and coalesce(rc.energy_level,5)<=2)
    or (coalesce(rc.stress_level,1)>=5 and coalesce(rc.energy_level,5)<=2)
    or (coalesce(rc.soreness_score,0)>=8 and coalesce(rc.energy_level,5)<=2)
  ) then
    v_recovery_flags:=v_recovery_flags+1;
  end if;
  if v_pain_sessions>0 then v_recovery_flags:=v_recovery_flags+1; end if;
  if v_high_effort_sessions>=2 then v_recovery_flags:=v_recovery_flags+1; end if;

  for m in
    with recent_sessions as (
      select ws.id
      from public.workout_sessions ws
      where ws.client_id=p_client_id
        and ws.program_id=p_program_id
        and ws.status in ('completed'::public.workout_session_status,'partial'::public.workout_session_status)
        and coalesce(ws.finished_at,ws.started_at)<=p_as_of
      order by coalesce(ws.finished_at,ws.started_at) desc
      limit 4
    ),
    ranked as (
      select tm.*,
             row_number() over(
               partition by tm.exercise_id
               order by coalesce(tm.finished_at,tm.started_at) desc,tm.started_at desc
             ) as rn
      from private.training_session_exercise_metrics tm
      join recent_sessions rs on rs.id=tm.session_id
      where tm.done_sets>0
    )
    select * from ranked where rn=1
  loop
    r:=private.progression_recommendation_v83(m.session_id,m.exercise_id);

    if coalesce(r->>'action','') in ('increase_load','build_reps','build_time') then
      v_progress:=v_progress+1;
    elsif coalesce(r->>'signal','') in (
      'below_rep_range_review','below_duration_range_review',
      'review_variable_load','partial_session','hold_high_effort'
    ) then
      v_stagnation:=v_stagnation+1;
    elsif coalesce(r->>'signal','')='time_ceiling_reached' then
      v_time_ceiling:=v_time_ceiling+1;
      v_stagnation:=v_stagnation+1;
    elsif coalesce(r->>'action','')='collect_more_data' then
      v_data_gaps:=v_data_gaps+1;
    end if;
  end loop;

  if v_block_week is not null
     and v_block_week>=5
     and v_recent_sessions>=3
     and (
       v_recovery_flags>0
       or v_high_effort_sessions>=2
       or v_stagnation>=2
       or v_time_ceiling>=2
     ) then
    v_state:='deload_recommended';
    v_deload:=true;
    v_reasons:=v_reasons||jsonb_build_array('block_age_plus_accumulated_fatigue_or_stagnation');
  elsif v_recovery_flags>0 then
    v_state:='recovery_limited';
    v_reasons:=v_reasons||jsonb_build_array('recovery_signal_requires_review');
  elsif v_recent_sessions>=3 and v_progress=0 and v_stagnation>=2 then
    v_state:='stagnating';
    v_reasons:=v_reasons||jsonb_build_array('repeated_non_progressing_exposures');
  elsif v_progress>=1 and v_stagnation<=v_progress then
    v_state:='progressing';
    v_reasons:=v_reasons||jsonb_build_array('productive_progression_signals');
  else
    v_state:='stable';
    if v_recent_sessions<2 then
      v_reasons:=v_reasons||jsonb_build_array('insufficient_recent_sessions');
    else
      v_reasons:=v_reasons||jsonb_build_array('stable_without_deload_signal');
    end if;
  end if;

  if v_pain_sessions>0 then v_reasons:=v_reasons||jsonb_build_array('recent_pain_feedback'); end if;
  if v_high_effort_sessions>=2 then v_reasons:=v_reasons||jsonb_build_array('repeated_high_effort'); end if;
  if v_time_ceiling>0 then v_reasons:=v_reasons||jsonb_build_array('time_ceiling_reached'); end if;
  if v_data_gaps>0 then v_reasons:=v_reasons||jsonb_build_array('data_gaps_present'); end if;

  return jsonb_build_object(
    'engine_version','ADAPTATION_ENGINE_V83',
    'client_id',p_client_id,
    'program_id',p_program_id,
    'state',v_state,
    'block_week',v_block_week,
    'recent_sessions',v_recent_sessions,
    'average_completion_pct',v_avg_completion,
    'progress_signals',v_progress,
    'stagnation_signals',v_stagnation,
    'data_gap_signals',v_data_gaps,
    'recovery_flags',v_recovery_flags,
    'pain_sessions',v_pain_sessions,
    'high_effort_sessions',v_high_effort_sessions,
    'time_ceiling_signals',v_time_ceiling,
    'deload_recommended',v_deload,
    'reason_codes',v_reasons,
    'weekly_recovery',jsonb_build_object(
      'checkin_id',rc.checkin_id,
      'sleep_hours_avg',rc.sleep_hours_avg,
      'energy_level',rc.energy_level,
      'stress_level',rc.stress_level,
      'soreness_score',rc.soreness_score,
      'pain_score',rc.pain_score,
      'risk_level',case when rc.risk_level is null then null else rc.risk_level::text end,
      'requires_coach',rc.risk_requires_coach
    ),
    'rule','V83 only recommends a deload after enough recent training evidence plus block age and fatigue/stagnation signals. It never edits the active program.'
  );
end;
$$;

comment on function private.compute_training_adaptation_v83(uuid,uuid,timestamptz) is
  'V83 deterministic block-state assessment: progressing/stable/stagnating/recovery-limited/deload-recommended.';

create or replace function private.seed_time_progressions_v83(p_session_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  ws public.workout_sessions%rowtype;
  m record;
  r jsonb;
  v_id uuid;
  v_created integer:=0;
  v_review integer:=0;
begin
  select * into ws from public.workout_sessions where id=p_session_id;
  if not found then return jsonb_build_object('status','skipped','reason','session_not_found'); end if;
  if ws.status not in ('completed'::public.workout_session_status,'partial'::public.workout_session_status) then
    return jsonb_build_object('status','skipped','reason','session_not_terminal');
  end if;
  if private.is_cv_canary_client(ws.client_id) then
    return jsonb_build_object('status','skipped','reason','canary_client');
  end if;

  for m in
    select *
    from private.training_session_exercise_metrics
    where session_id=p_session_id
      and prescription_unit='seconds'
      and done_sets>0
    order by exercise_name
  loop
    r:=private.progression_recommendation_v83(p_session_id,m.exercise_id);

    if coalesce(r->>'action','')='build_time' then
      v_id:=null;
      insert into public.progression_suggestions(
        client_id,exercise_id,source_session_id,
        previous_load,previous_reps,previous_duration_seconds,
        suggested_load,suggested_rep_min,suggested_rep_max,suggested_duration_seconds,
        reason_code,reason_text,confidence,status,
        action,engine_version,evidence_sessions,suggested_increment_kg,
        confidence_band,evidence,auto_generated
      ) values (
        ws.client_id,m.exercise_id,p_session_id,
        null,null,m.max_duration_seconds,
        null,null,null,nullif(r->>'suggested_duration_seconds','')::integer,
        left(coalesce(r->>'signal','build_time'),120),
        left(coalesce(r->>'reason','Progresión por tiempo V83'),1000),
        coalesce((r->>'confidence')::numeric,0),
        'pending'::public.progression_status,
        'build_time','PROGRESSION_ENGINE_V83',
        coalesce((r->>'evidence_sessions')::integer,0),
        null,
        coalesce(r->>'confidence_band','low'),
        r,true
      )
      on conflict(source_session_id,exercise_id) do update
      set previous_duration_seconds=excluded.previous_duration_seconds,
          suggested_duration_seconds=excluded.suggested_duration_seconds,
          suggested_load=null,
          suggested_rep_min=null,
          suggested_rep_max=null,
          reason_code=excluded.reason_code,
          reason_text=excluded.reason_text,
          confidence=excluded.confidence,
          action='build_time',
          engine_version='PROGRESSION_ENGINE_V83',
          evidence_sessions=excluded.evidence_sessions,
          suggested_increment_kg=null,
          confidence_band=excluded.confidence_band,
          evidence=excluded.evidence,
          auto_generated=true,
          updated_at=now()
      where public.progression_suggestions.status='pending'::public.progression_status
      returning id into v_id;

      if v_id is not null then v_created:=v_created+1; end if;
    elsif coalesce(r->>'action','')='review' then
      v_review:=v_review+1;
    end if;
  end loop;

  return jsonb_build_object(
    'status','ok',
    'engine_version','PROGRESSION_ENGINE_V83',
    'time_suggestions_created_or_refreshed',v_created,
    'time_review_signals',v_review
  );
end;
$$;

create or replace function private.seed_training_adaptation_v83(p_session_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  ws public.workout_sessions%rowtype;
  r jsonb;
  v_id uuid;
begin
  select * into ws from public.workout_sessions where id=p_session_id;
  if not found then return jsonb_build_object('status','skipped','reason','session_not_found'); end if;
  if ws.status not in ('completed'::public.workout_session_status,'partial'::public.workout_session_status) then
    return jsonb_build_object('status','skipped','reason','session_not_terminal');
  end if;
  if private.is_cv_canary_client(ws.client_id) then
    return jsonb_build_object('status','skipped','reason','canary_client');
  end if;

  r:=private.compute_training_adaptation_v83(ws.client_id,ws.program_id,coalesce(ws.finished_at,ws.started_at));

  insert into public.training_adaptation_reviews(
    client_id,program_id,source_session_id,state,block_week,recent_sessions,
    progress_signals,stagnation_signals,data_gap_signals,recovery_flags,
    average_completion_pct,deload_recommended,reason_codes,evidence,status
  ) values (
    ws.client_id,ws.program_id,p_session_id,
    coalesce(r->>'state','stable'),
    nullif(r->>'block_week','')::integer,
    coalesce((r->>'recent_sessions')::integer,0),
    coalesce((r->>'progress_signals')::integer,0),
    coalesce((r->>'stagnation_signals')::integer,0),
    coalesce((r->>'data_gap_signals')::integer,0),
    coalesce((r->>'recovery_flags')::integer,0),
    nullif(r->>'average_completion_pct','')::numeric,
    coalesce((r->>'deload_recommended')::boolean,false),
    coalesce(r->'reason_codes','[]'::jsonb),
    r,
    'pending'
  )
  on conflict(source_session_id) do update
  set state=excluded.state,
      block_week=excluded.block_week,
      recent_sessions=excluded.recent_sessions,
      progress_signals=excluded.progress_signals,
      stagnation_signals=excluded.stagnation_signals,
      data_gap_signals=excluded.data_gap_signals,
      recovery_flags=excluded.recovery_flags,
      average_completion_pct=excluded.average_completion_pct,
      deload_recommended=excluded.deload_recommended,
      reason_codes=excluded.reason_codes,
      evidence=excluded.evidence,
      status=case
        when public.training_adaptation_reviews.status='dismissed' then 'dismissed'
        else 'pending'
      end,
      updated_at=now()
  returning id into v_id;

  return jsonb_build_object('status','ok','review_id',v_id,'adaptation',r);
end;
$$;

create or replace function private.progression_adaptive_trigger_v83()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status='in_progress'::public.workout_session_status
     and new.status in ('completed'::public.workout_session_status,'partial'::public.workout_session_status) then
    perform private.seed_time_progressions_v83(new.id);
    perform private.seed_training_adaptation_v83(new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_workout_progression_adaptive_v83 on public.workout_sessions;
create trigger trg_workout_progression_adaptive_v83
after update of status on public.workout_sessions
for each row
when (old.status is distinct from new.status)
execute function private.progression_adaptive_trigger_v83();

create or replace function private.progression_suggestion_source_program_v83(p_suggestion_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select ws.program_id
  from public.progression_suggestions ps
  join public.workout_sessions ws on ws.id=ps.source_session_id
  where ps.id=p_suggestion_id
$$;

create or replace function private.guard_progression_suggestion_v83()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  r jsonb;
  v_action text;
  v_marker text:=coalesce(current_setting('cv.v83_review',true),'');
  v_program_id uuid;
  v_fresh boolean:=false;
  v_engine_load numeric;
  v_engine_rep_min integer;
  v_engine_rep_max integer;
  v_engine_duration integer;
begin
  if new.source_session_id is null or new.exercise_id is null then
    return new;
  end if;

  if tg_op='UPDATE'
     and old.status in ('approved'::public.progression_status,'modified'::public.progression_status)
     and new.status='rejected'::public.progression_status
     and coalesce(old.action,'')='build_time'
     and v_marker<>'1' then
    v_program_id:=private.progression_suggestion_source_program_v83(old.id);
    if v_program_id is not null then
      v_fresh:=private.progression_suggestion_is_fresh(old.id,v_program_id,old.client_id,old.exercise_id);
    end if;
    if v_fresh then
      new.status:=old.status;
      new.reviewed_by:=old.reviewed_by;
      new.reviewed_at:=old.reviewed_at;
      return new;
    end if;
  end if;

  if tg_op='UPDATE'
     and new.status='applied'::public.progression_status
     and old.status in ('approved'::public.progression_status,'modified'::public.progression_status) then
    return new;
  end if;

  r:=private.progression_recommendation_v83(new.source_session_id,new.exercise_id);
  v_action:=coalesce(r->>'action','collect_more_data');
  v_engine_load:=nullif(r->>'suggested_load','')::numeric;
  v_engine_rep_min:=nullif(r->>'suggested_rep_min','')::integer;
  v_engine_rep_max:=nullif(r->>'suggested_rep_max','')::integer;
  v_engine_duration:=nullif(r->>'suggested_duration_seconds','')::integer;

  if new.reviewed_by is not null
     and new.status in ('approved'::public.progression_status,'modified'::public.progression_status,'rejected'::public.progression_status)
     and v_marker<>'1' then
    raise exception 'Use review_progression_suggestion_v83 for coach decisions';
  end if;

  new.action:=v_action;
  new.engine_version:='PROGRESSION_ENGINE_V83';
  new.evidence_sessions:=coalesce((r->>'evidence_sessions')::integer,0);
  new.suggested_increment_kg:=nullif(r->>'suggested_increment_kg','')::numeric;
  new.confidence:=coalesce((r->>'confidence')::numeric,new.confidence);
  new.confidence_band:=coalesce(r->>'confidence_band','low');
  new.evidence:=r;

  if v_action in ('increase_load','build_reps','maintain','build_time') then
    if v_marker<>'1' or new.reviewed_by is null then
      new.suggested_load:=v_engine_load;
      new.suggested_rep_min:=v_engine_rep_min;
      new.suggested_rep_max:=v_engine_rep_max;
      new.suggested_duration_seconds:=v_engine_duration;
    end if;
    new.reason_code:=left(coalesce(r->>'signal',new.reason_code,v_action),120);
    new.reason_text:=left(coalesce(r->>'reason',new.reason_text,'Recomendación V83'),1000);
  elsif new.status in ('pending'::public.progression_status,'approved'::public.progression_status,'modified'::public.progression_status) then
    new.status:='rejected'::public.progression_status;
    new.reviewed_at:=coalesce(new.reviewed_at,now());
    new.reason_code:=left(coalesce(r->>'signal',new.reason_code,v_action),120);
    new.reason_text:=left(coalesce(r->>'reason',new.reason_text,'Progresión detenida por V83'),1000);
  end if;

  return new;
end;
$$;

drop trigger if exists trg_progression_suggestion_guard_v82 on public.progression_suggestions;
drop trigger if exists trg_progression_suggestion_guard_v83 on public.progression_suggestions;
create trigger trg_progression_suggestion_guard_v83
before insert or update on public.progression_suggestions
for each row execute function private.guard_progression_suggestion_v83();

create or replace function private.attach_time_progression_v83()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_client_id uuid;
  v_program_id uuid;
  v_suggestion_id uuid;
begin
  if coalesce(new.prescription_unit_snapshot,'reps')<>'seconds'
     or new.progression_suggestion_id is not null then
    return new;
  end if;

  select ws.client_id,ws.program_id into v_client_id,v_program_id
  from public.workout_sessions ws
  where ws.id=new.workout_session_id;

  select ps.id into v_suggestion_id
  from public.progression_suggestions ps
  where ps.client_id=v_client_id
    and ps.exercise_id=new.exercise_id
    and ps.action='build_time'
    and ps.status in ('approved'::public.progression_status,'modified'::public.progression_status)
    and private.progression_suggestion_is_fresh(ps.id,v_program_id,v_client_id,new.exercise_id)
  order by ps.reviewed_at desc nulls last,ps.created_at desc
  limit 1;

  if v_suggestion_id is not null then
    new.progression_suggestion_id:=v_suggestion_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_attach_time_progression_v83 on public.session_exercises;
create trigger trg_attach_time_progression_v83
before insert on public.session_exercises
for each row execute function private.attach_time_progression_v83();

create or replace function private.apply_time_progression_to_set_v83()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_unit text;
  v_suggestion_id uuid;
  v_duration integer;
begin
  select se.prescription_unit_snapshot,se.progression_suggestion_id
    into v_unit,v_suggestion_id
  from public.session_exercises se
  where se.id=new.session_exercise_id;

  if v_unit='seconds' and v_suggestion_id is not null then
    select ps.suggested_duration_seconds into v_duration
    from public.progression_suggestions ps
    where ps.id=v_suggestion_id
      and ps.action='build_time'
      and ps.status in ('approved'::public.progression_status,'modified'::public.progression_status,'applied'::public.progression_status);

    if v_duration is not null then
      new.suggested_duration_seconds:=v_duration;
      new.suggestion_source:='coach_progression';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_apply_time_progression_to_set_v83 on public.set_logs;
create trigger trg_apply_time_progression_to_set_v83
before insert on public.set_logs
for each row execute function private.apply_time_progression_to_set_v83();

create or replace function private.mark_time_progression_applied_v83()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(new.prescription_unit_snapshot,'reps')='seconds'
     and new.progression_suggestion_id is not null then
    update public.progression_suggestions
    set status='applied'::public.progression_status,updated_at=now()
    where id=new.progression_suggestion_id
      and status in ('approved'::public.progression_status,'modified'::public.progression_status);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_mark_time_progression_applied_v83 on public.session_exercises;
create trigger trg_mark_time_progression_applied_v83
after insert on public.session_exercises
for each row execute function private.mark_time_progression_applied_v83();

create or replace function public.review_progression_suggestion_v83(
  p_actor_id uuid,
  p_suggestion_id uuid,
  p_decision text,
  p_suggested_load numeric default null,
  p_suggested_rep_min integer default null,
  p_suggested_rep_max integer default null,
  p_suggested_duration_seconds integer default null,
  p_note text default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.progression_suggestions%rowtype;
  v_role public.app_role;
  r jsonb;
  v_action text;
  v_note text:=nullif(btrim(coalesce(p_note,'')),'');
  v_engine_load numeric;
  v_engine_rep_min integer;
  v_engine_rep_max integer;
  v_engine_duration integer;
  v_current_load numeric;
  v_current_duration integer;
  v_target_rep_min integer;
  v_load numeric;
  v_rep_min integer;
  v_rep_max integer;
  v_duration integer;
begin
  if (select auth.uid()) is null or (select auth.uid())<>p_actor_id then
    raise exception 'Actor authentication mismatch';
  end if;
  select role into v_role from public.profiles where id=p_actor_id and status::text='active';
  if v_role is null or v_role not in ('admin'::public.app_role,'coach'::public.app_role) then
    raise exception 'Coach/admin role required';
  end if;

  select * into s
  from public.progression_suggestions
  where id=p_suggestion_id
  for update;
  if not found then raise exception 'Progression suggestion not found'; end if;

  if v_role='coach'::public.app_role and not exists (
    select 1 from public.coach_clients cc
    where cc.coach_id=p_actor_id and cc.client_id=s.client_id
      and cc.status='active'::public.coach_client_status
  ) then
    raise exception 'Coach is not assigned to this client';
  end if;

  if p_decision not in ('approved','modified','rejected') then
    raise exception 'Unsupported progression decision';
  end if;
  if v_note is not null and char_length(v_note)>1000 then
    raise exception 'Coach note too long';
  end if;

  r:=private.progression_recommendation_v83(s.source_session_id,s.exercise_id);
  v_action:=coalesce(r->>'action','collect_more_data');
  perform pg_catalog.set_config('cv.v83_review','1',true);

  if p_decision='rejected' then
    update public.progression_suggestions
    set status='rejected'::public.progression_status,
        reviewed_by=p_actor_id,
        reviewed_at=now(),
        evidence=coalesce(evidence,'{}'::jsonb)||jsonb_build_object(
          'coach_review',jsonb_build_object('decision','rejected','note',v_note,'at',now())
        ),
        updated_at=now()
    where id=s.id;
  else
    if v_action not in ('increase_load','build_reps','build_time','maintain') then
      raise exception 'Current evidence does not allow progression approval';
    end if;

    v_engine_load:=nullif(r->>'suggested_load','')::numeric;
    v_engine_rep_min:=nullif(r->>'suggested_rep_min','')::integer;
    v_engine_rep_max:=nullif(r->>'suggested_rep_max','')::integer;
    v_engine_duration:=nullif(r->>'suggested_duration_seconds','')::integer;
    v_current_load:=nullif(r->>'current_load','')::numeric;
    v_current_duration:=coalesce(
      nullif(r->>'current_min_duration_seconds','')::integer,
      nullif(r->>'previous_duration_seconds','')::integer
    );
    v_target_rep_min:=nullif(r->>'target_rep_min','')::integer;

    if p_decision='approved' then
      v_load:=v_engine_load;
      v_rep_min:=v_engine_rep_min;
      v_rep_max:=v_engine_rep_max;
      v_duration:=v_engine_duration;
    else
      v_load:=coalesce(p_suggested_load,v_engine_load);
      v_rep_min:=coalesce(p_suggested_rep_min,v_engine_rep_min);
      v_rep_max:=coalesce(p_suggested_rep_max,v_engine_rep_max);
      v_duration:=coalesce(p_suggested_duration_seconds,v_engine_duration);

      if v_engine_load is not null then
        if v_load is null or v_load<0 or v_load>v_engine_load then
          raise exception 'Modified load exceeds V83 safe ceiling';
        end if;
        if v_action='increase_load' and v_current_load is not null and v_load<v_current_load then
          raise exception 'Modified increase-load target cannot be below current load';
        end if;
      elsif v_load is not null then
        raise exception 'Load modification is not valid for this recommendation';
      end if;

      if v_engine_rep_min is not null then
        if v_rep_min is null
           or (v_target_rep_min is not null and v_rep_min<v_target_rep_min)
           or v_rep_min>v_engine_rep_min then
          raise exception 'Modified repetition target exceeds V83 safe bounds';
        end if;
        if v_rep_max is null then v_rep_max:=v_engine_rep_max; end if;
        if v_rep_max<v_rep_min
           or (v_engine_rep_max is not null and v_rep_max>v_engine_rep_max) then
          raise exception 'Modified repetition range exceeds V83 safe bounds';
        end if;
      elsif v_rep_min is not null or v_rep_max is not null then
        raise exception 'Repetition modification is not valid for this recommendation';
      end if;

      if v_engine_duration is not null then
        if v_duration is null
           or v_duration>v_engine_duration
           or (v_current_duration is not null and v_duration<v_current_duration) then
          raise exception 'Modified duration exceeds V83 safe bounds';
        end if;
      elsif v_duration is not null then
        raise exception 'Duration modification is not valid for this recommendation';
      end if;
    end if;

    update public.progression_suggestions
    set status=case when p_decision='approved'
                    then 'approved'::public.progression_status
                    else 'modified'::public.progression_status end,
        suggested_load=v_load,
        suggested_rep_min=v_rep_min,
        suggested_rep_max=v_rep_max,
        suggested_duration_seconds=v_duration,
        action=v_action,
        engine_version='PROGRESSION_ENGINE_V83',
        confidence=coalesce((r->>'confidence')::numeric,confidence),
        confidence_band=coalesce(r->>'confidence_band',confidence_band),
        evidence_sessions=coalesce((r->>'evidence_sessions')::integer,evidence_sessions),
        suggested_increment_kg=nullif(r->>'suggested_increment_kg','')::numeric,
        reason_code=left(coalesce(r->>'signal',reason_code,v_action),120),
        reason_text=left(coalesce(r->>'reason',reason_text,'Recomendación V83'),1000),
        reviewed_by=p_actor_id,
        reviewed_at=now(),
        evidence=r||jsonb_build_object(
          'coach_review',jsonb_build_object(
            'decision',p_decision,'note',v_note,'at',now(),
            'suggested_load',v_load,
            'suggested_rep_min',v_rep_min,
            'suggested_rep_max',v_rep_max,
            'suggested_duration_seconds',v_duration
          )
        ),
        updated_at=now()
    where id=s.id;
  end if;

  select * into s from public.progression_suggestions where id=p_suggestion_id;
  return jsonb_build_object(
    'id',s.id,'client_id',s.client_id,'exercise_id',s.exercise_id,
    'status',s.status::text,'action',s.action,
    'suggested_load',s.suggested_load,
    'suggested_rep_min',s.suggested_rep_min,
    'suggested_rep_max',s.suggested_rep_max,
    'suggested_duration_seconds',s.suggested_duration_seconds,
    'reviewed_by',s.reviewed_by,'reviewed_at',s.reviewed_at,
    'engine_version',s.engine_version
  );
end;
$$;

revoke all on function public.review_progression_suggestion_v83(uuid,uuid,text,numeric,integer,integer,integer,text) from public;
grant execute on function public.review_progression_suggestion_v83(uuid,uuid,text,numeric,integer,integer,integer,text) to authenticated;

create or replace function public.review_training_adaptation_v83(
  p_actor_id uuid,
  p_review_id uuid,
  p_decision text,
  p_note text default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.training_adaptation_reviews%rowtype;
  v_role public.app_role;
  v_note text:=nullif(btrim(coalesce(p_note,'')),'');
begin
  if (select auth.uid()) is null or (select auth.uid())<>p_actor_id then
    raise exception 'Actor authentication mismatch';
  end if;
  select role into v_role from public.profiles where id=p_actor_id and status::text='active';
  if v_role is null or v_role not in ('admin'::public.app_role,'coach'::public.app_role) then
    raise exception 'Coach/admin role required';
  end if;

  select * into r from public.training_adaptation_reviews where id=p_review_id for update;
  if not found then raise exception 'Adaptation review not found'; end if;

  if v_role='coach'::public.app_role and not exists (
    select 1 from public.coach_clients cc
    where cc.coach_id=p_actor_id and cc.client_id=r.client_id
      and cc.status='active'::public.coach_client_status
  ) then
    raise exception 'Coach is not assigned to this client';
  end if;

  if p_decision not in ('reviewed','dismissed') then
    raise exception 'Unsupported adaptation decision';
  end if;
  if v_note is not null and char_length(v_note)>1000 then raise exception 'Coach note too long'; end if;

  update public.training_adaptation_reviews
  set status=p_decision,
      reviewed_by=p_actor_id,
      reviewed_at=now(),
      coach_notes=v_note,
      updated_at=now()
  where id=p_review_id
  returning * into r;

  return jsonb_build_object(
    'id',r.id,'client_id',r.client_id,'program_id',r.program_id,
    'state',r.state,'status',r.status,'reviewed_at',r.reviewed_at
  );
end;
$$;

revoke all on function public.review_training_adaptation_v83(uuid,uuid,text,text) from public;
grant execute on function public.review_training_adaptation_v83(uuid,uuid,text,text) to authenticated;

create or replace function public.get_progression_center_v83(
  p_actor_id uuid,
  p_client_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role public.app_role;
  v_suggestions jsonb;
  v_adaptations jsonb;
begin
  if (select auth.uid()) is null or (select auth.uid())<>p_actor_id then
    raise exception 'Actor authentication mismatch';
  end if;
  select role into v_role from public.profiles where id=p_actor_id and status::text='active';
  if v_role is null or v_role not in ('admin'::public.app_role,'coach'::public.app_role) then
    raise exception 'Coach/admin role required';
  end if;

  select coalesce(jsonb_agg(row_data order by created_at desc),'[]'::jsonb)
  into v_suggestions
  from (
    select ps.created_at,
      jsonb_build_object(
        'id',ps.id,
        'client_id',ps.client_id,
        'client_name',btrim(coalesce(cp.first_name,'')||' '||coalesce(cp.last_name,'')),
        'exercise_id',ps.exercise_id,
        'exercise_name',e.name,
        'prescription_unit',e.prescription_unit,
        'source_session_id',ps.source_session_id,
        'program_id',ws.program_id,
        'program_name',pr.name,
        'status',ps.status::text,
        'action',ps.action,
        'engine_version',ps.engine_version,
        'previous_load',ps.previous_load,
        'previous_reps',ps.previous_reps,
        'previous_duration_seconds',ps.previous_duration_seconds,
        'suggested_load',ps.suggested_load,
        'suggested_rep_min',ps.suggested_rep_min,
        'suggested_rep_max',ps.suggested_rep_max,
        'suggested_duration_seconds',ps.suggested_duration_seconds,
        'reason_code',ps.reason_code,
        'reason_text',ps.reason_text,
        'confidence',ps.confidence,
        'confidence_band',ps.confidence_band,
        'evidence_sessions',ps.evidence_sessions,
        'evidence',ps.evidence,
        'auto_generated',ps.auto_generated,
        'created_at',ps.created_at
      ) row_data
    from public.progression_suggestions ps
    join public.profiles cp on cp.id=ps.client_id
    join public.exercises e on e.id=ps.exercise_id
    left join public.workout_sessions ws on ws.id=ps.source_session_id
    left join public.programs pr on pr.id=ws.program_id
    where ps.status='pending'::public.progression_status
      and (p_client_id is null or ps.client_id=p_client_id)
      and (
        v_role='admin'::public.app_role
        or exists (
          select 1 from public.coach_clients cc
          where cc.coach_id=p_actor_id and cc.client_id=ps.client_id
            and cc.status='active'::public.coach_client_status
        )
      )
  ) q;

  select coalesce(jsonb_agg(row_data order by created_at desc),'[]'::jsonb)
  into v_adaptations
  from (
    select distinct on (ar.client_id,ar.program_id)
      ar.client_id,ar.program_id,ar.created_at,
      jsonb_build_object(
        'id',ar.id,
        'client_id',ar.client_id,
        'client_name',btrim(coalesce(cp.first_name,'')||' '||coalesce(cp.last_name,'')),
        'program_id',ar.program_id,
        'program_name',pr.name,
        'source_session_id',ar.source_session_id,
        'state',ar.state,
        'block_week',ar.block_week,
        'recent_sessions',ar.recent_sessions,
        'progress_signals',ar.progress_signals,
        'stagnation_signals',ar.stagnation_signals,
        'data_gap_signals',ar.data_gap_signals,
        'recovery_flags',ar.recovery_flags,
        'average_completion_pct',ar.average_completion_pct,
        'deload_recommended',ar.deload_recommended,
        'reason_codes',ar.reason_codes,
        'evidence',ar.evidence,
        'status',ar.status,
        'coach_notes',ar.coach_notes,
        'created_at',ar.created_at
      ) row_data
    from public.training_adaptation_reviews ar
    join public.profiles cp on cp.id=ar.client_id
    join public.programs pr on pr.id=ar.program_id
    where (p_client_id is null or ar.client_id=p_client_id)
      and (
        v_role='admin'::public.app_role
        or exists (
          select 1 from public.coach_clients cc
          where cc.coach_id=p_actor_id and cc.client_id=ar.client_id
            and cc.status='active'::public.coach_client_status
        )
      )
    order by ar.client_id,ar.program_id,ar.created_at desc
  ) q;

  return jsonb_build_object(
    'engine_version','ADAPTIVE_PROGRESSION_V83',
    'suggestions',v_suggestions,
    'adaptations',v_adaptations,
    'summary',jsonb_build_object(
      'pending_suggestions',jsonb_array_length(v_suggestions),
      'clients_with_adaptation_state',jsonb_array_length(v_adaptations),
      'deload_recommended',(
        select count(*)
        from jsonb_array_elements(v_adaptations) x
        where coalesce((x->>'deload_recommended')::boolean,false)
      )
    )
  );
end;
$$;

revoke all on function public.get_progression_center_v83(uuid,uuid) from public;
grant execute on function public.get_progression_center_v83(uuid,uuid) to authenticated;

update public.progression_suggestions
set updated_at=updated_at
where status='pending'::public.progression_status;

do $$
declare
  x record;
begin
  for x in
    select distinct on (ws.client_id,ws.program_id) ws.id
    from public.workout_sessions ws
    where ws.status in ('completed'::public.workout_session_status,'partial'::public.workout_session_status)
      and not private.is_cv_canary_client(ws.client_id)
    order by ws.client_id,ws.program_id,coalesce(ws.finished_at,ws.started_at) desc
  loop
    perform private.seed_training_adaptation_v83(x.id);
  end loop;
end;
$$;

comment on table public.training_adaptation_reviews is
  'V83 operational programming review: block state and deload recommendation. Never auto-edits an active program.';

commit;
