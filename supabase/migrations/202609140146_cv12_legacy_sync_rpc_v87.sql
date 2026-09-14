-- CV Coach V87 — idempotent CV12 ingestion RPC

create or replace function public.sync_cv12_legacy_v87(
  p_pilot_id uuid,
  p_sessions jsonb,
  p_exercise_logs jsonb,
  p_measurements jsonb default '[]'::jsonb,
  p_source_revision text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  x jsonb;
  v_session_count integer := 0;
  v_log_count integer := 0;
  v_measure_count integer := 0;
  v_alias public.legacy_cv12_exercise_aliases_v87%rowtype;
  v_refresh jsonb;
begin
  if not exists (
    select 1 from public.coach_intelligence_pilots
    where id=p_pilot_id and source_system='cv12_legacy' and mode='observed_only'
  ) then
    raise exception 'V87 requires an observed_only cv12_legacy pilot';
  end if;

  if jsonb_typeof(coalesce(p_sessions,'[]'::jsonb)) <> 'array'
     or jsonb_typeof(coalesce(p_exercise_logs,'[]'::jsonb)) <> 'array'
     or jsonb_typeof(coalesce(p_measurements,'[]'::jsonb)) <> 'array' then
    raise exception 'V87 sync payloads must be JSON arrays';
  end if;

  for x in select value from jsonb_array_elements(coalesce(p_sessions,'[]'::jsonb)) loop
    insert into public.legacy_cv12_sessions_v87(
      pilot_id,source_row_key,completed_at,week_start,day_label,title,difficulty,final_observation,state,counted,
      level,rank_name,class_name,training_progress,nutrition_progress,walk_progress,leveled_up,reward,raw,source_revision,updated_at
    ) values (
      p_pilot_id,
      x->>'source_row_key',
      (x->>'completed_at')::timestamptz,
      nullif(x->>'week_start','')::date,
      nullif(x->>'day_label',''),
      nullif(x->>'title',''),
      nullif(x->>'difficulty','')::numeric,
      nullif(x->>'final_observation',''),
      nullif(x->>'state',''),
      case when x ? 'counted' then (x->>'counted')::boolean else null end,
      nullif(x->>'level','')::integer,
      nullif(x->>'rank_name',''),
      nullif(x->>'class_name',''),
      nullif(x->>'training_progress',''),
      nullif(x->>'nutrition_progress',''),
      nullif(x->>'walk_progress',''),
      case when x ? 'leveled_up' then (x->>'leveled_up')::boolean else null end,
      nullif(x->>'reward',''),
      x,
      p_source_revision,
      now()
    )
    on conflict (pilot_id,source_row_key) do update set
      completed_at=excluded.completed_at,week_start=excluded.week_start,day_label=excluded.day_label,title=excluded.title,
      difficulty=excluded.difficulty,final_observation=excluded.final_observation,state=excluded.state,counted=excluded.counted,
      level=excluded.level,rank_name=excluded.rank_name,class_name=excluded.class_name,training_progress=excluded.training_progress,
      nutrition_progress=excluded.nutrition_progress,walk_progress=excluded.walk_progress,leveled_up=excluded.leveled_up,
      reward=excluded.reward,raw=excluded.raw,source_revision=excluded.source_revision,updated_at=now();
    v_session_count := v_session_count + 1;
  end loop;

  for x in select value from jsonb_array_elements(coalesce(p_exercise_logs,'[]'::jsonb)) loop
    select * into v_alias
    from public.legacy_cv12_exercise_aliases_v87
    where lower(legacy_name)=lower(x->>'exercise_name')
    limit 1;

    insert into public.legacy_cv12_exercise_logs_v87(
      pilot_id,source_row_key,completed_at,day_label,day_title,exercise_name,exercise_id,mapping_status,
      target_sets,target_reps,weight_raw,series_values,difficulty,observation,raw,source_revision,updated_at
    ) values (
      p_pilot_id,
      x->>'source_row_key',
      (x->>'completed_at')::timestamptz,
      nullif(x->>'day_label',''),
      nullif(x->>'day_title',''),
      x->>'exercise_name',
      v_alias.exercise_id,
      coalesce(v_alias.mapping_status,'unmapped'),
      nullif(x->>'target_sets','')::integer,
      nullif(x->>'target_reps',''),
      nullif(x->>'weight_raw',''),
      coalesce(x->'series_values','[]'::jsonb),
      nullif(x->>'difficulty','')::numeric,
      nullif(x->>'observation',''),
      x,
      p_source_revision,
      now()
    )
    on conflict (pilot_id,source_row_key) do update set
      completed_at=excluded.completed_at,day_label=excluded.day_label,day_title=excluded.day_title,
      exercise_name=excluded.exercise_name,exercise_id=excluded.exercise_id,mapping_status=excluded.mapping_status,
      target_sets=excluded.target_sets,target_reps=excluded.target_reps,weight_raw=excluded.weight_raw,
      series_values=excluded.series_values,difficulty=excluded.difficulty,observation=excluded.observation,
      raw=excluded.raw,source_revision=excluded.source_revision,updated_at=now();
    v_log_count := v_log_count + 1;
  end loop;

  for x in select value from jsonb_array_elements(coalesce(p_measurements,'[]'::jsonb)) loop
    insert into public.legacy_cv12_measurements_v87(
      pilot_id,source_row_key,measured_at,body_weight,waist_cm,hip_cm,thigh_cm,energy,nutrition_adherence,
      comments,raw,source_revision,updated_at
    ) values (
      p_pilot_id,
      x->>'source_row_key',
      (x->>'measured_at')::timestamptz,
      nullif(x->>'body_weight','')::numeric,
      nullif(x->>'waist_cm','')::numeric,
      nullif(x->>'hip_cm','')::numeric,
      nullif(x->>'thigh_cm','')::numeric,
      nullif(x->>'energy','')::numeric,
      nullif(x->>'nutrition_adherence','')::numeric,
      nullif(x->>'comments',''),
      x,
      p_source_revision,
      now()
    )
    on conflict (pilot_id,source_row_key) do update set
      measured_at=excluded.measured_at,body_weight=excluded.body_weight,waist_cm=excluded.waist_cm,
      hip_cm=excluded.hip_cm,thigh_cm=excluded.thigh_cm,energy=excluded.energy,
      nutrition_adherence=excluded.nutrition_adherence,comments=excluded.comments,raw=excluded.raw,
      source_revision=excluded.source_revision,updated_at=now();
    v_measure_count := v_measure_count + 1;
  end loop;

  v_refresh := public.refresh_cv12_pilot_baseline_v87(p_pilot_id);

  return jsonb_build_object(
    'ok',true,
    'engine_version','CV12_LEGACY_SYNC_V87',
    'pilot_id',p_pilot_id,
    'rows_received',jsonb_build_object('sessions',v_session_count,'exercise_logs',v_log_count,'measurements',v_measure_count),
    'baseline',v_refresh,
    'guardrails',jsonb_build_object('idempotent',true,'auto_publish',false,'auto_program_edit',false)
  );
end;
$function$;

revoke all on function public.sync_cv12_legacy_v87(uuid,jsonb,jsonb,jsonb,text) from public, anon, authenticated;
grant execute on function public.sync_cv12_legacy_v87(uuid,jsonb,jsonb,jsonb,text) to service_role;

comment on function public.sync_cv12_legacy_v87(uuid,jsonb,jsonb,jsonb,text) is 'V87 service-only, idempotent legacy CV12 snapshot sync. Reads never mutate native programs.';
