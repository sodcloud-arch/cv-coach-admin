-- CV Coach V82 — Intelligent Progression Engine
-- Double progression with deterministic load/repetition guardrails.
-- The engine recommends; it never rewrites published programming.

begin;

alter table public.progression_suggestions
  add column if not exists action text,
  add column if not exists engine_version text,
  add column if not exists evidence_sessions integer,
  add column if not exists suggested_increment_kg numeric,
  add column if not exists confidence_band text,
  add column if not exists evidence jsonb not null default '{}'::jsonb,
  add column if not exists auto_generated boolean not null default false;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.progression_suggestions'::regclass
      and conname='progression_action_v82_valid'
  ) then
    alter table public.progression_suggestions
      add constraint progression_action_v82_valid
      check (action is null or action in ('collect_more_data','maintain','build_reps','increase_load','review'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='public.progression_suggestions'::regclass
      and conname='progression_evidence_sessions_v82_valid'
  ) then
    alter table public.progression_suggestions
      add constraint progression_evidence_sessions_v82_valid
      check (evidence_sessions is null or evidence_sessions >= 0);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='public.progression_suggestions'::regclass
      and conname='progression_increment_v82_valid'
  ) then
    alter table public.progression_suggestions
      add constraint progression_increment_v82_valid
      check (suggested_increment_kg is null or suggested_increment_kg >= 0);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='public.progression_suggestions'::regclass
      and conname='progression_confidence_band_v82_valid'
  ) then
    alter table public.progression_suggestions
      add constraint progression_confidence_band_v82_valid
      check (confidence_band is null or confidence_band in ('low','medium','high'));
  end if;
end;
$$;

create or replace function private.progression_load_increment_v82(
  p_current_load numeric,
  p_equipment text
) returns numeric
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_equipment text := lower(coalesce(p_equipment,''));
  v_step numeric;
  v_cap numeric;
  v_increment numeric;
begin
  if p_current_load is null or p_current_load <= 0 then
    return null;
  end if;

  if v_equipment like '%peso corporal%'
     or v_equipment like '%caminadora%'
     or v_equipment like '%bicicleta%'
     or v_equipment like '%cuerdas de batalla%'
     or v_equipment like '%barra fija%' then
    return null;
  end if;

  if p_current_load < 10 then
    v_step := 0.50;
  elsif p_current_load < 20 then
    v_step := 1.00;
  elsif p_current_load < 40 then
    v_step := 1.50;
  else
    v_step := 2.50;
  end if;

  if v_equipment like '%mancuerna%' then
    v_step := least(v_step, 2.00);
  end if;

  v_cap := case
    when p_current_load < 10 then 0.50
    else greatest(0.50, p_current_load * 0.05)
  end;

  v_increment := least(v_step, v_cap);
  v_increment := round(v_increment * 2) / 2.0;

  if v_increment <= 0 then
    return null;
  end if;
  return v_increment;
end;
$$;

comment on function private.progression_load_increment_v82(numeric,text) is
  'V82 conservative next-load increment: equipment-aware micro-progression with a 5% ceiling for normal loads.';

