-- CV Coach V85 — Mesocycle Intelligence
-- Adds compact longitudinal memory for AI next-block generation, block-vs-block trends,
-- and an observed-only pilot readiness assessment. Never auto-publishes or mutates live programs.

begin;

create or replace function private.compute_mesocycle_intelligence_v85(
  p_client_id uuid,
  p_target_program_id uuid
) returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
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
  select * into target_program from public.programs where id=p_target_program_id and client_id=p_client_id;
  if not found then
    return jsonb_build_object('engine_version','MESOCYCLE_INTELLIGENCE_V85','available',false,'reason','target_program_not_found');
  end if;

  select apd.source_program_id into v_source_id
  from public.adaptive_program_drafts apd
  where apd.draft_program_id=target_program.id
  order by apd.created_at desc limit 1;

  if v_source_id is null and target_program.status='draft'::public.program_status then
    select p.id into v_source_id
    from public.programs p
    where p.client_id=p_client_id and p.status='active'::public.program_status
    order by p.version desc nulls last,p.updated_at desc limit 1;
  end if;
  v_source_id:=coalesce(v_source_id,target_program.id);

  select * into source_program from public.programs where id=v_source_id;
  if not found then
    return jsonb_build_object('engine_version','MESOCYCLE_INTELLIGENCE_V85','available',false,'reason','source_program_not_found');
  end if;

  select p.* into previous_program
  from public.programs p
  where p.client_id=p_client_id and p.id<>source_program.id
    and coalesce(p.version,0)<coalesce(source_program.version,2147483647)
    and exists(select 1 from public.workout_sessions ws where ws.program_id=p.id and ws.client_id=p_client_id and ws.status in ('completed'::public.workout_session_status,'partial'::public.workout_session_status))
  order by p.version desc nulls last,p.updated_at desc limit 1;
  v_previous_id:=previous_program.id;

  v_adaptation:=private.compute_training_adaptation_v83(p_client_id,source_program.id,now());

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
  where ws.client_id=p_client_id and ws.program_id=source_program.id
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
    where ws.client_id=p_client_id and ws.program_id=previous_program.id
      and ws.status in ('completed'::public.workout_session_status,'partial'::public.workout_session_status);
  else
    v_previous_summary:='{}'::jsonb;
  end if;

  with m as (
    select tm.*
    from private.training_session_exercise_metrics tm
    join public.workout_sessions ws on ws.id=tm.session_id
    where tm.client_id=p_client_id and ws.program_id=source_program.id
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
  where ps.client_id=p_client_id and (ws.program_id=source_program.id or ws.id is null)
    and ps.created_at>=coalesce(source_program.published_at,source_program.created_at,now()-interval '16 weeks');

  v_memory_quality:=case
    when coalesce((v_current_summary->>'sessions')::integer,0)>=6 then 'high'
    when coalesce((v_current_summary->>'sessions')::integer,0)>=3 then 'medium'
    else 'low'
  end;

  return jsonb_build_object(
    'engine_version','MESOCYCLE_INTELLIGENCE_V85','available',true,'client_id',p_client_id,
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
$$;

create or replace function public.get_mesocycle_intelligence_v85(
  p_actor_id uuid,
  p_client_id uuid,
  p_program_id uuid
) returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare
  v_role public.app_role;
  v_request_role text:=coalesce(auth.role(),'');
begin
  if v_request_role<>'service_role' and (auth.uid() is null or auth.uid()<>p_actor_id) then raise exception 'Actor authentication mismatch'; end if;
  select role into v_role from public.profiles where id=p_actor_id and status='active'::public.profile_status;
  if v_role is null or v_role not in ('admin'::public.app_role,'coach'::public.app_role) then raise exception 'Coach/admin role required'; end if;
  if v_role='coach'::public.app_role and not exists(select 1 from public.coach_clients where coach_id=p_actor_id and client_id=p_client_id and status='active'::public.coach_client_status) then raise exception 'Coach is not assigned to this client'; end if;
  return private.compute_mesocycle_intelligence_v85(p_client_id,p_program_id);
end;
$$;

create or replace function public.get_client_training_trends_v85(
  p_actor_id uuid,
  p_client_id uuid,
  p_weeks integer default 12
) returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare
  v84 jsonb;
  v_program uuid;
  v_memory jsonb;
begin
  v84:=public.get_client_training_trends_v84(p_actor_id,p_client_id,p_weeks);
  select p.id into v_program from public.programs p where p.client_id=p_client_id and p.status='active'::public.program_status order by p.version desc nulls last,p.updated_at desc limit 1;
  if v_program is null then
    return v84||jsonb_build_object('engine_version','TRAINING_TRENDS_V85','mesocycle_intelligence',jsonb_build_object('available',false,'reason','no_active_program'));
  end if;
  v_memory:=public.get_mesocycle_intelligence_v85(p_actor_id,p_client_id,v_program);
  return v84||jsonb_build_object(
    'engine_version','TRAINING_TRENDS_V85',
    'mesocycle_intelligence',v_memory,
    'block_comparison',coalesce(v_memory->'block_comparison','{}'::jsonb),
    'exercise_effectiveness',coalesce(v_memory->'exercise_effectiveness','[]'::jsonb)
  );
end;
$$;

create or replace function public.get_v85_pilot_readiness(
  p_actor_id uuid,
  p_client_id uuid default null
) returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare
  v_role public.app_role;
  v_rows jsonb;
begin
  if auth.uid() is null or auth.uid()<>p_actor_id then raise exception 'Actor authentication mismatch'; end if;
  select role into v_role from public.profiles where id=p_actor_id and status='active'::public.profile_status;
  if v_role is null or v_role not in ('admin'::public.app_role,'coach'::public.app_role) then raise exception 'Coach/admin role required'; end if;

  with clients as (
    select p.id client_id
    from public.profiles p
    where p.role='client'::public.app_role and p.status='active'::public.profile_status
      and (p_client_id is null or p.id=p_client_id)
      and (v_role='admin'::public.app_role or exists(select 1 from public.coach_clients cc where cc.coach_id=p_actor_id and cc.client_id=p.id and cc.status='active'::public.coach_client_status))
  ), facts as (
    select c.client_id,
      (select p.id from public.programs p where p.client_id=c.client_id and p.status='active'::public.program_status order by p.version desc nulls last,p.updated_at desc limit 1) active_program_id,
      (select count(*) from public.programs p where p.client_id=c.client_id and p.status='draft'::public.program_status)::integer draft_programs,
      (select count(*) from public.workout_sessions ws where ws.client_id=c.client_id and ws.status in ('completed'::public.workout_session_status,'partial'::public.workout_session_status) and ws.started_at>=now()-interval '42 days')::integer recent_sessions,
      (select count(*) from (
        select tm.exercise_id from private.training_session_exercise_metrics tm
        where tm.client_id=c.client_id and tm.done_sets>0 and coalesce(tm.finished_at,tm.started_at)>=now()-interval '84 days'
        group by tm.exercise_id having count(*)>=2
      ) q)::integer evidence_exercises,
      (select max(wc.submitted_at) from public.weekly_checkins wc where wc.client_id=c.client_id) latest_checkin_at
    from clients c
  ), scored as (
    select f.*,
      case when f.active_program_id is null then 'no_active_program'
           when f.draft_programs>0 then 'draft_in_progress'
           when f.recent_sessions<3 or f.evidence_exercises<2 then 'collect_more_data'
           else 'ready_observed_pilot' end pilot_status,
      (f.active_program_id is not null and f.draft_programs=0 and f.recent_sessions>=3 and f.evidence_exercises>=2) ready,
      jsonb_strip_nulls(jsonb_build_object(
        'active_program',case when f.active_program_id is null then 'required' else null end,
        'draft_program',case when f.draft_programs>0 then 'finish_or_discard_existing_draft_first' else null end,
        'recent_sessions',case when f.recent_sessions<3 then 'need_at_least_3_sessions_in_42d' else null end,
        'exercise_evidence',case when f.evidence_exercises<2 then 'need_at_least_2_exercises_with_2_exposures' else null end
      )) blockers
    from facts f
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'client_id',s.client_id,'active_program_id',s.active_program_id,'draft_programs',s.draft_programs,
    'recent_sessions_42d',s.recent_sessions,'evidence_exercises_84d',s.evidence_exercises,
    'latest_checkin_at',s.latest_checkin_at,'ready',s.ready,'pilot_status',s.pilot_status,'blockers',s.blockers,
    'mode','observed_only','mutates_client',false,'auto_publish',false
  ) order by s.ready desc,s.recent_sessions desc),'[]'::jsonb) into v_rows from scored s;

  return jsonb_build_object('engine_version','V85_PILOT_READINESS','observed_only',true,'clients',v_rows);
