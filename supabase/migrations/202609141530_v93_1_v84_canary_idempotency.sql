-- CV Coach V93.1 — V84 production canary idempotency hardening
-- Scope: synthetic production-v76 canary client only.
-- Any temporary status change lives inside the rollback-isolated E2E subtransaction.

create or replace function public.run_adaptive_programming_e2e_v84(p_run_id text default null)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_client uuid;
  v_actor uuid;
  v_program uuid;
  v_day uuid;
  v_pe public.program_exercises%rowtype;
  v_exercise uuid;
  v_source uuid;
  v_source_se uuid;
  v_suggestion uuid;
  v_next uuid;
  v_next_se uuid;
  v_set uuid;
  v_rec jsonb;
  v_review jsonb;
  v_trends jsonb;
  v_status text;
  v_target integer;
  v_result jsonb;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service_role required';
  end if;

  begin
    select client_id into v_client
    from public.cv_canary_clients
    where label='production-v76' and enabled=true
    limit 1;
    if v_client is null then raise exception 'V84 canary client missing'; end if;

    select id into v_actor
    from public.profiles
    where role='admin'::public.app_role and status='active'::public.profile_status
    order by created_at
    limit 1;
    if v_actor is null then raise exception 'V84 admin actor missing'; end if;

    select id into v_program
    from public.programs
    where client_id=v_client and status='active'::public.program_status
    order by updated_at desc
    limit 1;
    if v_program is null then raise exception 'V84 active canary program missing'; end if;

    select id into v_day
    from public.program_days
    where program_id=v_program
    order by day_number
    limit 1;

    select pe.* into v_pe
    from public.program_exercises pe
    where pe.program_day_id=v_day and pe.active=true
    order by pe.exercise_order
    limit 1;
    if v_pe.id is null then raise exception 'V84 canary exercise missing'; end if;
    v_exercise := v_pe.exercise_id;

    -- Serialize V84 tests for the exact synthetic client/day scope.
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('cv-v84-canary:'||v_client::text||':'||v_day::text, 0)
    );

    -- A browser/previous canary may legitimately leave the synthetic account with
    -- one in-progress session. Temporarily neutralize only that exact canary scope.
    -- The enclosing exception block deliberately rolls this UPDATE back before return,
    -- so the pre-test production state is restored byte-for-byte at transaction level.
    update public.workout_sessions
    set status='abandoned'::public.workout_session_status,
        finished_at=coalesce(finished_at,now()),
        updated_at=now()
    where client_id=v_client
      and program_day_id=v_day
      and status='in_progress'::public.workout_session_status;

    insert into public.workout_sessions(
      client_id,program_id,program_day_id,started_at,finished_at,status,
      completion_pct,duration_seconds,client_effort,fatigue_score,pain_score,
      difficulty_level,had_pain,session_notes
    ) values(
      v_client,v_program,v_day,now()-interval '2 minutes',now()-interval '1 minute',
      'completed'::public.workout_session_status,100,60,6,3,0,3,false,
      'CV_V84_E2E_SOURCE '||coalesce(p_run_id,'local')
    ) returning id into v_source;

    insert into public.session_exercises(
      workout_session_id,program_exercise_id,exercise_id,exercise_order,status,
      target_sets_snapshot,rep_min_snapshot,rep_max_snapshot,rir_target_snapshot,
      rest_seconds_snapshot,allow_substitution_snapshot,prescription_unit_snapshot
    ) values(
      v_source,v_pe.id,v_exercise,1,'completed'::public.session_exercise_status,
      2,30,45,2,60,false,'seconds'
    ) returning id into v_source_se;

    insert into public.set_logs(session_exercise_id,set_number,duration_seconds,rir,completed,completed_at)
    values
      (v_source_se,1,30,2,true,now()-interval '70 seconds'),
      (v_source_se,2,30,2,true,now()-interval '65 seconds');

    v_rec := private.progression_recommendation_v83(v_source,v_exercise);
    if coalesce(v_rec->>'action','') <> 'build_time'
       or (v_rec->>'suggested_duration_seconds')::integer <> 35 then
      raise exception 'V84 E2E recommendation mismatch: %',v_rec;
    end if;

    insert into public.progression_suggestions(
      client_id,exercise_id,source_session_id,previous_duration_seconds,
      suggested_duration_seconds,reason_code,reason_text,confidence,status,
      action,engine_version,evidence_sessions,confidence_band,evidence,auto_generated
    ) values(
      v_client,v_exercise,v_source,30,35,'v84_e2e','V84 isolated progression E2E',
      95,'pending'::public.progression_status,'build_time','PROGRESSION_ENGINE_V83',
      1,'high',v_rec,true
    ) returning id into v_suggestion;

    perform pg_catalog.set_config('request.jwt.claim.sub',v_actor::text,true);
    v_review := public.review_progression_suggestion_v83(
      v_actor,v_suggestion,'modified',null,null,null,35,
      'V84 E2E conservative modification'
    );
    if coalesce(v_review->>'status','') <> 'modified' then
      raise exception 'V84 E2E review failed';
    end if;
    perform pg_catalog.set_config('cv.v83_review','',true);

    insert into public.workout_sessions(client_id,program_id,program_day_id,status,session_notes)
    values(
      v_client,v_program,v_day,'in_progress'::public.workout_session_status,
      'CV_V84_E2E_NEXT '||coalesce(p_run_id,'local')
    ) returning id into v_next;

    insert into public.session_exercises(
      workout_session_id,program_exercise_id,exercise_id,exercise_order,status,
      target_sets_snapshot,rep_min_snapshot,rep_max_snapshot,rir_target_snapshot,
      rest_seconds_snapshot,allow_substitution_snapshot,prescription_unit_snapshot
    ) values(
      v_next,v_pe.id,v_exercise,1,'pending'::public.session_exercise_status,
      2,30,45,2,60,false,'seconds'
    ) returning id into v_next_se;

    insert into public.set_logs(session_exercise_id,set_number,completed)
    values(v_next_se,1,false)
    returning id into v_set;

    select status::text into v_status
    from public.progression_suggestions
    where id=v_suggestion;

    select suggested_duration_seconds into v_target
    from public.set_logs
    where id=v_set;

    if v_status <> 'applied' or v_target <> 35 then
      raise exception 'V84 E2E next-session application failed: status %, target %',v_status,v_target;
    end if;

    v_trends := public.get_client_training_trends_v84(v_actor,v_client,12);
    if jsonb_array_length(coalesce(v_trends->'exercise_history','[]'::jsonb)) < 1 then
      raise exception 'V84 E2E longitudinal history missing';
    end if;

    v_result := jsonb_build_object(
      'ok',true,
      'contract','CV_V84_ADAPTIVE_PROGRAMMING_E2E_OK',
      'run_id',p_run_id,
      'recommendation_action',v_rec->>'action',
      'review_status',v_review->>'status',
      'next_session_progression_status',v_status,
      'suggested_duration_seconds',v_target,
      'history_visible',true,
      'rollback_isolated',true,
      'stale_in_progress_tolerated',true
    );

    raise exception using errcode='CV084',message='rollback_v84_e2e';
  exception when sqlstate 'CV084' then
    return v_result;
  end;
end;
$$;

comment on function public.run_adaptive_programming_e2e_v84(text) is
  'V93.1 hardening of the V84 service-role canary. Serializes the synthetic client/day, temporarily neutralizes pre-existing in-progress canary state, and rolls every E2E mutation back before returning.';

revoke all on function public.run_adaptive_programming_e2e_v84(text) from public,anon,authenticated;
grant execute on function public.run_adaptive_programming_e2e_v84(text) to service_role;