create or replace function private.progression_recommendation_v82(
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
  p private.training_session_exercise_metrics%rowtype;
  ws public.workout_sessions%rowtype;
  e public.exercises%rowtype;
  rc record;
  v_signal text;
  v_action text := 'collect_more_data';
  v_evidence integer := 0;
  v_conf numeric := 0;
  v_band text;
  v_increment numeric := null;
  v_suggested_load numeric := null;
  v_rep_min integer := null;
  v_rep_max integer := null;
  v_target_reps integer := null;
  v_reason text := 'Se requieren más datos antes de cambiar la progresión.';
  v_previous_volume numeric := null;
  v_volume_delta_pct numeric := null;
begin
  select * into ws from public.workout_sessions where id=p_session_id;
  if not found then
    return jsonb_build_object(
      'engine_version','PROGRESSION_ENGINE_V82',
      'action','collect_more_data',
      'signal','no_session',
      'confidence',0,
      'confidence_band','low',
      'reason','Sesión no encontrada.'
    );
  end if;

  select * into c
  from private.training_session_exercise_metrics
  where session_id=p_session_id and exercise_id=p_exercise_id;

  if not found then
    return jsonb_build_object(
      'engine_version','PROGRESSION_ENGINE_V82',
      'action','collect_more_data',
      'signal','no_exercise_data',
      'confidence',0,
      'confidence_band','low',
      'reason','No hay datos ejecutados para este ejercicio.'
    );
  end if;

  select * into e from public.exercises where id=p_exercise_id;
  v_signal := private.deterministic_progression_signal(p_session_id,p_exercise_id);

  select count(*)::integer into v_evidence
  from private.training_session_exercise_metrics m
  where m.client_id=c.client_id
    and m.exercise_id=c.exercise_id
    and m.workout_status in ('completed','partial')
    and m.done_sets>0
    and coalesce(m.finished_at,m.started_at)<=coalesce(c.finished_at,c.started_at);

  select * into p
  from private.training_session_exercise_metrics m
  where m.client_id=c.client_id
    and m.exercise_id=c.exercise_id
    and m.session_id<>c.session_id
    and m.workout_status in ('completed','partial')
    and m.done_sets>0
    and coalesce(m.finished_at,m.started_at)<coalesce(c.finished_at,c.started_at)
  order by coalesce(m.finished_at,m.started_at) desc,m.started_at desc
  limit 1;

  if p.session_id is not null then
    v_previous_volume := p.volume;
    if coalesce(p.volume,0)>0 and c.volume is not null then
      v_volume_delta_pct := round(((c.volume-p.volume)/p.volume)*100,2);
    end if;
  end if;

  if coalesce(c.prescription_unit,'reps') <> 'reps' then
    v_action := 'collect_more_data';
    v_signal := 'time_based_progression_not_enabled';
    v_reason := 'V82 mantiene los ejercicios por tiempo sin progresión automática de carga.';
  else
    case v_signal
      when 'eligible_load_increase' then
        v_increment := private.progression_load_increment_v82(c.max_weight,e.equipment);
        if v_increment is not null then
          v_action := 'increase_load';
          v_suggested_load := c.max_weight + v_increment;
          v_rep_min := c.rep_min;
          v_rep_max := c.rep_max;
          v_reason := 'Completó dos exposiciones válidas en el techo de repeticiones, con carga estable y esfuerzo compatible. Subir una microcarga y volver al inicio del rango.';
        else
          v_action := 'maintain';
          v_suggested_load := c.max_weight;
          v_rep_min := c.rep_min;
          v_rep_max := c.rep_max;
          v_reason := 'El ejercicio alcanzó el techo del rango, pero no existe una microcarga determinista fiable para este equipamiento. Mantener y revisar manualmente.';
        end if;

      when 'maintain_load_build_reps' then
        v_action := 'build_reps';
        v_suggested_load := c.max_weight;
        v_target_reps := least(
          coalesce(c.rep_max,100),
          greatest(
            coalesce(c.rep_min,1),
            floor(coalesce(c.avg_reps,c.max_reps,c.rep_min,1))::integer + 1
          )
        );
        v_rep_min := v_target_reps;
        v_rep_max := c.rep_max;
        v_reason := 'Mantener la carga y sumar una repetición objetivo antes de considerar más peso.';

      when 'hold_collect_evidence' then
        v_action := 'maintain';
        v_suggested_load := c.max_weight;
        v_rep_min := c.rep_min;
        v_rep_max := c.rep_max;
        v_reason := 'El techo del rango se logró, pero todavía falta repetir la evidencia con la misma carga antes de progresar.';

      when 'hold_missing_rir' then
        v_action := 'collect_more_data';
        v_reason := 'Falta RIR suficiente para validar una subida de carga. Mantener condiciones y registrar esfuerzo.';

      when 'below_rep_range_review' then
        v_action := 'review';
        v_reason := 'Las repeticiones quedaron por debajo del rango prescrito. Revisar carga, técnica y fatiga antes de progresar.';

      when 'partial_session' then
        v_action := 'review';
        v_reason := 'La sesión o el ejercicio quedó incompleto. No progresar hasta revisar adherencia, interrupciones o fatiga.';

      when 'review_variable_load' then
        v_action := 'review';
        v_reason := 'La carga varió entre series. Requiere estabilizar la ejecución antes de progresar.';

      when 'hold_high_effort' then
        v_action := 'review';
        v_reason := 'El RIR fue más exigente que el objetivo. Mantener o revisar antes de aumentar carga.';

      when 'hold_pain_feedback' then
        v_action := 'review';
        v_reason := 'Hubo dolor relevante en la sesión. La progresión queda detenida para revisión del coach.';

      when 'hold_high_fatigue' then
        v_action := 'review';
        v_reason := 'La fatiga global fue alta. Revisar recuperación antes de progresar.';

      when 'hold_high_session_effort' then
        v_action := 'review';
        v_reason := 'El esfuerzo global fue alto. Revisar recuperación antes de progresar.';

      when 'hold_weekly_pain' then
        v_action := 'review';
        v_reason := 'El check-in semanal registra dolor relevante. No progresar hasta revisión.';

      when 'hold_low_recovery' then
        v_action := 'review';
        v_reason := 'La recuperación semanal es insuficiente para justificar una progresión.';

      when 'hold_high_stress' then
        v_action := 'review';
        v_reason := 'Estrés alto y energía baja: mantener la carga de trabajo y revisar recuperación.';

      when 'collect_more_data' then
        v_action := 'collect_more_data';
        v_reason := 'La ejecución fue válida, pero todavía no hay evidencia suficiente para cambiar el objetivo.';

      when 'no_data' then
        v_action := 'collect_more_data';
        v_reason := 'No hay datos suficientes para recomendar una progresión.';

      else
        v_action := 'review';
        v_reason := 'Señal de progresión no reconocida. Se exige revisión conservadora.';
    end case;
  end if;

  v_conf := 40 + least(v_evidence,4)*8;
  if c.avg_rir is not null then v_conf := v_conf + 10; end if;
  if coalesce(c.all_sets_completed,false) then v_conf := v_conf + 8; end if;
  if coalesce(c.load_stable,false) then v_conf := v_conf + 8; end if;
  if c.target_sets is not null and c.done_sets>=c.target_sets then v_conf := v_conf + 6; end if;
  if v_action='increase_load' and p.session_id is not null then v_conf := v_conf + 8; end if;

  if v_action='collect_more_data' then v_conf := least(v_conf,64); end if;
  if v_action='review' then v_conf := greatest(v_conf,85); end if;
  v_conf := greatest(0,least(100,round(v_conf,2)));

  v_band := case when v_conf>=85 then 'high' when v_conf>=65 then 'medium' else 'low' end;

  select * into rc
  from private.latest_weekly_recovery_context(ws.client_id,coalesce(ws.finished_at,ws.started_at));

  return jsonb_build_object(
    'engine_version','PROGRESSION_ENGINE_V82',
    'session_id',p_session_id,
    'exercise_id',p_exercise_id,
    'exercise_name',c.exercise_name,
    'equipment',e.equipment,
    'prescription_unit',c.prescription_unit,
    'signal',v_signal,
    'action',v_action,
    'reason',v_reason,
    'confidence',v_conf,
    'confidence_band',v_band,
    'evidence_sessions',v_evidence,
    'current_load',c.max_weight,
    'current_min_reps',c.min_reps,
    'current_max_reps',c.max_reps,
    'current_avg_reps',c.avg_reps,
    'current_avg_rir',c.avg_rir,
    'target_rep_min',c.rep_min,
    'target_rep_max',c.rep_max,
    'suggested_load',v_suggested_load,
    'suggested_increment_kg',v_increment,
    'suggested_rep_min',v_rep_min,
    'suggested_rep_max',v_rep_max,
    'previous_session_id',p.session_id,
    'previous_load',p.max_weight,
    'previous_max_reps',p.max_reps,
    'previous_avg_rir',p.avg_rir,
    'previous_volume',v_previous_volume,
    'volume_delta_pct',v_volume_delta_pct,
    'session_feedback',jsonb_build_object(
      'difficulty_level',ws.difficulty_level,
      'client_effort',ws.client_effort,
      'fatigue_score',ws.fatigue_score,
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
    'rule','Double progression V82: build reps first; increase load only after repeated top-range evidence, stable load, compatible RIR and acceptable recovery.'
  );
end;
$$;

comment on function private.progression_recommendation_v82(uuid,uuid) is
  'V82 deterministic progression memory and recommendation. Read-only; never modifies a published program.';

create or replace function private.guard_progression_suggestion_v82()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  r jsonb;
  v_action text;
  v_engine_load numeric;
  v_engine_rep_min integer;
  v_engine_rep_max integer;
begin
  if new.source_session_id is null or new.exercise_id is null then
    return new;
  end if;

  if new.reviewed_by is not null then
    return new;
  end if;

  r := private.progression_recommendation_v82(new.source_session_id,new.exercise_id);
  v_action := coalesce(r->>'action','collect_more_data');
  v_engine_load := nullif(r->>'suggested_load','')::numeric;
  v_engine_rep_min := nullif(r->>'suggested_rep_min','')::integer;
  v_engine_rep_max := nullif(r->>'suggested_rep_max','')::integer;

  new.action := v_action;
  new.engine_version := coalesce(r->>'engine_version','PROGRESSION_ENGINE_V82');
  new.evidence_sessions := coalesce((r->>'evidence_sessions')::integer,0);
  new.suggested_increment_kg := nullif(r->>'suggested_increment_kg','')::numeric;
  new.confidence := coalesce((r->>'confidence')::numeric,new.confidence);
  new.confidence_band := coalesce(r->>'confidence_band','low');
  new.evidence := r;
  new.auto_generated := coalesce(new.auto_generated,false);

  if v_action in ('increase_load','build_reps','maintain') then
    new.suggested_load := v_engine_load;
    new.suggested_rep_min := v_engine_rep_min;
    new.suggested_rep_max := v_engine_rep_max;
    new.reason_code := left(coalesce(r->>'signal',new.reason_code,v_action),120);
    new.reason_text := left(coalesce(r->>'reason',new.reason_text,'Recomendación V82'),1000);
  elsif new.status in ('pending'::public.progression_status,'approved'::public.progression_status,'modified'::public.progression_status) then
    new.status := 'rejected'::public.progression_status;
    new.reviewed_at := coalesce(new.reviewed_at,now());
    new.reason_code := left(coalesce(r->>'signal',new.reason_code,v_action),120);
    new.reason_text := left(coalesce(r->>'reason',new.reason_text,'Progresión detenida por V82'),1000);
  end if;

  return new;
end;
$$;

drop trigger if exists trg_progression_suggestion_guard_v82 on public.progression_suggestions;
create trigger trg_progression_suggestion_guard_v82
before insert or update on public.progression_suggestions
for each row execute function private.guard_progression_suggestion_v82();

comment on function private.guard_progression_suggestion_v82() is
  'V82 hard guardrail: system-generated suggestions are normalized to the deterministic recommendation; unsafe progressions are rejected.';

create or replace function private.seed_progression_suggestions_v82(p_session_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  ws public.workout_sessions%rowtype;
  m record;
  r jsonb;
  v_action text;
  v_id uuid;
  v_created integer := 0;
  v_review integer := 0;
  v_skipped integer := 0;
begin
  select * into ws from public.workout_sessions where id=p_session_id;
  if not found then return jsonb_build_object('status','skipped','reason','session_not_found'); end if;
  if ws.status not in ('completed'::public.workout_session_status,'partial'::public.workout_session_status) then
    return jsonb_build_object('status','skipped','reason','session_not_completed_or_partial');
  end if;
  if private.is_cv_canary_client(ws.client_id) then
    return jsonb_build_object('status','skipped','reason','canary_client');
  end if;

  for m in
    select *
    from private.training_session_exercise_metrics
    where session_id=p_session_id
      and coalesce(prescription_unit,'reps')='reps'
      and done_sets>0
    order by exercise_name
  loop
    r := private.progression_recommendation_v82(p_session_id,m.exercise_id);
    v_action := coalesce(r->>'action','collect_more_data');

    if v_action in ('increase_load','build_reps') then
      v_id := null;
      insert into public.progression_suggestions(
        client_id,exercise_id,source_session_id,
        previous_load,previous_reps,
        suggested_load,suggested_rep_min,suggested_rep_max,
        reason_code,reason_text,confidence,status,
        action,engine_version,evidence_sessions,suggested_increment_kg,
        confidence_band,evidence,auto_generated
      ) values (
        ws.client_id,m.exercise_id,p_session_id,
        m.max_weight,m.max_reps,
        nullif(r->>'suggested_load','')::numeric,
        nullif(r->>'suggested_rep_min','')::integer,
        nullif(r->>'suggested_rep_max','')::integer,
        left(coalesce(r->>'signal',v_action),120),
        left(coalesce(r->>'reason','Recomendación V82'),1000),
        coalesce((r->>'confidence')::numeric,0),
        'pending'::public.progression_status,
        v_action,
        coalesce(r->>'engine_version','PROGRESSION_ENGINE_V82'),
        coalesce((r->>'evidence_sessions')::integer,0),
        nullif(r->>'suggested_increment_kg','')::numeric,
        coalesce(r->>'confidence_band','low'),
        r,
        true
      )
      on conflict(source_session_id,exercise_id) do update
      set previous_load=excluded.previous_load,
          previous_reps=excluded.previous_reps,
          suggested_load=excluded.suggested_load,
          suggested_rep_min=excluded.suggested_rep_min,
          suggested_rep_max=excluded.suggested_rep_max,
          reason_code=excluded.reason_code,
          reason_text=excluded.reason_text,
          confidence=excluded.confidence,
          action=excluded.action,
          engine_version=excluded.engine_version,
          evidence_sessions=excluded.evidence_sessions,
          suggested_increment_kg=excluded.suggested_increment_kg,
          confidence_band=excluded.confidence_band,
          evidence=excluded.evidence,
          auto_generated=true,
          updated_at=now()
      where public.progression_suggestions.status='pending'::public.progression_status
      returning id into v_id;

      if v_id is not null then v_created := v_created + 1; else v_skipped := v_skipped + 1; end if;
    elsif v_action='review' then
      v_review := v_review + 1;
    else
      v_skipped := v_skipped + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'status','ok',
    'engine_version','PROGRESSION_ENGINE_V82',
    'session_id',p_session_id,
    'suggestions_created_or_refreshed',v_created,
    'review_signals',v_review,
    'no_change_or_more_data',v_skipped
  );
end;
$$;

comment on function private.seed_progression_suggestions_v82(uuid) is
  'V82 creates pending next-session progression suggestions immediately after a valid completed/partial workout.';

create or replace function private.progression_seed_trigger_v82()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status='in_progress'::public.workout_session_status
     and new.status in ('completed'::public.workout_session_status,'partial'::public.workout_session_status) then
    perform private.seed_progression_suggestions_v82(new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_workout_progression_seed_v82 on public.workout_sessions;
create trigger trg_workout_progression_seed_v82
after update of status on public.workout_sessions
for each row
when (old.status is distinct from new.status)
execute function private.progression_seed_trigger_v82();

comment on function private.progression_seed_trigger_v82() is
  'V82 event hook: generates deterministic pending progression suggestions after terminal workout completion.';

update public.progression_suggestions
set updated_at=updated_at
where status='pending'::public.progression_status
  and source_session_id is not null;

do $$
begin
  if exists (
    select 1
    from public.progression_suggestions ps
    where ps.status='pending'::public.progression_status
      and ps.source_session_id is not null
      and (
        ps.engine_version is distinct from 'PROGRESSION_ENGINE_V82'
        or ps.action is null
        or ps.evidence_sessions is null
        or ps.confidence_band is null
      )
  ) then
    raise exception 'V82 invariant failed: pending suggestion lacks deterministic metadata';
  end if;

  if exists (
    select 1
    from public.progression_suggestions ps
    where ps.status in ('pending'::public.progression_status,'approved'::public.progression_status,'modified'::public.progression_status)
      and ps.action='increase_load'
      and (
        ps.previous_load is null
        or ps.suggested_load is null
        or ps.suggested_load<=ps.previous_load
        or ps.suggested_increment_kg is null
      )
  ) then
    raise exception 'V82 invariant failed: active increase_load suggestion is inconsistent';
  end if;
end;
$$;

commit;
