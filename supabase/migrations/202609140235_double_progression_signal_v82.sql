-- CV Coach V82 — full-range double progression signal
-- Extends the deterministic signal so reps progress across the whole prescribed range.

create or replace function private.deterministic_progression_signal(p_session_id uuid, p_exercise_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
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

  select * into rc from private.latest_weekly_recovery_context(ws.client_id,coalesce(ws.finished_at,ws.started_at));
  if rc.checkin_id is not null then
    if coalesce(rc.pain_score,0)>=4 then return 'hold_weekly_pain'; end if;
    if coalesce(rc.sleep_hours_avg,99)<5 and coalesce(rc.energy_level,5)<=2 then return 'hold_low_recovery'; end if;
    if coalesce(rc.stress_level,1)>=5 and coalesce(rc.energy_level,5)<=2 then return 'hold_high_stress'; end if;
    if coalesce(rc.soreness_score,0)>=8 and coalesce(rc.energy_level,5)<=2 then return 'hold_low_recovery'; end if;
  end if;

  select count(*)::integer into v_evidence
  from private.training_session_exercise_metrics m
  where m.client_id=c.client_id and m.exercise_id=c.exercise_id
    and m.workout_status in ('completed','partial') and m.done_sets>0
    and coalesce(m.finished_at,m.started_at)<=coalesce(c.finished_at,c.started_at);

  select * into p
  from private.training_session_exercise_metrics m
  where m.client_id=c.client_id and m.exercise_id=c.exercise_id and m.session_id<>c.session_id
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
$$;

comment on function private.deterministic_progression_signal(uuid,uuid) is
  'V82 double progression signal: progresses reps through the full prescribed range before considering load increase.';
