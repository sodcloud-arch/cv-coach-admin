-- CV Coach V80
-- Authoritative server-side verification for the current simplified workout feedback model.
-- Restricted to the configured production canary client; normal clients cannot use it.

create or replace function public.verify_production_canary_v80(
  p_run_id text,
  p_expected_weight numeric,
  p_expected_reps integer
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_canary_client uuid;
  v_run public.cv_canary_runs%rowtype;
  v_session public.workout_sessions%rowtype;
  v_set_count integer := 0;
  v_outbox_count integer := 0;
  v_ficha_visible boolean := false;
  v_report_visible boolean := false;
  v_after jsonb;
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;

  select c.client_id
    into v_canary_client
  from public.cv_canary_clients c
  where c.label = 'production-v76'
    and c.enabled = true
  limit 1;

  if v_canary_client is null or v_uid <> v_canary_client then
    raise exception 'Production canary client required';
  end if;

  select r.*
    into v_run
  from public.cv_canary_runs r
  where r.run_id = p_run_id
    and r.client_id = v_uid;

  if not found then raise exception 'Canary run not found'; end if;
  if v_run.status <> 'claimed' or v_run.session_id is null then
    raise exception 'Canary run is not claim-ready';
  end if;

  select ws.*
    into v_session
  from public.workout_sessions ws
  where ws.id = v_run.session_id
    and ws.client_id = v_uid;

  if not found then raise exception 'Canary session missing'; end if;
  if v_session.status::text <> 'abandoned' then
    raise exception 'Unexpected terminal status: %', v_session.status;
  end if;
  if not (coalesce(v_session.completion_pct,0) > 0 and coalesce(v_session.completion_pct,0) < 50) then
    raise exception 'Unexpected completion percentage: %', v_session.completion_pct;
  end if;
  if v_session.finished_at is null or coalesce(v_session.duration_seconds,-1) < 0 then
    raise exception 'Terminal metrics missing';
  end if;

  -- Feedback V2 canonical contract:
  -- difficulty 3 -> legacy client_effort 6, fatigue_score NULL, no pain -> pain_score 0.
  if v_session.difficulty_level is distinct from 3
     or v_session.had_pain is distinct from false
     or v_session.client_effort is distinct from 6
     or v_session.fatigue_score is not null
     or v_session.pain_score is distinct from 0 then
    raise exception 'Feedback V2 mismatch';
  end if;

  if v_session.session_notes is distinct from ('CV_CANARY_V76 run=' || p_run_id) then
    raise exception 'Canary marker missing';
  end if;

  select count(*)::integer
    into v_set_count
  from public.set_logs sl
  join public.session_exercises se on se.id = sl.session_exercise_id
  where se.workout_session_id = v_run.session_id
    and sl.completed = true
    and sl.weight_kg = p_expected_weight
    and sl.reps = p_expected_reps;

  if v_set_count <> 1 then
    raise exception 'Expected exactly one completed canary set, got %', v_set_count;
  end if;

  select exists(
    select 1 from (
      select ws.id
      from public.workout_sessions ws
      where ws.client_id = v_uid
      order by ws.started_at desc
      limit 10
    ) x where x.id = v_run.session_id
  ) into v_ficha_visible;

  select exists(
    select 1 from (
      select ws.id
      from public.workout_sessions ws
      where ws.client_id = v_uid
      order by ws.started_at desc
      limit 200
    ) x where x.id = v_run.session_id
  ) into v_report_visible;

  if not v_ficha_visible then raise exception 'Coach ficha missing session'; end if;
  if not v_report_visible then raise exception 'Coach report missing session'; end if;

  select count(*)::integer
    into v_outbox_count
  from public.event_outbox eo
  where eo.client_id = v_uid
    and eo.aggregate_id = v_run.session_id;

  if v_outbox_count <> 0 then raise exception 'Canary outbox not suppressed'; end if;

  select jsonb_build_object(
    'xp_total', coalesce((
      select sum(case when x.reversed_at is null then x.amount else 0 end)
      from public.xp_ledger x where x.client_id = v_uid
    ),0),
    'credit_total', coalesce((
      select sum(case
        when c.transaction_type::text = 'earned' then abs(c.amount)
        when c.transaction_type::text = 'spent' then -abs(c.amount)
        else c.amount end)
      from public.credit_ledger c where c.client_id = v_uid
    ),0),
    'xp_ids', coalesce((
      select jsonb_agg(x.id order by x.id)
      from public.xp_ledger x where x.client_id = v_uid
    ),'[]'::jsonb),
    'credit_ids', coalesce((
      select jsonb_agg(c.id order by c.id)
      from public.credit_ledger c where c.client_id = v_uid
    ),'[]'::jsonb),
    'cv_state', (
      select to_jsonb(s) from (
        select cs.client_id,cs.current_level,cs.total_xp,cs.credit_balance,cs.current_cv_score,cs.dynamic_state
        from public.client_cv_state cs where cs.client_id = v_uid
      ) s
    ),
    'missions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',m.id,'progress',m.progress,'target',m.target,'status',m.status,'completed_at',m.completed_at
      ) order by m.id)
      from public.client_missions m where m.client_id = v_uid
    ),'[]'::jsonb),
    'achievement_ids', coalesce((
      select jsonb_agg(a.id order by a.id)
      from public.client_achievements a where a.client_id = v_uid
    ),'[]'::jsonb),
    'snapshot_ids', coalesce((
      select jsonb_agg(s.id order by s.id)
      from public.cv_score_snapshots s where s.client_id = v_uid
    ),'[]'::jsonb),
    'progressions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',p.id,'source_session_id',p.source_session_id,'status',p.status,
        'reviewed_by',p.reviewed_by,'reviewed_at',p.reviewed_at
      ) order by p.id)
      from public.progression_suggestions p where p.client_id = v_uid
    ),'[]'::jsonb),
    'level_ids', coalesce((
      select jsonb_agg(l.id order by l.id)
      from public.client_level_history l where l.client_id = v_uid
    ),'[]'::jsonb),
    'notification_ids', coalesce((
      select jsonb_agg(n.id order by n.id)
      from public.notifications n where n.user_id = v_uid
    ),'[]'::jsonb)
  ) into v_after;

  if v_after is distinct from v_run.baseline then
    raise exception 'Canary state drift before cleanup';
  end if;

  return jsonb_build_object(
    'ok',true,
    'run_id',p_run_id,
    'session_id',v_run.session_id,
    'athlete_terminal_ok',true,
    'coach_ficha_visible',v_ficha_visible,
    'coach_report_visible',v_report_visible,
    'completed_set_ok',true,
    'outbox_suppressed',true,
    'state_unchanged',true,
    'feedback_v2_ok',true,
    'completion_pct',v_session.completion_pct
  );
end;
$function$;

revoke all on function public.verify_production_canary_v80(text,numeric,integer) from public;
revoke all on function public.verify_production_canary_v80(text,numeric,integer) from anon;
grant execute on function public.verify_production_canary_v80(text,numeric,integer) to authenticated;
