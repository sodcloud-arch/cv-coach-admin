-- ARCH-1.0 · F1.M1.S5 Wave E2B — CV Score + CV state identity cutover
-- Preserves the CV12 formula and changes only the tenant boundary of inputs/state.

-- ---------------------------------------------------------------------------
-- client_cv_state identity cutover: Organization + Client
-- ---------------------------------------------------------------------------

alter table public.client_cv_state
  drop constraint if exists client_cv_state_pkey;

drop index if exists public.ux_client_cv_state_org_client;

alter table public.client_cv_state
  add constraint client_cv_state_pkey
  primary key (organization_id,client_id);


CREATE OR REPLACE FUNCTION private.calculate_cv_score_core_in_org(p_organization_id uuid, p_client_id uuid, p_as_of_date date DEFAULT NULL::date, p_trigger_source text DEFAULT 'system'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_as_of date;
  v_tz text;
  v_cfg jsonb;
  v_weights jsonb;
  v_recency jsonb;
  v_progress_weights jsonb;
  v_progress_cadence jsonb;
  v_states jsonb;

  v_w_training numeric := 0.40;
  v_w_nutrition numeric := 0.25;
  v_w_habits numeric := 0.20;
  v_w_progress numeric := 0.15;
  v_r numeric[] := array[0.40::numeric,0.30::numeric,0.20::numeric,0.10::numeric];

  v_training_config boolean := false;
  v_nutrition_config boolean := false;
  v_habits_config boolean := false;
  v_progress_config boolean := false;

  v_training_score numeric := 0;
  v_nutrition_score numeric := 0;
  v_habit_score numeric := 0;
  v_progress_score numeric := 0;
  v_cv_score numeric := 0;

  v_accum numeric;
  v_weight_sum numeric;
  v_effective_weight numeric;
  v_bucket_start date;
  v_bucket_end date;
  v_overlap_start date;
  v_overlap_end date;
  v_active_days integer;
  v_expected numeric;
  v_actual numeric;
  v_bucket_score numeric;
  v_bucket_details jsonb;
  i integer;

  v_program public.programs%rowtype;
  v_program_days integer := 0;
  v_nutrition_target public.nutrition_targets%rowtype;
  v_habit_count integer;

  v_measure_first date;
  v_photo_first date;
  v_checkin_first date;
  v_measure_last date;
  v_photo_last date;
  v_measure_score numeric;
  v_photo_score numeric;
  v_checkin_score numeric;
  v_sub_accum numeric;
  v_sub_weight numeric;
  v_pw_measure numeric := 0.40;
  v_pw_photos numeric := 0.30;
  v_pw_checkin numeric := 0.30;
  v_measure_full integer := 14;
  v_measure_half integer := 28;
  v_photo_full integer := 28;
  v_photo_half integer := 56;

  v_prior_score numeric;
  v_trend numeric;
  v_state text := 'INICIO';
  v_weakest text;
  v_algorithm text := 'CV12-1.0';
  v_details jsonb := '{}'::jsonb;
  v_configured jsonb;
  v_result jsonb;
  v_snapshot_id uuid;

  v_streak_min numeric := 85;
  v_streak_drop numeric := 3;
  v_ascending_delta numeric := 5;
  v_consistent_min numeric := 70;
  v_consistent_drop numeric := 8;
  v_recovery_delta numeric := 2;
  v_attention_below numeric := 50;
begin
  if p_organization_id is null or p_client_id is null then
    raise exception 'organization_id and client_id are required';
  end if;

  if not exists (
    select 1
    from public.clients c
    join public.profiles p on p.id=c.user_id
    where c.organization_id=p_organization_id
      and c.user_id=p_client_id
      and c.status<>'archived'::public.client_status
      and p.role='client'::public.app_role
      and p.status::text='active'
  ) then
    raise exception 'client is not active in requested organization';
  end if;

  select cp.timezone into v_tz
  from public.client_profiles cp
  where cp.organization_id=p_organization_id
    and cp.client_id=p_client_id;
  if v_tz is null or not exists(select 1 from pg_catalog.pg_timezone_names t where t.name=v_tz) then
    v_tz := 'America/Santiago';
  end if;
  v_as_of := coalesce(p_as_of_date, pg_catalog.timezone(v_tz, pg_catalog.now())::date);

  select value into v_weights from private.cv12_settings where key='score_weights';
  select value into v_recency from private.cv12_settings where key='score_recency_weights';
  select value into v_progress_weights from private.cv12_settings where key='score_progress_weights';
  select value into v_progress_cadence from private.cv12_settings where key='score_progress_cadence';
  select value into v_states from private.cv12_settings where key='score_dynamic_states';
  select value->>0 into v_algorithm from private.cv12_settings where false;
  select trim(both '"' from value::text) into v_algorithm from private.cv12_settings where key='algorithm_version';
  v_algorithm := coalesce(nullif(v_algorithm,''),'CV12-1.0');

  v_w_training := coalesce((v_weights->>'training')::numeric,0.40);
  v_w_nutrition := coalesce((v_weights->>'nutrition')::numeric,0.25);
  v_w_habits := coalesce((v_weights->>'habits')::numeric,0.20);
  v_w_progress := coalesce((v_weights->>'progress')::numeric,0.15);

  v_r[1] := coalesce((v_recency->>'days_1_7')::numeric,0.40);
  v_r[2] := coalesce((v_recency->>'days_8_14')::numeric,0.30);
  v_r[3] := coalesce((v_recency->>'days_15_21')::numeric,0.20);
  v_r[4] := coalesce((v_recency->>'days_22_28')::numeric,0.10);

  v_pw_measure := coalesce((v_progress_weights->>'measurement')::numeric,0.40);
  v_pw_photos := coalesce((v_progress_weights->>'photos')::numeric,0.30);
  v_pw_checkin := coalesce((v_progress_weights->>'weekly_checkin')::numeric,0.30);
  v_measure_full := coalesce((v_progress_cadence->>'measurement_full_days')::integer,14);
  v_measure_half := coalesce((v_progress_cadence->>'measurement_half_days')::integer,28);
  v_photo_full := coalesce((v_progress_cadence->>'photos_full_days')::integer,28);
  v_photo_half := coalesce((v_progress_cadence->>'photos_half_days')::integer,56);

  v_streak_min := coalesce((v_states->>'streak_min')::numeric,85);
  v_streak_drop := coalesce((v_states->>'streak_drop_tolerance')::numeric,3);
  v_ascending_delta := coalesce((v_states->>'ascending_delta')::numeric,5);
  v_consistent_min := coalesce((v_states->>'consistent_min')::numeric,70);
  v_consistent_drop := coalesce((v_states->>'consistent_drop_tolerance')::numeric,8);
  v_recovery_delta := coalesce((v_states->>'recovery_delta')::numeric,2);
  v_attention_below := coalesce((v_states->>'attention_below')::numeric,50);

  -- TRAINING: adherencia a la frecuencia del programa, no volumen ni carga.
  select p.* into v_program
  from public.programs p
  where p.organization_id=p_organization_id
    and p.client_id=p_client_id
    and p.status='active'::public.program_status
    and (p.start_date is null or p.start_date<=v_as_of)
    and (p.end_date is null or p.end_date>=v_as_of)
  order by coalesce(p.published_at,p.updated_at,p.created_at) desc
  limit 1;

  if found then
    select count(*)::integer into v_program_days
    from public.program_days pd
    where pd.organization_id=p_organization_id
      and pd.program_id=v_program.id
      and exists(select 1 from public.program_exercises pe where pe.organization_id=p_organization_id and pe.program_day_id=pd.id and pe.active=true);
  end if;

  v_accum:=0; v_weight_sum:=0; v_bucket_details:='[]'::jsonb;
  if v_program_days>0 then
    for i in 0..3 loop
      v_bucket_end := v_as_of - (i*7);
      v_bucket_start := v_bucket_end - 6;
      v_overlap_start := greatest(v_bucket_start,coalesce(v_program.start_date,v_program.created_at::date));
      v_overlap_end := least(v_bucket_end,coalesce(v_program.end_date,v_bucket_end));
      if v_overlap_start<=v_overlap_end then
        v_active_days := (v_overlap_end-v_overlap_start)+1;
        v_expected := v_program_days::numeric * v_active_days::numeric / 7.0;
        select coalesce(sum(case
          when ws.status='completed'::public.workout_session_status then 1::numeric
          when ws.status='partial'::public.workout_session_status then least(1::numeric,greatest(0::numeric,coalesce(ws.completion_pct,0)/100.0))
          else 0::numeric end),0)
        into v_actual
        from public.workout_sessions ws
        where ws.organization_id=p_organization_id
          and ws.client_id=p_client_id
          and ws.started_at::date between v_overlap_start and v_overlap_end;
        if v_expected>0 then
          v_bucket_score:=least(100::numeric,round((100*v_actual/v_expected)::numeric,2));
          v_accum:=v_accum+(v_bucket_score*v_r[i+1]);
          v_weight_sum:=v_weight_sum+v_r[i+1];
          v_bucket_details:=v_bucket_details||jsonb_build_array(jsonb_build_object(
            'days',jsonb_build_array(v_overlap_start,v_overlap_end),'expected_sessions',round(v_expected,2),'actual_units',round(v_actual,2),'score',v_bucket_score,'weight',v_r[i+1]
          ));
        end if;
      end if;
    end loop;
  end if;
  if v_weight_sum>0 then
    v_training_config:=true;
    v_training_score:=round(v_accum/v_weight_sum,2);
  end if;
  v_details:=v_details||jsonb_build_object('training',jsonb_build_object('configured',v_training_config,'score',v_training_score,'program_days_per_week',v_program_days,'buckets',v_bucket_details));

  -- NUTRITION: cumplimiento diario. Días sin registro cuentan como 0 solo cuando existe objetivo activo.
  select nt.* into v_nutrition_target
  from public.nutrition_targets nt
  where nt.organization_id=p_organization_id
    and nt.client_id=p_client_id and nt.active=true
    and nt.start_date<=v_as_of
    and (nt.end_date is null or nt.end_date>=v_as_of)
  order by nt.start_date desc,nt.created_at desc
  limit 1;

  v_accum:=0; v_weight_sum:=0; v_bucket_details:='[]'::jsonb;
  if found then
    for i in 0..3 loop
      v_bucket_end:=v_as_of-(i*7);
      v_bucket_start:=v_bucket_end-6;
      v_overlap_start:=greatest(v_bucket_start,v_nutrition_target.start_date);
      v_overlap_end:=least(v_bucket_end,coalesce(v_nutrition_target.end_date,v_bucket_end));
      if v_overlap_start<=v_overlap_end then
        v_active_days:=(v_overlap_end-v_overlap_start)+1;
        v_expected:=v_active_days;
        select coalesce(sum(case
          when nd.adherence_pct is not null then least(1::numeric,greatest(0::numeric,nd.adherence_pct/100.0))
          when nd.compliant is true then 1::numeric
          when nd.compliant is false then 0::numeric
          when coalesce(nd.meal_target_snapshot,0)>0 and nd.meals_completed is not null then least(1::numeric,greatest(0::numeric,nd.meals_completed::numeric/nd.meal_target_snapshot::numeric))
          else 0::numeric end),0)
        into v_actual
        from public.nutrition_daily_logs nd
        where nd.organization_id=p_organization_id
          and nd.client_id=p_client_id and nd.log_date between v_overlap_start and v_overlap_end;
        v_bucket_score:=least(100::numeric,round((100*v_actual/nullif(v_expected,0))::numeric,2));
        v_accum:=v_accum+(v_bucket_score*v_r[i+1]);
        v_weight_sum:=v_weight_sum+v_r[i+1];
        v_bucket_details:=v_bucket_details||jsonb_build_array(jsonb_build_object(
          'days',jsonb_build_array(v_overlap_start,v_overlap_end),'expected_days',v_expected,'compliance_units',round(v_actual,2),'score',v_bucket_score,'weight',v_r[i+1]
        ));
      end if;
    end loop;
  end if;
  if v_weight_sum>0 then
    v_nutrition_config:=true;
    v_nutrition_score:=round(v_accum/v_weight_sum,2);
  end if;
  v_details:=v_details||jsonb_build_object('nutrition',jsonb_build_object('configured',v_nutrition_config,'score',v_nutrition_score,'buckets',v_bucket_details));

  -- HABITS: cada hábito asignado pesa igual; frecuencia semanal/custom se prorratea si comenzó a mitad de semana.
  v_accum:=0; v_weight_sum:=0; v_bucket_details:='[]'::jsonb;
  for i in 0..3 loop
    v_bucket_end:=v_as_of-(i*7);
    v_bucket_start:=v_bucket_end-6;
    with h as (
      select ch.id,ch.frequency_type::text as freq,greatest(ch.frequency_target,1) as freq_target,
             greatest(v_bucket_start,ch.start_date) as overlap_start,
             least(v_bucket_end,coalesce(ch.end_date,v_bucket_end)) as overlap_end
      from public.client_habits ch
      where ch.organization_id=p_organization_id
        and ch.client_id=p_client_id and ch.active=true
        and ch.start_date<=v_bucket_end and (ch.end_date is null or ch.end_date>=v_bucket_start)
    ), hs as (
      select h.id,
             case when h.freq='daily' then ((h.overlap_end-h.overlap_start)+1)::numeric
                  else greatest(0.01::numeric,h.freq_target::numeric*((h.overlap_end-h.overlap_start)+1)::numeric/7.0) end as expected,
             (select count(*)::numeric from public.habit_logs hl where hl.organization_id=p_organization_id and hl.client_habit_id=h.id and hl.completed=true and hl.log_date between h.overlap_start and h.overlap_end) as actual
      from h where h.overlap_start<=h.overlap_end
    )
    select count(*)::integer,coalesce(avg(least(100::numeric,100*actual/nullif(expected,0))),0)
    into v_habit_count,v_bucket_score from hs;

    if v_habit_count>0 then
      v_bucket_score:=round(v_bucket_score,2);
      v_accum:=v_accum+(v_bucket_score*v_r[i+1]);
      v_weight_sum:=v_weight_sum+v_r[i+1];
      v_bucket_details:=v_bucket_details||jsonb_build_array(jsonb_build_object(
        'days',jsonb_build_array(v_bucket_start,v_bucket_end),'habits',v_habit_count,'score',v_bucket_score,'weight',v_r[i+1]
      ));
    end if;
  end loop;
  if v_weight_sum>0 then
    v_habits_config:=true;
    v_habit_score:=round(v_accum/v_weight_sum,2);
  end if;
  select count(*)::integer into v_habit_count from public.client_habits ch where ch.organization_id=p_organization_id and ch.client_id=p_client_id and ch.active=true and ch.start_date<=v_as_of and (ch.end_date is null or ch.end_date>=v_as_of);
  v_details:=v_details||jsonb_build_object('habits',jsonb_build_object('configured',v_habits_config,'score',v_habit_score,'active_habits',v_habit_count,'buckets',v_bucket_details));

  -- PROGRESS: premia monitoreo, no una dirección física concreta. Esto evita premiar o castigar peso perdido/ganado sin contexto de objetivo.
  select min(m.measured_at::date) into v_measure_first from public.measurements m where m.organization_id=p_organization_id and m.client_id=p_client_id and m.measured_at::date<=v_as_of;
  select min(pp.taken_at::date) into v_photo_first from public.progress_photos pp where pp.organization_id=p_organization_id and pp.client_id=p_client_id and pp.taken_at::date<=v_as_of;
  select min(rp.event_date) into v_checkin_first from private.cv12_reward_processing rp where rp.organization_id=p_organization_id and rp.client_id=p_client_id and rp.event_key='weekly_checkin' and rp.event_date<=v_as_of;
  v_progress_config := (v_measure_first is not null or v_photo_first is not null or v_checkin_first is not null);
  v_accum:=0; v_weight_sum:=0; v_bucket_details:='[]'::jsonb;

  if v_progress_config then
    for i in 0..3 loop
      v_bucket_end:=v_as_of-(i*7);
      v_bucket_start:=v_bucket_end-6;
      v_sub_accum:=0; v_sub_weight:=0;
      v_measure_score:=null; v_photo_score:=null; v_checkin_score:=null;

      if v_measure_first is not null and v_measure_first<=v_bucket_end then
        select max(m.measured_at::date) into v_measure_last from public.measurements m where m.organization_id=p_organization_id and m.client_id=p_client_id and m.measured_at::date<=v_bucket_end;
        v_measure_score:=case when v_measure_last is null then 0 when (v_bucket_end-v_measure_last)<=v_measure_full then 100 when (v_bucket_end-v_measure_last)<=v_measure_half then 50 else 0 end;
        v_sub_accum:=v_sub_accum+(v_measure_score*v_pw_measure); v_sub_weight:=v_sub_weight+v_pw_measure;
      end if;

      if v_photo_first is not null and v_photo_first<=v_bucket_end then
        select max(pp.taken_at::date) into v_photo_last from public.progress_photos pp where pp.organization_id=p_organization_id and pp.client_id=p_client_id and pp.taken_at::date<=v_bucket_end;
        v_photo_score:=case when v_photo_last is null then 0 when (v_bucket_end-v_photo_last)<=v_photo_full then 100 when (v_bucket_end-v_photo_last)<=v_photo_half then 50 else 0 end;
        v_sub_accum:=v_sub_accum+(v_photo_score*v_pw_photos); v_sub_weight:=v_sub_weight+v_pw_photos;
      end if;

      if v_checkin_first is not null and v_checkin_first<=v_bucket_end then
        v_checkin_score:=case when exists(select 1 from private.cv12_reward_processing rp where rp.organization_id=p_organization_id and rp.client_id=p_client_id and rp.event_key='weekly_checkin' and rp.event_date between v_bucket_start and v_bucket_end) then 100 else 0 end;
        v_sub_accum:=v_sub_accum+(v_checkin_score*v_pw_checkin); v_sub_weight:=v_sub_weight+v_pw_checkin;
      end if;

      if v_sub_weight>0 then
        v_bucket_score:=round(v_sub_accum/v_sub_weight,2);
        v_accum:=v_accum+(v_bucket_score*v_r[i+1]);
        v_weight_sum:=v_weight_sum+v_r[i+1];
        v_bucket_details:=v_bucket_details||jsonb_build_array(jsonb_build_object(
          'days',jsonb_build_array(v_bucket_start,v_bucket_end),'measurement',v_measure_score,'photos',v_photo_score,'weekly_checkin',v_checkin_score,'score',v_bucket_score,'weight',v_r[i+1]
        ));
      end if;
    end loop;
  end if;
  if v_weight_sum>0 then v_progress_score:=round(v_accum/v_weight_sum,2); else v_progress_config:=false; end if;
  v_details:=v_details||jsonb_build_object('progress',jsonb_build_object('configured',v_progress_config,'score',v_progress_score,'buckets',v_bucket_details));

  -- SCORE TOTAL: renormaliza pilares no configurados.
  v_effective_weight :=
      (case when v_training_config then v_w_training else 0 end)
    + (case when v_nutrition_config then v_w_nutrition else 0 end)
    + (case when v_habits_config then v_w_habits else 0 end)
    + (case when v_progress_config then v_w_progress else 0 end);

  if v_effective_weight>0 then
    v_cv_score:=round((
      (case when v_training_config then v_training_score*v_w_training else 0 end)+
      (case when v_nutrition_config then v_nutrition_score*v_w_nutrition else 0 end)+
      (case when v_habits_config then v_habit_score*v_w_habits else 0 end)+
      (case when v_progress_config then v_progress_score*v_w_progress else 0 end)
    )/v_effective_weight,2);
  else
    v_cv_score:=0;
  end if;

  v_configured:=jsonb_build_object('training',v_training_config,'nutrition',v_nutrition_config,'habits',v_habits_config,'progress',v_progress_config);

  select x.pillar into v_weakest
  from (values
    ('training'::text,v_training_score,v_training_config),
    ('nutrition'::text,v_nutrition_score,v_nutrition_config),
    ('habits'::text,v_habit_score,v_habits_config),
    ('progress'::text,v_progress_score,v_progress_config)
  ) as x(pillar,score,configured)
  where x.configured
  order by x.score asc, x.pillar
  limit 1;

  select s.cv_score into v_prior_score
  from public.cv_score_snapshots s
  where s.organization_id=p_organization_id
    and s.client_id=p_client_id and s.as_of_date<=v_as_of-7
  order by s.as_of_date desc,s.calculated_at desc
  limit 1;

  if v_prior_score is null then
    v_state:='INICIO'; v_trend:=null;
  else
    v_trend:=round(v_cv_score-v_prior_score,2);
    if v_cv_score>=v_streak_min and v_trend>=(-v_streak_drop) then
      v_state:='EN RACHA';
    elsif v_trend>=v_ascending_delta then
      v_state:='ASCENDIENDO';
    elsif v_cv_score>=v_consistent_min and v_trend>(-v_consistent_drop) then
      v_state:='CONSISTENTE';
    elsif v_trend>=v_recovery_delta then
      v_state:='RECUPERANDO';
    elsif v_cv_score<v_attention_below or v_trend<=(-v_consistent_drop) then
      v_state:='REQUIERE ATENCIÓN';
    elsif v_cv_score>=v_consistent_min then
      v_state:='CONSISTENTE';
    else
      v_state:='RECUPERANDO';
    end if;
  end if;

  v_details:=v_details||jsonb_build_object(
    'weights',jsonb_build_object('base',jsonb_build_object('training',v_w_training,'nutrition',v_w_nutrition,'habits',v_w_habits,'progress',v_w_progress),'effective_sum',v_effective_weight),
    'previous_score_7d',v_prior_score,
    'trigger_source',p_trigger_source
  );

  insert into public.cv_score_snapshots(
    organization_id,client_id,calculated_at,as_of_date,training_score,nutrition_score,habit_score,progress_score,cv_score,
    algorithm_version,configured_pillars,score_details,trend_delta,dynamic_state,weakest_pillar
  ) values (
    p_organization_id,p_client_id,now(),v_as_of,v_training_score,v_nutrition_score,v_habit_score,v_progress_score,v_cv_score,
    v_algorithm,v_configured,v_details,v_trend,v_state,v_weakest
  ) returning id into v_snapshot_id;

  update public.client_cv_state s
  set dynamic_state=v_state,current_cv_score=v_cv_score,updated_at=now()
  where s.organization_id=p_organization_id
    and s.client_id=p_client_id;

  v_result:=jsonb_build_object(
    'snapshot_id',v_snapshot_id,'organization_id',p_organization_id,'client_id',p_client_id,'as_of_date',v_as_of,'cv_score',v_cv_score,
    'training_score',v_training_score,'nutrition_score',v_nutrition_score,'habit_score',v_habit_score,'progress_score',v_progress_score,
    'configured_pillars',v_configured,'weakest_pillar',v_weakest,'dynamic_state',v_state,'trend_delta',v_trend,'algorithm_version',v_algorithm
  );
  return v_result;
end;
$function$;


create or replace function private.calculate_cv_score_core(
  p_client_id uuid,
  p_as_of_date date default null::date,
  p_trigger_source text default 'system'::text
)
returns jsonb
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
  return private.calculate_cv_score_core_in_org(
    v_organization,p_client_id,p_as_of_date,p_trigger_source
  );
end;
$function$;

CREATE OR REPLACE FUNCTION private.refresh_client_cv_state_in_org(p_organization_id uuid, p_client_id uuid, p_trigger_source text DEFAULT 'system'::text)
 RETURNS TABLE(previous_level integer, current_level integer, total_xp integer, credit_balance integer, new_levels integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_prev integer;
  v_new integer;
  v_eligible integer;
  v_xp integer;
  v_balance integer;
  v_hist uuid;
  v_level record;
  v_new_levels integer:=0;
begin
  if not exists(
    select 1
    from public.clients c
    join public.profiles p
      on p.id=c.user_id
    where c.organization_id=p_organization_id
      and c.user_id=p_client_id
      and c.status<>'archived'::public.client_status
      and p.role='client'::public.app_role
  ) then
    return;
  end if;

  insert into public.client_cv_state(
    organization_id,client_id,current_level,total_xp,credit_balance
  )
  values(
    p_organization_id,p_client_id,1,0,0
  )
  on conflict(organization_id,client_id) do nothing;

  insert into public.client_level_history(
    organization_id,client_id,level_number,trigger_source
  )
  values(
    p_organization_id,p_client_id,1,'initial'
  )
  on conflict(
    organization_id,client_id,level_number
  ) do nothing;

  select s.current_level into v_prev
  from public.client_cv_state s
  where s.organization_id=p_organization_id
    and s.client_id=p_client_id
  for update;

  select greatest(
    0,
    coalesce(
      sum(x.amount) filter(
        where x.reversed_at is null
      ),
      0
    )::integer
  )
  into v_xp
  from public.xp_ledger x
  where x.organization_id=p_organization_id
    and x.client_id=p_client_id;

  select coalesce(
    sum(
      case c.transaction_type
        when 'earned'::public.credit_transaction_type
          then abs(c.amount)
        when 'spent'::public.credit_transaction_type
          then -abs(c.amount)
        when 'adjustment'::public.credit_transaction_type
          then c.amount
        when 'reversal'::public.credit_transaction_type
          then c.amount
        else 0
      end
    ),
    0
  )::integer
  into v_balance
  from public.credit_ledger c
  where c.organization_id=p_organization_id
    and c.client_id=p_client_id;

  select coalesce(max(l.level_number),1)
  into v_eligible
  from public.cv_levels l
  where l.xp_required_total<=v_xp
    and private.level_requirements_met_in_org(
      p_organization_id,p_client_id,l.level_number
    );

  v_new:=greatest(
    v_prev,
    coalesce(v_eligible,1)
  );

  if v_new>v_prev then
    for v_level in
      select l.level_number,l.reward_credits
      from public.cv_levels l
      where l.level_number>v_prev
        and l.level_number<=v_new
      order by l.level_number
    loop
      v_hist:=null;

      insert into public.client_level_history(
        organization_id,client_id,level_number,trigger_source
      )
      values(
        p_organization_id,p_client_id,
        v_level.level_number,p_trigger_source
      )
      on conflict(
        organization_id,client_id,level_number
      ) do nothing
      returning id into v_hist;

      if v_hist is not null then
        v_new_levels:=v_new_levels+1;

        if v_level.reward_credits>0 then
          insert into public.credit_ledger(
            organization_id,client_id,transaction_type,
            source_type,source_id,amount,description
          )
          values(
            p_organization_id,
            p_client_id,
            'earned'::public.credit_transaction_type,
            'level_up',
            v_hist,
            v_level.reward_credits,
            'Recompensa por alcanzar Nivel '||
              v_level.level_number
          )
          on conflict do nothing;
        end if;
      end if;
    end loop;

    select coalesce(
      sum(
        case c.transaction_type
          when 'earned'::public.credit_transaction_type
            then abs(c.amount)
          when 'spent'::public.credit_transaction_type
            then -abs(c.amount)
          when 'adjustment'::public.credit_transaction_type
            then c.amount
          when 'reversal'::public.credit_transaction_type
            then c.amount
          else 0
        end
      ),
      0
    )::integer
    into v_balance
    from public.credit_ledger c
    where c.organization_id=p_organization_id
      and c.client_id=p_client_id;
  end if;

  update public.client_cv_state s
  set current_level=v_new,
      total_xp=v_xp,
      credit_balance=v_balance,
      current_cv_score=(
        select cs.cv_score
        from public.cv_score_snapshots cs
        where cs.organization_id=p_organization_id
          and cs.client_id=p_client_id
        order by cs.calculated_at desc
        limit 1
      ),
      dynamic_state=coalesce(
        (
          select cs.dynamic_state
          from public.cv_score_snapshots cs
          where cs.organization_id=p_organization_id
            and cs.client_id=p_client_id
          order by cs.calculated_at desc
          limit 1
        ),
        s.dynamic_state
      ),
      updated_at=now()
  where s.organization_id=p_organization_id
    and s.client_id=p_client_id;

  return query
  select v_prev,v_new,v_xp,v_balance,v_new_levels;
end;
$function$;


create or replace function private.recalculate_cv_score_trigger()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_client uuid;
  v_organization uuid;
begin
  if tg_op='DELETE' then
    v_client:=old.client_id;
    v_organization:=old.organization_id;
  else
    v_client:=new.client_id;
    v_organization:=new.organization_id;
  end if;

  if tg_table_name='workout_sessions'
     and private.is_cv_canary_client(v_client) then
    return null;
  end if;

  if v_client is not null and v_organization is not null then
    perform private.calculate_cv_score_core_in_org(
      v_organization,
      v_client,
      null,
      'trigger:'||tg_table_name
    );
  end if;

  return null;
end;
$function$;

create or replace function private.process_cv_score_automation()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_template public.mission_templates%rowtype;
  v_template_name text;
  v_weak_score numeric;
  v_habit_category text;
  v_coach uuid;
  v_program_days integer;
  v_details jsonb;
begin
  v_details:=jsonb_build_object(
    'organization_id',new.organization_id,
    'snapshot_id',new.id,
    'cv_score',new.cv_score,
    'trend_delta',new.trend_delta,
    'training_score',new.training_score,
    'nutrition_score',new.nutrition_score,
    'habit_score',new.habit_score,
    'progress_score',new.progress_score,
    'weakest_pillar',new.weakest_pillar,
    'dynamic_state',new.dynamic_state
  );

  -- 1) Operational alerts for canonical active coaches in this Organization.
  for v_coach in
    select cp.user_id
    from public.clients c
    join public.client_coach_assignments a
      on a.organization_id=c.organization_id
     and a.client_id=c.id
     and a.status='active'::public.client_coach_assignment_status
    join public.coach_profiles cp
      on cp.organization_id=a.organization_id
     and cp.id=a.coach_id
     and cp.status='active'::public.coach_profile_status
    where c.organization_id=new.organization_id
      and c.user_id=new.client_id
      and c.status<>'archived'::public.client_status
  loop
    perform private.set_coach_alert_in_org(
      new.organization_id,
      v_coach,
      new.client_id,
      'cv_score_low',
      new.cv_score<50,
      case
        when new.cv_score<35 then 'critical'::public.alert_severity
        else 'warning'::public.alert_severity
      end,
      'CV Score requiere atención',
      'El CV Score actual es '||round(new.cv_score)::text||
        '. Revisa adherencia y contexto del cliente.',
      v_details
    );

    perform private.set_coach_alert_in_org(
      new.organization_id,
      v_coach,
      new.client_id,
      'cv_score_drop',
      coalesce(new.trend_delta,0)<=-10,
      case
        when coalesce(new.trend_delta,0)<=-20
          then 'critical'::public.alert_severity
        else 'warning'::public.alert_severity
      end,
      'Caída relevante de CV Score',
      'El CV Score cambió '||
        coalesce(round(new.trend_delta)::text,'0')||
        ' puntos frente a la referencia de 7 días.',
      v_details
    );

    perform private.set_coach_alert_in_org(
      new.organization_id,
      v_coach,
      new.client_id,
      'training_attention',
      coalesce(
        (new.configured_pillars->>'training')::boolean,
        false
      ) and new.training_score<50,
      'warning'::public.alert_severity,
      'Adherencia de entrenamiento baja',
      'Pilar Entrenamiento: '||
        round(new.training_score)::text||'/100.',
      v_details
    );

    perform private.set_coach_alert_in_org(
      new.organization_id,
      v_coach,
      new.client_id,
      'nutrition_attention',
      coalesce(
        (new.configured_pillars->>'nutrition')::boolean,
        false
      ) and new.nutrition_score<50,
      'warning'::public.alert_severity,
      'Adherencia nutricional baja',
      'Pilar Nutrición: '||
        round(new.nutrition_score)::text||'/100.',
      v_details
    );

    perform private.set_coach_alert_in_org(
      new.organization_id,
      v_coach,
      new.client_id,
      'habits_attention',
      coalesce(
        (new.configured_pillars->>'habits')::boolean,
        false
      ) and new.habit_score<50,
      'warning'::public.alert_severity,
      'Hábitos requieren atención',
      'Pilar Hábitos: '||
        round(new.habit_score)::text||'/100.',
      v_details
    );
  end loop;

  -- 2) Adaptive mission remains inside the snapshot Organization.
  v_template_name:=null;
  v_weak_score:=case new.weakest_pillar
    when 'training' then new.training_score
    when 'nutrition' then new.nutrition_score
    when 'habits' then new.habit_score
    when 'progress' then new.progress_score
    else null
  end;

  if v_weak_score is not null
     and v_weak_score<70
     and not exists(
       select 1
       from public.client_missions cm
       where cm.organization_id=new.organization_id
         and cm.client_id=new.client_id
         and cm.status='active'::public.client_mission_status
         and cm.pillar=new.weakest_pillar
         and cm.generated_reason like 'CV12 adaptive:%'
         and (
           cm.expires_at is null
           or cm.expires_at>now()
         )
     ) then

    if new.weakest_pillar='training' then
      select count(*)::integer into v_program_days
      from public.program_days pd
      join public.programs p
        on p.organization_id=pd.organization_id
       and p.id=pd.program_id
      where p.organization_id=new.organization_id
        and p.client_id=new.client_id
        and p.status='active'::public.program_status;

      if coalesce(v_program_days,0)>=2 then
        v_template_name:='Volver al ritmo';
      end if;

    elsif new.weakest_pillar='nutrition'
      and exists(
        select 1
        from public.nutrition_targets nt
        where nt.organization_id=new.organization_id
          and nt.client_id=new.client_id
          and nt.active=true
      ) then
      v_template_name:='5 días de nutrición';

    elsif new.weakest_pillar='habits' then
      with cats as (
        select
          hd.category,
          count(*) filter(
            where hl.completed=true
          )::numeric/nullif(
            count(distinct ch.id)*7,
            0
          ) as ratio
        from public.client_habits ch
        join public.habit_definitions hd
          on hd.id=ch.habit_id
        left join public.habit_logs hl
          on hl.organization_id=ch.organization_id
         and hl.client_habit_id=ch.id
         and hl.log_date between current_date-6 and current_date
        where ch.organization_id=new.organization_id
          and ch.client_id=new.client_id
          and ch.active=true
          and ch.start_date<=current_date
          and (
            ch.end_date is null
            or ch.end_date>=current_date
          )
        group by hd.category
      )
      select category into v_habit_category
      from cats
      order by ratio asc nulls first,category
      limit 1;

      v_template_name:=case v_habit_category
        when 'steps' then 'Pasos 5 de 7'
        when 'sleep' then 'Sueño 5 de 7'
        when 'hydration' then 'Hidratación 5 de 7'
        when 'cardio' then 'Cardio semanal'
        else null
      end;
    end if;

    if v_template_name is not null then
      select * into v_template
      from public.mission_templates mt
      where mt.name=v_template_name
        and mt.active=true
      order by mt.created_at desc
      limit 1;

      if v_template.id is not null
         and not exists(
           select 1
           from public.client_missions cm
           where cm.organization_id=new.organization_id
             and cm.client_id=new.client_id
             and cm.mission_template_id=v_template.id
             and cm.status='active'::public.client_mission_status
             and (
               cm.expires_at is null
               or cm.expires_at>now()
             )
         ) then

        insert into public.client_missions(
          organization_id,client_id,mission_template_id,
          mission_name,mission_description,pillar,assigned_by,
          generated_reason,xp_reward_snapshot,
          credit_reward_snapshot,start_at,expires_at,
          progress,target,status
        )
        values(
          new.organization_id,
          new.client_id,
          v_template.id,
          v_template.name,
          v_template.description,
          v_template.pillar,
          null,
          'CV12 adaptive: weakest_pillar='||
            new.weakest_pillar||
            '; score='||round(v_weak_score)::text,
          v_template.xp_reward,
          v_template.credit_reward,
          now(),
          now()+interval '7 days',
          0,
          coalesce(
            nullif(
              v_template.rule->>'default_target',
              ''
            )::numeric,
            1
          ),
          'active'::public.client_mission_status
        );

        insert into public.notifications(
          user_id,type,title,body,action_url,metadata
        )
        values(
          new.client_id,
          'adaptive_mission',
          'Nueva misión adaptativa',
          v_template.name,
          '/progress/missions',
          jsonb_build_object(
            'organization_id',new.organization_id,
            'mission_template_id',v_template.id,
            'weakest_pillar',new.weakest_pillar
          )
        );
      end if;
    end if;
  end if;

  return new;