end;
$$;

create or replace function public.prepare_ai_program_generation(
  p_actor_id uuid,
  p_client_id uuid,
  p_program_id uuid default null,
  p_scope text default 'program',
  p_target_day_number integer default null,
  p_idempotency_key text default null
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_request_role text:=coalesce(auth.role(),'');
  v_request_user uuid:=auth.uid();
  v_program public.programs%rowtype;
  v_generation public.ai_program_generations%rowtype;
  v_key text:=nullif(pg_catalog.btrim(p_idempotency_key),'');
  v_context jsonb;
  v_onboarding jsonb;
  v_weekly jsonb;
  v_catalog jsonb;
  v_current_program jsonb;
  v_client_profile jsonb;
  v_mesocycle jsonb;
  v_constraints jsonb;
  v_exposures jsonb;
  v_time_learning jsonb;
begin
  if p_actor_id is null or p_client_id is null then raise exception 'actor_id and client_id are required'; end if;
  if p_scope not in ('program','day') then raise exception 'scope must be program or day'; end if;
  if p_scope='day' and (p_target_day_number is null or p_target_day_number<1) then raise exception 'target_day_number is required for day scope'; end if;
  if v_key is null then raise exception 'idempotency_key is required'; end if;
  if v_request_role<>'service_role' and (v_request_user is null or v_request_user<>p_actor_id) then raise exception 'actor identity mismatch'; end if;

  if not exists(select 1 from public.profiles a where a.id=p_actor_id and a.status='active'::public.profile_status and a.role='admin'::public.app_role)
     and not exists(select 1 from public.coach_clients cc join public.profiles a on a.id=cc.coach_id where cc.coach_id=p_actor_id and cc.client_id=p_client_id and cc.status='active'::public.coach_client_status and a.status='active'::public.profile_status and a.role in ('coach'::public.app_role,'admin'::public.app_role)) then
    raise exception 'Forbidden';
  end if;

  if p_program_id is null then
    select p.* into v_program from public.programs p where p.client_id=p_client_id and p.status='draft'::public.program_status order by p.updated_at desc,p.created_at desc limit 1;
  else
    select p.* into v_program from public.programs p where p.id=p_program_id and p.client_id=p_client_id;
  end if;
  if v_program.id is null then raise exception 'Draft program not found'; end if;
  if v_program.status<>'draft'::public.program_status then raise exception 'AI generation can only target draft programs'; end if;

  select g.* into v_generation from public.ai_program_generations g where g.idempotency_key=v_key limit 1;
  if v_generation.id is not null then
    if v_generation.program_id<>v_program.id or v_generation.client_id<>p_client_id or v_generation.coach_id<>p_actor_id or v_generation.scope<>p_scope or coalesce(v_generation.target_day_number,0)<>coalesce(p_target_day_number,0) then
      raise exception 'idempotency_key already used for another generation';
    end if;
    return jsonb_build_object('generation_id',v_generation.id,'program_id',v_generation.program_id,'client_id',v_generation.client_id,'scope',v_generation.scope,'target_day_number',v_generation.target_day_number,'status',v_generation.status,'engine_version',v_generation.engine_version,'context',v_generation.input_snapshot);
  end if;

  select coalesce(jsonb_object_agg(r.question_key,r.response_value),'{}'::jsonb) into v_onboarding from public.onboarding_responses r where r.client_id=p_client_id;
  select coalesce(to_jsonb(w),'{}'::jsonb) into v_weekly from (select wc.* from public.weekly_checkins wc where wc.client_id=p_client_id order by wc.submitted_at desc limit 1) w;
  select coalesce(to_jsonb(cp),'{}'::jsonb) into v_client_profile from public.client_profiles cp where cp.client_id=p_client_id;
  select coalesce(to_jsonb(t),'{}'::jsonb) into v_time_learning from private.get_client_time_learning(p_client_id) t;
  select coalesce(jsonb_agg(jsonb_build_object('constraint_code',c.constraint_code,'label',cat.label,'region',cat.region,'action',c.action,'note',c.note)),'[]'::jsonb)
    into v_constraints from public.client_training_constraints c join public.training_constraint_catalog cat on cat.code=c.constraint_code
    where c.client_id=p_client_id and c.active=true and (c.valid_until is null or c.valid_until>=current_date);
  select coalesce(jsonb_agg(jsonb_build_object('exercise_id',e.exercise_id,'constraint_code',e.constraint_code,'exposure_level',e.exposure_level)),'[]'::jsonb)
    into v_exposures from public.exercise_mechanical_exposures e;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',e.id,'name',e.name,'primary_muscle',e.primary_muscle,'equipment',e.equipment,'movement_pattern',e.movement_pattern,
    'difficulty',e.difficulty,'default_tempo',e.default_tempo,'default_rest_sec',e.default_rest_sec,'prescription_unit',e.prescription_unit
  ) order by e.name),'[]'::jsonb)
  into v_catalog from public.exercises e where e.active=true;

  select jsonb_build_object(
    'program',to_jsonb(p),
    'days',coalesce((select jsonb_agg(jsonb_build_object(
      'id',pd.id,'day_number',pd.day_number,'name',pd.name,'focus',pd.focus,'estimated_minutes',pd.estimated_minutes,'notes',pd.notes,
      'exercises',coalesce((select jsonb_agg(jsonb_build_object(
        'id',pe.id,'exercise_id',pe.exercise_id,'exercise_order',pe.exercise_order,'target_sets',pe.target_sets,
        'rep_min',pe.rep_min,'rep_max',pe.rep_max,'prescription_unit',pe.prescription_unit,'rir_target',pe.rir_target,'tempo',pe.tempo,
        'rest_seconds',pe.rest_seconds,'load_strategy',pe.load_strategy,'coach_notes',pe.coach_notes,'client_notes',pe.client_notes,
        'allow_substitution',pe.allow_substitution,'initial_weight_kg',pe.initial_weight_kg
      ) order by pe.exercise_order) from public.program_exercises pe where pe.program_day_id=pd.id and pe.active=true),'[]'::jsonb)
    ) order by pd.day_number) from public.program_days pd where pd.program_id=p.id),'[]'::jsonb)
  ) into v_current_program from public.programs p where p.id=v_program.id;

  v_mesocycle:=private.compute_mesocycle_intelligence_v85(p_client_id,v_program.id);

  v_context:=jsonb_build_object(
    'client_profile',coalesce(v_client_profile,'{}'::jsonb),
    'onboarding',coalesce(v_onboarding,'{}'::jsonb),
    'training_preferences',coalesce((select to_jsonb(tp) from public.client_training_preferences tp where tp.client_id=p_client_id),'{}'::jsonb),
    'schedule_preferences',coalesce((select to_jsonb(sp) from public.client_training_schedule_preferences sp where sp.client_id=p_client_id),'{}'::jsonb),
    'training_constraints',coalesce(v_constraints,'[]'::jsonb),
    'time_learning',coalesce(v_time_learning,'{}'::jsonb),
    'exercise_mechanical_exposures',coalesce(v_exposures,'[]'::jsonb),
    'latest_weekly_checkin',coalesce(v_weekly,'{}'::jsonb),
    'mesocycle_intelligence',coalesce(v_mesocycle,'{}'::jsonb),
    'current_draft',coalesce(v_current_program,'{}'::jsonb),
    'exercise_catalog',coalesce(v_catalog,'[]'::jsonb),
    'guardrails',jsonb_build_object('draft_only',true,'coach_review_required',true,'auto_publish',false,'blocking_conflicts_must_be_empty',true,'mesocycle_memory_is_evidence',true)
  );

  insert into public.ai_program_generations(program_id,client_id,coach_id,scope,target_day_number,status,engine_version,idempotency_key,input_snapshot)
  values(v_program.id,p_client_id,p_actor_id,p_scope,p_target_day_number,'prepared','cv-coach-ai-program-v85',v_key,v_context)
  returning * into v_generation;

  return jsonb_build_object('generation_id',v_generation.id,'program_id',v_generation.program_id,'client_id',v_generation.client_id,'scope',v_generation.scope,'target_day_number',v_generation.target_day_number,'status',v_generation.status,'engine_version',v_generation.engine_version,'context',v_generation.input_snapshot);
end;
$$;

revoke all on function public.get_mesocycle_intelligence_v85(uuid,uuid,uuid) from public,anon;
revoke all on function public.get_client_training_trends_v85(uuid,uuid,integer) from public,anon;
revoke all on function public.get_v85_pilot_readiness(uuid,uuid) from public,anon;
grant execute on function public.get_mesocycle_intelligence_v85(uuid,uuid,uuid) to authenticated,service_role;
grant execute on function public.get_client_training_trends_v85(uuid,uuid,integer) to authenticated,service_role;
grant execute on function public.get_v85_pilot_readiness(uuid,uuid) to authenticated,service_role;

commit;
