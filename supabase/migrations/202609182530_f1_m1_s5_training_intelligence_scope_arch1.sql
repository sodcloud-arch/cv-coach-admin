-- ARCH-1.0 · F1.M1.S5 Wave G1B3A — Training intelligence tenant scope
-- Session/Program identifiers anchor every historical comparison to one Organization.

CREATE OR REPLACE FUNCTION private.deterministic_progression_signal(p_session_id uuid, p_exercise_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  c private.training_session_exercise_metrics%rowtype;
  p private.training_session_exercise_metrics%rowtype;
  s private.training_engine_settings%rowtype;
  ws public.workout_sessions%rowtype;
  rc record;
  v_evidence integer:=0;
begin
  select * into s from private.training_engine_settings where active=true order by created_at desc limit 1;
  if not found then raise exception 'training engine settings missing'; end if;
  select * into ws from public.workout_sessions where id=p_session_id;
  if not found then return 'no_data'; end if;
  select * into c from private.training_session_exercise_metrics where session_id=p_session_id and exercise_id=p_exercise_id;
  if not found then return 'no_data'; end if;

  if ws.pain_score is not null and ws.pain_score>=4 then return 'hold_pain_feedback'; end if;
  if ws.fatigue_score is not null and ws.fatigue_score>=8 then return 'hold_high_fatigue'; end if;
  if ws.client_effort is not null and ws.client_effort>=9 then return 'hold_high_session_effort'; end if;

  select * into rc from private.latest_weekly_recovery_context_in_org(ws.organization_id,ws.client_id,coalesce(ws.finished_at,ws.started_at));
  if rc.checkin_id is not null then
    if coalesce(rc.pain_score,0)>=4 then return 'hold_weekly_pain'; end if;
    if coalesce(rc.sleep_hours_avg,99)<5 and coalesce(rc.energy_level,5)<=2 then return 'hold_low_recovery'; end if;
    if coalesce(rc.stress_level,1)>=5 and coalesce(rc.energy_level,5)<=2 then return 'hold_high_stress'; end if;
    if coalesce(rc.soreness_score,0)>=8 and coalesce(rc.energy_level,5)<=2 then return 'hold_low_recovery'; end if;
  end if;

  select count(*)::integer into v_evidence
  from private.training_session_exercise_metrics m
  where m.client_id=c.client_id and m.exercise_id=c.exercise_id
    and exists(select 1 from public.workout_sessions wh where wh.id=m.session_id and wh.organization_id=ws.organization_id)
    and m.workout_status in ('completed','partial') and m.done_sets>0
    and coalesce(m.finished_at,m.started_at)<=coalesce(c.finished_at,c.started_at);

  select * into p
  from private.training_session_exercise_metrics m
  where m.client_id=c.client_id and m.exercise_id=c.exercise_id
    and exists(select 1 from public.workout_sessions wh where wh.id=m.session_id and wh.organization_id=ws.organization_id) and m.session_id<>c.session_id
    and m.workout_status in ('completed','partial') and m.done_sets>0
    and coalesce(m.finished_at,m.started_at)<coalesce(c.finished_at,c.started_at)
  order by coalesce(m.finished_at,m.started_at) desc limit 1;

  if c.done_sets=0 then return 'no_data'; end if;
  if c.done_sets<c.target_sets then return 'partial_session'; end if;
  if c.rep_min is not null and c.min_reps<c.rep_min then return 'below_rep_range_review'; end if;
  if not c.load_stable then return 'review_variable_load'; end if;

  if c.all_at_rep_max then
    if v_evidence<s.minimum_sessions_for_load_increase then return 'hold_collect_evidence'; end if;
    if c.max_weight is null then return 'collect_more_data'; end if;
    if s.require_rir_for_load_increase and c.avg_rir is null then return 'hold_missing_rir'; end if;
    if s.require_rir_for_load_increase and c.rir_target is not null and c.avg_rir < (c.rir_target-s.rir_tolerance) then return 'hold_high_effort'; end if;
    if p.session_id is null then return 'hold_collect_evidence'; end if;
    if not p.all_sets_completed or not p.all_at_rep_max or not p.load_stable then return 'hold_collect_evidence'; end if;
    if p.max_weight is distinct from c.max_weight then return 'hold_collect_evidence'; end if;
    if s.require_rir_for_load_increase and p.avg_rir is null then return 'hold_missing_rir'; end if;
    if s.require_rir_for_load_increase and p.rir_target is not null and p.avg_rir < (p.rir_target-s.rir_tolerance) then return 'hold_high_effort'; end if;
    return 'eligible_load_increase';
  end if;

  if c.all_sets_completed
     and c.rep_min is not null
     and c.rep_max is not null
     and c.min_reps>=c.rep_min
     and c.max_reps<c.rep_max then
    if s.require_rir_for_load_increase and c.avg_rir is null then return 'hold_missing_rir'; end if;
    if s.require_rir_for_load_increase and c.rir_target is not null and c.avg_rir < (c.rir_target-s.rir_tolerance) then return 'hold_high_effort'; end if;
    return 'maintain_load_build_reps';
  end if;

  return 'collect_more_data';
end;
$function$;

CREATE OR REPLACE FUNCTION private.progression_recommendation_v82(p_session_id uuid, p_exercise_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    and exists(select 1 from public.workout_sessions wh where wh.id=m.session_id and wh.organization_id=ws.organization_id)
    and m.workout_status in ('completed','partial')
    and m.done_sets>0
    and coalesce(m.finished_at,m.started_at)<=coalesce(c.finished_at,c.started_at);

  select * into p
  from private.training_session_exercise_metrics m
  where m.client_id=c.client_id
    and m.exercise_id=c.exercise_id
    and exists(select 1 from public.workout_sessions wh where wh.id=m.session_id and wh.organization_id=ws.organization_id)
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
  from private.latest_weekly_recovery_context_in_org(ws.organization_id,ws.client_id,coalesce(ws.finished_at,ws.started_at));

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
$function$;

CREATE OR REPLACE FUNCTION private.progression_recommendation_v83(p_session_id uuid, p_exercise_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    and exists(select 1 from public.workout_sessions wh where wh.id=m.session_id and wh.organization_id=ws.organization_id)
    and m.prescription_unit='seconds'
    and m.workout_status in ('completed','partial')
    and m.done_sets>0
    and coalesce(m.finished_at,m.started_at)<=coalesce(c.finished_at,c.started_at);

  select * into rc
  from private.latest_weekly_recovery_context_in_org(ws.organization_id,ws.client_id,coalesce(ws.finished_at,ws.started_at));

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
$function$;

CREATE OR REPLACE FUNCTION private.compute_training_adaptation_in_org_v83(p_organization_id uuid, p_client_id uuid, p_program_id uuid, p_as_of timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  where id=p_program_id and organization_id=p_organization_id and client_id=p_client_id;

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
    where ws.organization_id=p_organization_id
      and ws.client_id=p_client_id
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
  from private.latest_weekly_recovery_context_in_org(p_organization_id,p_client_id,p_as_of);

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
    'organization_id',p_organization_id,
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
$function$;

create or replace function private.compute_training_adaptation_v83(
  p_client_id uuid,
  p_program_id uuid,
  p_as_of timestamp with time zone default now()
)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_organization uuid;
begin
  select p.organization_id into v_organization
  from public.programs p
  where p.id=p_program_id
    and p.client_id=p_client_id;

  if v_organization is null then
    return jsonb_build_object(
      'engine_version','ADAPTATION_ENGINE_V83',
      'state','stable',
      'recent_sessions',0,
      'deload_recommended',false,
      'reason_codes',jsonb_build_array('program_not_found')
    );
  end if;

  return private.compute_training_adaptation_in_org_v83(
    v_organization,p_client_id,p_program_id,p_as_of
  );
end;
$function$;

CREATE OR REPLACE FUNCTION private.compute_mesocycle_intelligence_in_org_v85(p_organization_id uuid, p_client_id uuid, p_target_program_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  target_program public.programs%rowtype;
  source_program public.programs%rowtype;
  previous_program public.programs%rowtype;
  v_source_id uuid;
  v_previous_id uuid;
  v_adaptation jsonb;
  v_current_summary jsonb;
  v_previous_summary jsonb;
  v_effectiveness jsonb;
  v_progressions jsonb;
  v_memory_quality text;
begin
  select * into target_program from public.programs where id=p_target_program_id and organization_id=p_organization_id and client_id=p_client_id;
  if not found then
    return jsonb_build_object('engine_version','MESOCYCLE_INTELLIGENCE_V85','available',false,'reason','target_program_not_found');
  end if;

  select apd.source_program_id into v_source_id
  from public.adaptive_program_drafts apd
  where apd.organization_id=p_organization_id and apd.draft_program_id=target_program.id
  order by apd.created_at desc limit 1;

  if v_source_id is null and target_program.status='draft'::public.program_status then
    select p.id into v_source_id
    from public.programs p
    where p.organization_id=p_organization_id and p.client_id=p_client_id and p.status='active'::public.program_status
    order by p.version desc nulls last,p.updated_at desc limit 1;
  end if;
  v_source_id:=coalesce(v_source_id,target_program.id);

  select * into source_program from public.programs where id=v_source_id;
  if not found then
    return jsonb_build_object('engine_version','MESOCYCLE_INTELLIGENCE_V85','available',false,'reason','source_program_not_found');
  end if;

  select p.* into previous_program
  from public.programs p
  where p.organization_id=p_organization_id and p.client_id=p_client_id and p.id<>source_program.id
    and coalesce(p.version,0)<coalesce(source_program.version,2147483647)
    and exists(select 1 from public.workout_sessions ws where ws.program_id=p.id and ws.client_id=p_client_id and ws.status in ('completed'::public.workout_session_status,'partial'::public.workout_session_status))
  order by p.version desc nulls last,p.updated_at desc limit 1;
  v_previous_id:=previous_program.id;

  v_adaptation:=private.compute_training_adaptation_in_org_v83(p_organization_id,p_client_id,source_program.id,now());

  select jsonb_build_object(
    'program_id',source_program.id,'version',source_program.version,
    'sessions',count(*),
    'average_completion_pct',round(avg(ws.completion_pct),1),
    'average_volume',round(avg(ws.total_volume),1),
    'total_volume',round(coalesce(sum(ws.total_volume),0),1),
    'average_effort',round(avg(ws.client_effort),1),
    'pain_sessions',count(*) filter(where coalesce(ws.had_pain,false) or coalesce(ws.pain_score,0)>=4),
    'completed_sessions',count(*) filter(where ws.status='completed'::public.workout_session_status),
    'first_session_at',min(ws.started_at),'last_session_at',max(coalesce(ws.finished_at,ws.started_at))
  ) into v_current_summary
  from public.workout_sessions ws
  where ws.organization_id=p_organization_id and ws.client_id=p_client_id and ws.program_id=source_program.id
    and ws.status in ('completed'::public.workout_session_status,'partial'::public.workout_session_status);

  if v_previous_id is not null then
    select jsonb_build_object(
      'program_id',previous_program.id,'version',previous_program.version,
      'sessions',count(*),
      'average_completion_pct',round(avg(ws.completion_pct),1),
      'average_volume',round(avg(ws.total_volume),1),
      'total_volume',round(coalesce(sum(ws.total_volume),0),1),
      'average_effort',round(avg(ws.client_effort),1),
      'pain_sessions',count(*) filter(where coalesce(ws.had_pain,false) or coalesce(ws.pain_score,0)>=4),
      'completed_sessions',count(*) filter(where ws.status='completed'::public.workout_session_status),
      'first_session_at',min(ws.started_at),'last_session_at',max(coalesce(ws.finished_at,ws.started_at))
    ) into v_previous_summary
    from public.workout_sessions ws
    where ws.organization_id=p_organization_id and ws.client_id=p_client_id and ws.program_id=previous_program.id
      and ws.status in ('completed'::public.workout_session_status,'partial'::public.workout_session_status);
  else
    v_previous_summary:='{}'::jsonb;
  end if;

  with m as (
    select tm.*
    from private.training_session_exercise_metrics tm
    join public.workout_sessions ws on ws.id=tm.session_id
    where tm.client_id=p_client_id and ws.organization_id=p_organization_id and ws.program_id=source_program.id
      and tm.done_sets>0 and tm.workout_status in ('completed','partial')
  ), firsts as (
    select distinct on (exercise_id) exercise_id,max_weight,avg_reps,avg_duration_seconds,avg_rir,volume,coalesce(finished_at,started_at) at
    from m order by exercise_id,coalesce(finished_at,started_at) asc
  ), lasts as (
    select distinct on (exercise_id) exercise_id,max_weight,avg_reps,avg_duration_seconds,avg_rir,volume,coalesce(finished_at,started_at) at
    from m order by exercise_id,coalesce(finished_at,started_at) desc
  ), agg as (
    select exercise_id,max(exercise_name) exercise_name,max(prescription_unit) prescription_unit,
      count(*)::integer exposures,max(volume) peak_volume
    from m group by exercise_id
  ), classified as (
    select a.*,f.max_weight first_load,l.max_weight latest_load,
      f.avg_reps first_reps,l.avg_reps latest_reps,
      f.avg_duration_seconds first_duration,l.avg_duration_seconds latest_duration,
      l.avg_rir latest_rir,l.volume latest_volume,
      case
        when a.exposures<2 then 'insufficient_data'
        when a.prescription_unit='seconds' and coalesce(l.avg_duration_seconds,0)>=coalesce(f.avg_duration_seconds,0)+3 then 'progressing'
        when a.prescription_unit='reps' and (
          coalesce(l.max_weight,0)>coalesce(f.max_weight,0)+0.001
          or coalesce(l.avg_reps,0)>=coalesce(f.avg_reps,0)+1
        ) then 'progressing'
        when a.exposures>=3 then 'stalled'
        else 'stable'
      end as trend
    from agg a join firsts f using(exercise_id) join lasts l using(exercise_id)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'exercise_id',c.exercise_id,'exercise_name',c.exercise_name,'prescription_unit',c.prescription_unit,
    'exposures',c.exposures,'trend',c.trend,'first_load',c.first_load,'latest_load',c.latest_load,
    'first_avg_reps',c.first_reps,'latest_avg_reps',c.latest_reps,
    'first_avg_duration_seconds',c.first_duration,'latest_avg_duration_seconds',c.latest_duration,
    'latest_avg_rir',c.latest_rir,'latest_volume',c.latest_volume,'peak_volume',c.peak_volume
  ) order by case c.trend when 'progressing' then 1 when 'stable' then 2 when 'stalled' then 3 else 4 end,c.exposures desc),'[]'::jsonb)
  into v_effectiveness from classified c;

  select jsonb_build_object(
    'applied',count(*) filter(where ps.status='applied'::public.progression_status),
    'approved_or_modified',count(*) filter(where ps.status in ('approved'::public.progression_status,'modified'::public.progression_status)),
    'rejected',count(*) filter(where ps.status='rejected'::public.progression_status),
    'pending',count(*) filter(where ps.status='pending'::public.progression_status)
  ) into v_progressions
  from public.progression_suggestions ps
  left join public.workout_sessions ws on ws.id=ps.source_session_id
  where ps.organization_id=p_organization_id and ps.client_id=p_client_id and (ws.program_id=source_program.id or ws.id is null)
    and ps.created_at>=coalesce(source_program.published_at,source_program.created_at,now()-interval '16 weeks');

  v_memory_quality:=case
    when coalesce((v_current_summary->>'sessions')::integer,0)>=6 then 'high'
    when coalesce((v_current_summary->>'sessions')::integer,0)>=3 then 'medium'
    else 'low'
  end;

  return jsonb_build_object(
    'engine_version','MESOCYCLE_INTELLIGENCE_V85','available',true,'organization_id',p_organization_id,'client_id',p_client_id,
    'target_program_id',target_program.id,'source_program_id',source_program.id,'source_program_version',source_program.version,
    'previous_program_id',v_previous_id,'previous_program_version',previous_program.version,
    'memory_quality',v_memory_quality,
    'block_state',coalesce(v_adaptation,'{}'::jsonb),
    'block_comparison',jsonb_build_object('current',coalesce(v_current_summary,'{}'::jsonb),'previous',coalesce(v_previous_summary,'{}'::jsonb)),
    'exercise_effectiveness',coalesce(v_effectiveness,'[]'::jsonb),
    'progression_summary',coalesce(v_progressions,'{}'::jsonb),
    'guardrails',jsonb_build_object(
      'memory_is_evidence_not_instruction',true,'coach_review_required',true,'auto_publish',false,
      'preserve_productive_patterns',true,'single_peak_is_not_progress',true,
      'do_not_auto_increase_volume_when_recovery_limited',true
    )
  );
end;
$function$;

create or replace function private.compute_mesocycle_intelligence_v85(
  p_client_id uuid,
  p_target_program_id uuid
)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_organization uuid;
begin
  select p.organization_id into v_organization
  from public.programs p
  where p.id=p_target_program_id
    and p.client_id=p_client_id;

  if v_organization is null then
    return jsonb_build_object(
      'engine_version','MESOCYCLE_INTELLIGENCE_V85',
      'available',false,
      'reason','target_program_not_found'
    );
  end if;

  return private.compute_mesocycle_intelligence_in_org_v85(
    v_organization,p_client_id,p_target_program_id
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_mesocycle_intelligence_v85(p_actor_id uuid, p_client_id uuid, p_program_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_role public.app_role;
  v_organization uuid;
  v_request_role text:=coalesce(auth.role(),'');
begin
  if v_request_role<>'service_role' and (auth.uid() is null or auth.uid()<>p_actor_id) then raise exception 'Actor authentication mismatch'; end if;
  select role into v_role from public.profiles where id=p_actor_id and status='active'::public.profile_status;
  if v_role is null or v_role not in ('admin'::public.app_role,'coach'::public.app_role) then raise exception 'Coach/admin role required'; end if;
  select organization_id into v_organization
  from public.programs
  where id=p_program_id and client_id=p_client_id;
  if v_organization is null then raise exception 'Program not found'; end if;
  if v_request_role<>'service_role'
     and not private.actor_can_manage_client_in_org_v1(
       p_actor_id,v_organization,p_client_id
     ) then
    raise exception 'Coach/admin is not authorized for this client in organization';
  end if;
  return private.compute_mesocycle_intelligence_in_org_v85(v_organization,p_client_id,p_program_id);
end;
$function$;

comment on function private.compute_training_adaptation_in_org_v83(uuid,uuid,uuid,timestamp with time zone) is
  'F1.M1.S5 G1B3A tenant-explicit adaptation engine.';
comment on function private.compute_mesocycle_intelligence_in_org_v85(uuid,uuid,uuid) is
  'F1.M1.S5 G1B3A tenant-explicit mesocycle intelligence.';