end;
$function$;

create or replace function public.calculate_cv_score_backend(
  p_actor_id uuid,
  p_client_id uuid default null::uuid,
  p_as_of_date date default null::date
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_target uuid:=coalesce(p_client_id,p_actor_id);
  v_role text;
  v_organization uuid;
begin
  if p_actor_id is null then
    raise exception 'actor_id is required';
  end if;

  select p.role::text into v_role
  from public.profiles p
  where p.id=p_actor_id
    and p.status::text='active';

  if v_role is null then
    raise exception 'actor is not an active CV Coach user';
  end if;

  if not exists(
    select 1
    from public.profiles p
    where p.id=v_target
      and p.role='client'::public.app_role
      and p.status::text='active'
  ) then
    raise exception 'target is not an active client';
  end if;

  if p_actor_id=v_target then
    if v_role<>'client' then
      raise exception 'self CV score requires a client account';
    end if;
    v_organization:=private.resolve_legacy_client_organization_v1(
      v_target,null
    );
  else
    if v_role not in ('admin','coach') then
      raise exception 'actor role is not authorized';
    end if;

    v_organization:=private.resolve_legacy_professional_organization_v1(
      p_actor_id,v_target
    );

    if not private.actor_can_manage_client_in_org_v1(
      p_actor_id,v_organization,v_target
    ) then
      raise exception 'actor is not authorized for this client in organization';
    end if;
  end if;

  return private.calculate_cv_score_core_in_org(
    v_organization,v_target,p_as_of_date,'rpc'
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.log_habit_backend(p_actor_id uuid, p_client_habit_id uuid, p_log_date date DEFAULT CURRENT_DATE, p_value numeric DEFAULT NULL::numeric, p_text_value text DEFAULT NULL::text, p_completed boolean DEFAULT NULL::boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor_role text;
  v_client_id uuid;
  v_organization uuid;
  v_habit_id uuid;
  v_category text;
  v_name text;
  v_input text;
  v_target numeric;
  v_min numeric;
  v_max numeric;
  v_custom_xp integer;
  v_default_xp integer;
  v_complete boolean:=false;
  v_source public.log_source;
  v_log_id uuid;
  v_event text;
  v_reward record;
  v_missions integer:=0;
  v_achievements jsonb:='[]'::jsonb;
  v_state record;
  v_level_before integer:=1;
  v_level_after integer:=1;
  v_request_role text:=coalesce(auth.role(),'');
  v_request_user uuid:=auth.uid();
begin
  if p_actor_id is null or p_client_habit_id is null then
    raise exception 'actor_id and client_habit_id are required';
  end if;
  if p_log_date is null or p_log_date>current_date then
    raise exception 'invalid log_date';
  end if;

  if v_request_role<>'service_role'
     and (v_request_user is null or v_request_user<>p_actor_id) then
    raise exception 'actor identity mismatch';
  end if;

  select p.role::text into v_actor_role
  from public.profiles p
  where p.id=p_actor_id
    and p.status::text='active';

  if v_actor_role is null then
    raise exception 'actor is not an active CV Coach user';
  end if;

  select
    ch.organization_id,
    ch.client_id,
    ch.habit_id,
    hd.category,
    hd.name,
    hd.input_type::text,
    ch.target_value,
    ch.minimum_value,
    ch.maximum_value,
    ch.xp_reward,
    hd.default_xp
  into
    v_organization,
    v_client_id,
    v_habit_id,
    v_category,
    v_name,
    v_input,
    v_target,
    v_min,
    v_max,
    v_custom_xp,
    v_default_xp
  from public.client_habits ch
  join public.habit_definitions hd
    on hd.id=ch.habit_id
  where ch.id=p_client_habit_id
    and ch.active=true
    and ch.start_date<=p_log_date
    and (ch.end_date is null or ch.end_date>=p_log_date)
    and hd.active=true;

  if v_client_id is null then
    raise exception 'active client habit not found for this date';
  end if;

  if p_actor_id=v_client_id then
    if v_actor_role<>'client'
       or not private.is_org_member(v_organization) then
      raise exception 'self logging requires client membership in habit organization';
    end if;
  else
    if v_actor_role not in ('admin','coach')
       or not private.actor_can_manage_client_in_org_v1(
         p_actor_id,v_organization,v_client_id
       ) then
      raise exception 'actor is not authorized for this client habit in organization';
    end if;
  end if;

  if v_actor_role='client' and p_log_date<current_date-7 then
    raise exception 'client manual logs can be backfilled up to 7 days';
  end if;

  v_source:=case
    when p_actor_id=v_client_id then 'manual'::public.log_source
    else 'coach'::public.log_source
  end;

  select coalesce(s.current_level,1)
    into v_level_before
  from public.client_cv_state s
  where s.organization_id=v_organization
    and s.client_id=v_client_id;
  v_level_before:=coalesce(v_level_before,1);

  if v_input='boolean' then
    v_complete:=coalesce(p_completed,false);
  else
    if p_value is null then
      v_complete:=coalesce(p_completed,false);
    elsif v_min is not null and v_max is not null then
      v_complete:=p_value between v_min and v_max;
    elsif v_min is not null then
      v_complete:=p_value>=v_min;
    elsif v_max is not null then
      v_complete:=p_value<=v_max;
    elsif v_target is not null then
      v_complete:=p_value>=v_target;
    else
      v_complete:=coalesce(p_completed,false);
    end if;
  end if;

  insert into public.habit_logs(
    organization_id,client_habit_id,client_id,log_date,
    value,text_value,completed,source
  )
  values(
    v_organization,p_client_habit_id,v_client_id,p_log_date,
    p_value,p_text_value,v_complete,v_source
  )
  on conflict(client_habit_id,log_date) do update set
    organization_id=excluded.organization_id,
    value=excluded.value,
    text_value=excluded.text_value,
    completed=excluded.completed,
    source=excluded.source,
    updated_at=now()
  returning id into v_log_id;

  v_event:=case
    when v_category='cardio' then 'cardio_completed'
    else 'habit_completed'
  end;

  select
    0 as xp_awarded,
    0 as credits_awarded,
    false as idempotent,
    false as cap_reached
  into v_reward;

  if v_complete then
    select * into v_reward
    from private.award_cv12_action_in_org(
      v_organization,
      v_client_id,
      v_event,
      v_log_id,
      p_log_date,
      case
        when v_category='cardio' then 'Cardio/caminata completado'
        else 'Hábito cumplido: '||v_name
      end,
      case
        when v_event='habit_completed'
          then coalesce(nullif(v_custom_xp,0),nullif(v_default_xp,0))
        else null
      end
    );

    v_missions:=private.process_event_missions_in_org(
      v_organization,
      v_client_id,v_event,v_category
    );
    v_achievements:=private.process_generic_achievements_in_org(
      v_organization,
      v_client_id,v_event
    );
  end if;

  select * into v_state
  from private.refresh_client_cv_state_in_org(v_organization,v_client_id,v_event);

  v_level_after:=coalesce(
    v_state.current_level,
    v_level_before,
    1
  );

  return jsonb_build_object(
    'organization_id',v_organization,
    'client_id',v_client_id,
    'habit_log_id',v_log_id,
    'habit_name',v_name,
    'habit_category',v_category,
    'log_date',p_log_date,
    'completed',v_complete,
    'event',case when v_complete then v_event else null end,
    'xp_earned',coalesce(v_reward.xp_awarded,0),
    'credits_earned',coalesce(v_reward.credits_awarded,0),
    'reward_idempotent',coalesce(v_reward.idempotent,false),
    'reward_cap_reached',coalesce(v_reward.cap_reached,false),
    'missions_completed',v_missions,
    'achievements_unlocked',v_achievements,
    'previous_level',v_level_before,
    'current_level',v_level_after,
    'level_up',(v_level_after>v_level_before)
  );
end;
$function$;


CREATE OR REPLACE FUNCTION public.log_nutrition_day_backend(p_actor_id uuid, p_client_id uuid DEFAULT NULL::uuid, p_log_date date DEFAULT CURRENT_DATE, p_adherence_pct numeric DEFAULT NULL::numeric, p_meals_completed integer DEFAULT NULL::integer, p_compliant boolean DEFAULT NULL::boolean, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor_role text;
  v_client uuid;
  v_organization uuid;
  v_target public.nutrition_targets%rowtype;
  v_meal_target integer;
  v_compliant boolean:=false;
  v_source public.log_source;
  v_log_id uuid;
  v_reward record;
  v_missions integer:=0;
  v_achievements jsonb:='[]'::jsonb;
  v_state record;
  v_level_before integer:=1;
  v_level_after integer:=1;
  v_request_role text:=coalesce(auth.role(),'');
  v_request_user uuid:=auth.uid();
begin
  if p_actor_id is null then
    raise exception 'actor_id is required';
  end if;
  if p_log_date is null or p_log_date>current_date then
    raise exception 'invalid log_date';
  end if;
  if p_adherence_pct is not null
     and (p_adherence_pct<0 or p_adherence_pct>100) then
    raise exception 'adherence_pct must be between 0 and 100';
  end if;
  if p_meals_completed is not null and p_meals_completed<0 then
    raise exception 'meals_completed cannot be negative';
  end if;

  if v_request_role<>'service_role'
     and (v_request_user is null or v_request_user<>p_actor_id) then
    raise exception 'actor identity mismatch';
  end if;

  select p.role::text into v_actor_role
  from public.profiles p
  where p.id=p_actor_id
    and p.status::text='active';

  if v_actor_role is null then
    raise exception 'actor is not an active CV Coach user';
  end if;

  v_client:=coalesce(p_client_id,p_actor_id);

  if p_actor_id=v_client then
    if v_actor_role<>'client' then
      raise exception 'self nutrition logging requires a client account or an explicit client_id';
    end if;
    v_organization:=private.resolve_legacy_client_organization_v1(
      v_client,null
    );
    if not private.is_org_member(v_organization) then
      raise exception 'client is not active in resolved organization';
    end if;
  else
    if v_actor_role not in ('admin','coach') then
      raise exception 'actor is not authorized for this client';
    end if;
    v_organization:=private.resolve_legacy_professional_organization_v1(
      p_actor_id,v_client
    );
    if not private.actor_can_manage_client_in_org_v1(
      p_actor_id,v_organization,v_client
    ) then
      raise exception 'actor is not authorized for this client in organization';
    end if;
  end if;

  if v_actor_role='client' and p_log_date<current_date-7 then
    raise exception 'client manual logs can be backfilled up to 7 days';
  end if;

  v_source:=case
    when p_actor_id=v_client then 'manual'::public.log_source
    else 'coach'::public.log_source
  end;

  select coalesce(s.current_level,1)
    into v_level_before
  from public.client_cv_state s
  where s.organization_id=v_organization
    and s.client_id=v_client;
  v_level_before:=coalesce(v_level_before,1);

  select * into v_target
  from public.nutrition_targets nt
  where nt.organization_id=v_organization
    and nt.client_id=v_client
    and nt.active=true
    and nt.start_date<=p_log_date
    and (nt.end_date is null or nt.end_date>=p_log_date)
  order by nt.start_date desc,nt.created_at desc
  limit 1;

  v_meal_target:=case
    when found then v_target.meal_target
    else null
  end;

  if p_adherence_pct is not null then
    v_compliant:=p_adherence_pct>=80;
  elsif p_meals_completed is not null
        and v_meal_target is not null
        and v_meal_target>0 then
    v_compliant:=p_meals_completed>=v_meal_target;
  else
    v_compliant:=coalesce(p_compliant,false);
  end if;

  insert into public.nutrition_daily_logs(
    organization_id,client_id,log_date,adherence_pct,
    meals_completed,meal_target_snapshot,compliant,notes,source
  )
  values(
    v_organization,v_client,p_log_date,p_adherence_pct,
    p_meals_completed,v_meal_target,v_compliant,p_notes,v_source
  )
  on conflict(organization_id,client_id,log_date) do update set
    adherence_pct=excluded.adherence_pct,
    meals_completed=excluded.meals_completed,
    meal_target_snapshot=excluded.meal_target_snapshot,
    compliant=excluded.compliant,
    notes=excluded.notes,
    source=excluded.source,
    updated_at=now()
  returning id into v_log_id;

  select
    0 as xp_awarded,
    0 as credits_awarded,
    false as idempotent,
    false as cap_reached
  into v_reward;

  if v_compliant then
    select * into v_reward
    from private.award_cv12_action_in_org(
      v_organization,
      v_client,
      'nutrition_compliant',
      v_log_id,
      p_log_date,
      'Día de nutrición cumplido',
      null
    );

    v_missions:=private.process_event_missions_in_org(
      v_organization,
      v_client,'nutrition_compliant',null
    );
    v_achievements:=private.process_generic_achievements_in_org(
      v_organization,
      v_client,'nutrition_compliant'
    );
  end if;

  select * into v_state
  from private.refresh_client_cv_state_in_org(
    v_organization,v_client,'nutrition_compliant'
  );

  v_level_after:=coalesce(
    v_state.current_level,
    v_level_before,
    1
  );

  return jsonb_build_object(
    'organization_id',v_organization,
    'client_id',v_client,
    'nutrition_log_id',v_log_id,
    'log_date',p_log_date,
    'compliant',v_compliant,
    'adherence_pct',p_adherence_pct,
    'meals_completed',p_meals_completed,
    'meal_target',v_meal_target,
    'event',case
      when v_compliant then 'nutrition_compliant'
      else null
    end,
    'xp_earned',coalesce(v_reward.xp_awarded,0),
    'credits_earned',coalesce(v_reward.credits_awarded,0),
    'reward_idempotent',coalesce(v_reward.idempotent,false),
    'reward_cap_reached',coalesce(v_reward.cap_reached,false),
    'missions_completed',v_missions,
    'achievements_unlocked',v_achievements,
    'previous_level',v_level_before,
    'current_level',v_level_after,
    'level_up',(v_level_after>v_level_before)
  );
end;
$function$;


CREATE OR REPLACE FUNCTION public.complete_workout_backend(p_session_id uuid, p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_client uuid;
  v_organization uuid;
  v_before_level integer:=1;
  v_after_level integer:=1;
  v_before_xp integer:=0;
  v_after_xp integer:=0;
  v_before_credits integer:=0;
  v_after_credits integer:=0;
  v_result jsonb;
  v_personal_records jsonb:='[]'::jsonb;
  v_pr_count integer:=0;
begin
  select ws.organization_id,ws.client_id into v_organization,v_client from public.workout_sessions ws where ws.id=p_session_id;
  if v_client is null then raise exception 'workout session not found'; end if;

  perform private.refresh_client_cv_state_in_org(v_organization,v_client,'before_workout_completion');
  select s.current_level,s.total_xp,s.credit_balance into v_before_level,v_before_xp,v_before_credits from public.client_cv_state s where s.organization_id=v_organization and s.client_id=v_client;

  v_result:=public.complete_workout_backend_core(p_session_id,p_actor_id);

  if coalesce((v_result->>'idempotent')::boolean,false) then
    return v_result;
  end if;

  perform private.refresh_client_cv_state_in_org(v_organization,v_client,'workout_completed');
  select s.current_level,s.total_xp,s.credit_balance into v_after_level,v_after_xp,v_after_credits from public.client_cv_state s where s.organization_id=v_organization and s.client_id=v_client;

  v_personal_records:=private.detect_session_personal_records(p_session_id);
  v_pr_count:=jsonb_array_length(coalesce(v_personal_records,'[]'::jsonb));

  v_result:=v_result || jsonb_build_object(
    'previous_level',v_before_level,
    'current_level',v_after_level,
    'level_up',(v_after_level>v_before_level),
    'xp_earned',greatest(0,v_after_xp-v_before_xp),
    'credits_earned',v_after_credits-v_before_credits,
    'personal_records',coalesce(v_personal_records,'[]'::jsonb),
    'personal_record_count',v_pr_count
  );

  if v_pr_count>0 then
    insert into public.notifications(user_id,type,title,body,action_url,metadata)
    values(
      v_client,
      'personal_record',
      case when v_pr_count=1 then '¡Nuevo récord personal!' else '¡Nuevos récords personales!' end,
      case when v_pr_count=1 then 'Superaste una marca real de entrenamiento.' else 'Superaste '||v_pr_count||' marcas reales de entrenamiento.' end,
      '/progress',
      jsonb_build_object('organization_id',v_organization,'session_id',p_session_id,'personal_record_count',v_pr_count,'personal_records',v_personal_records)
    );
  end if;

  update private.workout_processing set result=v_result where session_id=p_session_id;
  return v_result;
end;
$function$;


CREATE OR REPLACE FUNCTION public.get_client_rank_state_backend(p_actor_id uuid, p_client_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor_role text; v_client uuid; v_organization uuid; v_state public.client_cv_state%rowtype; v_rank public.cv_classes%rowtype; v_next_rank public.cv_classes%rowtype;
  v_level public.cv_levels%rowtype; v_next_level public.cv_levels%rowtype; v_rank_start_xp integer:=0; v_next_rank_xp integer;
  v_level_progress numeric:=100; v_rank_progress numeric:=100; v_pillars jsonb:='{}'::jsonb;
begin
  if p_actor_id is null then raise exception 'actor_id is required'; end if;
  if auth.uid() is not null and auth.uid()<>p_actor_id then raise exception 'actor mismatch'; end if;
  select p.role::text into v_actor_role from public.profiles p where p.id=p_actor_id and p.status::text='active';
  if v_actor_role is null then raise exception 'actor is not an active CV Coach user'; end if;
  v_client:=coalesce(p_client_id,p_actor_id);
  if p_actor_id<>v_client then
    if v_actor_role='admin' then null;
    elsif v_actor_role='coach' and exists(select 1 from public.coach_clients cc where cc.coach_id=p_actor_id and cc.client_id=v_client and cc.status::text='active') then null;
    else raise exception 'actor is not authorized for this client'; end if;
  elsif v_actor_role<>'client' then raise exception 'self rank state requires a client account or explicit client_id'; end if;
  if p_actor_id=v_client then
    v_organization:=private.resolve_legacy_client_organization_v1(v_client,null);
  else
    v_organization:=private.resolve_legacy_professional_organization_v1(p_actor_id,v_client);
    if not private.actor_can_manage_client_in_org_v1(
      p_actor_id,v_organization,v_client
    ) then
      raise exception 'actor is not assigned to this client in organization';
    end if;
  end if;
  select * into v_state from public.client_cv_state s
  where s.organization_id=v_organization
    and s.client_id=v_client;
  if not found then return jsonb_build_object('client_id',v_client,'current_level',1,'total_xp',0,'rank',null); end if;
  select * into v_rank from public.cv_classes c where c.rank_key is not null and v_state.current_level between c.min_level and c.max_level order by c.order_index limit 1;
  select * into v_next_rank from public.cv_classes c where c.rank_key is not null and c.order_index>v_rank.order_index order by c.order_index limit 1;
  select * into v_level from public.cv_levels l where l.level_number=v_state.current_level;
  select * into v_next_level from public.cv_levels l where l.level_number=v_state.current_level+1;
  if v_next_level.level_number is not null then v_level_progress:=least(100,greatest(0,100.0*(v_state.total_xp-v_level.xp_required_total)::numeric/greatest(1,v_next_level.xp_required_total-v_level.xp_required_total)::numeric)); end if;
  select coalesce(l.xp_required_total,0) into v_rank_start_xp from public.cv_levels l where l.level_number=v_rank.min_level;
  if v_next_rank.id is not null then
    select l.xp_required_total into v_next_rank_xp from public.cv_levels l where l.level_number=v_next_rank.min_level;
    v_rank_progress:=least(100,greatest(0,100.0*(v_state.total_xp-v_rank_start_xp)::numeric/greatest(1,v_next_rank_xp-v_rank_start_xp)::numeric));
  end if;
  select coalesce(jsonb_object_agg(x.pillar,x.amount),'{}'::jsonb) into v_pillars from (
    select coalesce(nullif(xl.pillar,''),'other') pillar,coalesce(sum(xl.amount) filter(where xl.reversed_at is null),0)::integer amount
    from public.xp_ledger xl where xl.organization_id=v_organization and xl.client_id=v_client group by coalesce(nullif(xl.pillar,''),'other')
  ) x;
  return jsonb_build_object(
    'organization_id',v_organization,'client_id',v_client,'current_level',v_state.current_level,'total_xp',v_state.total_xp,'credit_balance',v_state.credit_balance,
    'cv_score',v_state.current_cv_score,'dynamic_state',v_state.dynamic_state,
    'rank',jsonb_build_object('key',v_rank.rank_key,'name',v_rank.name,'order',v_rank.order_index,'min_level',v_rank.min_level,'max_level',v_rank.max_level,'color_primary',v_rank.color_primary,'color_secondary',v_rank.color_secondary,'tagline',v_rank.tagline,'description',v_rank.description,'terminal',v_rank.is_terminal),
    'next_rank',case when v_next_rank.id is null then null else jsonb_build_object('key',v_next_rank.rank_key,'name',v_next_rank.name,'min_level',v_next_rank.min_level,'color_primary',v_next_rank.color_primary,'color_secondary',v_next_rank.color_secondary,'tagline',v_next_rank.tagline) end,
    'level_start_xp',coalesce(v_level.xp_required_total,0),'next_level_xp',v_next_level.xp_required_total,
    'xp_to_next_level',case when v_next_level.level_number is null then 0 else greatest(0,v_next_level.xp_required_total-v_state.total_xp) end,
    'level_progress_pct',round(v_level_progress,1),'next_rank_xp',v_next_rank_xp,
    'xp_to_next_rank',case when v_next_rank.id is null then 0 else greatest(0,v_next_rank_xp-v_state.total_xp) end,
    'levels_to_next_rank',case when v_next_rank.id is null then 0 else greatest(0,v_next_rank.min_level-v_state.current_level) end,
    'rank_progress_pct',round(v_rank_progress,1),'pillar_xp',v_pillars,
    'rank_reached_at',(select rh.reached_at from public.client_rank_history rh where rh.client_id=v_client and rh.class_id=v_rank.id limit 1)
  );
end;$function$;


CREATE OR REPLACE FUNCTION public.get_client_rank_dashboard_v61(p_actor_id uuid, p_client_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_client uuid:=coalesce(p_client_id,p_actor_id);v_organization uuid;v_profile public.client_competitive_rank_v61%rowtype;v_rule public.cv_rank_rules_v61%rowtype;v_next public.cv_rank_rules_v61%rowtype;v_floor numeric;v_next_floor numeric;v_preview jsonb;v_global int;v_league int;v_total int;v_week date:=date_trunc('week',now() at time zone 'America/Santiago')::date;begin
  if auth.uid() is not null and auth.uid()<>p_actor_id then raise exception 'actor mismatch';end if;
  if not private.cv_rank_authorized_client_v61(p_actor_id,v_client) then raise exception 'not authorized';end if;
  if p_actor_id=v_client then
    v_organization:=private.resolve_legacy_client_organization_v1(v_client,null);
  else
    v_organization:=private.resolve_legacy_professional_organization_v1(p_actor_id,v_client);
    if not private.actor_can_manage_client_in_org_v1(
      p_actor_id,v_organization,v_client
    ) then
      raise exception 'actor is not assigned to this client in organization';
    end if;
  end if;
  insert into public.client_competitive_rank_v61(client_id,competitive_alias) values(v_client,private.cv_alias_v61(v_client)) on conflict do nothing;
  select * into v_profile from public.client_competitive_rank_v61 where client_id=v_client;
  if v_profile.tutorial_completed then select * into v_rule from public.cv_rank_rules_v61 where rank_key=v_profile.current_rank_key;end if;
  if v_rule.rank_key is not null then select * into v_next from public.cv_rank_rules_v61 where order_index=v_rule.order_index+1;end if;
  select rating_floor into v_floor from public.cv_rank_level_thresholds_v61 where level_number=greatest(1,v_profile.current_level);
  select rating_floor into v_next_floor from public.cv_rank_level_thresholds_v61 where level_number=least(26,greatest(2,v_profile.current_level+1));
  v_preview:=private.calculate_discipline_v61(v_client,v_week);
  if v_profile.show_global and v_profile.tutorial_completed then
    select pos,total into v_global,v_total from (select client_id,row_number() over(order by cv_rating desc,rolling_4_week_score desc nulls last,rolling_12_week_score desc nulls last,updated_at asc)::int pos,count(*) over()::int total from public.client_competitive_rank_v61 where show_global=true and tutorial_completed=true)x where client_id=v_client;
    select pos into v_league from (select client_id,row_number() over(order by cv_rating desc,rolling_4_week_score desc nulls last,updated_at asc)::int pos from public.client_competitive_rank_v61 where show_global=true and tutorial_completed=true and current_rank_key=v_profile.current_rank_key)x where client_id=v_client;
  end if;
  return jsonb_build_object('version','v61','client_id',v_client,'tutorial_completed',v_profile.tutorial_completed,'current_level',v_profile.current_level,
    'rank',case when v_rule.rank_key is null then null else to_jsonb(v_rule) end,'next_rank',case when v_next.rank_key is null then null else to_jsonb(v_next) end,
    'cv_rating',round(v_profile.cv_rating,0),'rating_peak',round(v_profile.rating_peak,0),'rating_floor',coalesce(v_floor,0),'next_level_rating',v_next_floor,
    'rating_to_next_level',case when v_profile.current_level>=26 then 0 else greatest(0,coalesce(v_next_floor,0)-v_profile.cv_rating) end,
    'level_progress_pct',case when v_profile.current_level=0 then 0 when v_profile.current_level>=26 then 100 else round(100*greatest(0,v_profile.cv_rating-coalesce(v_floor,0))/greatest(1,coalesce(v_next_floor,1)-coalesce(v_floor,0)),1) end,
    'organization_id',v_organization,'lifetime_xp',coalesce((select total_xp from public.client_cv_state where organization_id=v_organization and client_id=v_client),0),'discipline_preview',v_preview,
    'last_discipline_score',v_profile.last_discipline_score,'rolling_4_week_score',v_profile.rolling_4_week_score,'rolling_12_week_score',v_profile.rolling_12_week_score,
    'global_position',v_global,'global_total',v_total,'league_position',v_league,'alias',coalesce(v_profile.competitive_alias,private.cv_alias_v61(v_client)),
    'rank_protected_until',v_profile.rank_protected_until,'legend_since',v_profile.legend_since,
    'tutorial',private.cv_tutorial_status_v61(v_client));
end;$function$;


comment on function private.calculate_cv_score_core_in_org(uuid,uuid,date,text) is
  'F1.M1.S5 E2B tenant-explicit CV Score engine. Formula preserved; all client data sources are Organization-scoped.';
comment on constraint client_cv_state_pkey on public.client_cv_state is
  'F1.M1.S5 E2B canonical CV12 state identity: Organization + Client.';
