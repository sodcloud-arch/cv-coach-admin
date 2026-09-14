-- CV Coach V88 — CV12 native read bridge + reversible pilot unlink
-- Goal: expose preserved CV12 legacy sessions through the existing client training-history contract
-- without copying legacy rows into native workout_sessions or altering automatic programming.

-- Preserve the V59+ native history implementation behind an internal helper exactly once.
do $$
begin
  if to_regprocedure('public.get_client_training_history_native_v88(integer)') is null then
    if to_regprocedure('public.get_client_training_history(integer)') is null then
      raise exception 'Required function public.get_client_training_history(integer) not found';
    end if;
    execute 'alter function public.get_client_training_history(integer) rename to get_client_training_history_native_v88';
  end if;
end $$;

revoke all on function public.get_client_training_history_native_v88(integer) from public;
revoke all on function public.get_client_training_history_native_v88(integer) from anon;
revoke all on function public.get_client_training_history_native_v88(integer) from authenticated;

create or replace function public.get_client_training_history(p_limit integer default 20)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_client_id uuid := auth.uid();
  v_limit integer := greatest(1,least(coalesce(p_limit,20),50));
  v_native jsonb;
  v_sessions jsonb := '[]'::jsonb;
  v_summary jsonb := '{}'::jsonb;
  v_legacy_terminal_30 integer := 0;
  v_legacy_completed_30 integer := 0;
  v_legacy_last timestamptz;
  v_legacy_total integer := 0;
  v_native_last timestamptz;
  v_last timestamptz;
begin
  if v_client_id is null then raise exception 'Authentication required'; end if;

  -- Existing native behavior remains canonical and unchanged.
  v_native := public.get_client_training_history_native_v88(v_limit);

  select
    count(*)::integer,
    count(*) filter (
      where l.completed_at >= now()-interval '30 days'
        and (coalesce(l.counted,false)=true or lower(coalesce(l.state,'')) like '%final%')
    )::integer,
    count(*) filter (
      where l.completed_at >= now()-interval '30 days'
        and (coalesce(l.counted,false)=true or lower(coalesce(l.state,'')) like '%final%')
    )::integer,
    max(l.completed_at)
  into v_legacy_total,v_legacy_terminal_30,v_legacy_completed_30,v_legacy_last
  from public.coach_intelligence_pilots p
  join public.legacy_cv12_sessions_v87 l on l.pilot_id=p.id
  where p.client_id=v_client_id
    and p.source_system='cv12_legacy'
    and p.status='linked';

  -- Merge read-only history. No legacy row is copied into workout_sessions.
  with combined as (
    select j.value as item,
           nullif(j.value->>'sort_at','')::timestamptz as sort_at
    from jsonb_array_elements(coalesce(v_native->'sessions','[]'::jsonb)) j

    union all

    select jsonb_build_object(
      'id',l.id,
      'program_id',null,
      'program_day_id',null,
      'program_name','CV12 · Historial importado',
      'day_name',coalesce(l.title,l.day_label,'Entrenamiento CV12'),
      'day_number',case when substring(coalesce(l.day_label,'') from '([0-9]+)') is null then null else substring(l.day_label from '([0-9]+)')::integer end,
      'started_at',l.completed_at,
      'finished_at',l.completed_at,
      'status',case when coalesce(l.counted,false)=true or lower(coalesce(l.state,'')) like '%final%' then 'completed' else 'partial' end,
      'completion_pct',null,
      'duration_seconds',null,
      'total_volume',null,
      'difficulty_level',l.difficulty,
      'had_pain',null,
      'pain_context',null,
      'client_effort',null,
      'fatigue_score',null,
      'pain_score',null,
      'pain_notes',null,
      'session_notes',l.final_observation,
      'sort_at',l.completed_at,
      'source','cv12_legacy',
      'legacy',true
    ) as item,
    l.completed_at as sort_at
    from public.coach_intelligence_pilots p
    join public.legacy_cv12_sessions_v87 l on l.pilot_id=p.id
    where p.client_id=v_client_id
      and p.source_system='cv12_legacy'
      and p.status='linked'
  ), limited as (
    select item,sort_at from combined order by sort_at desc nulls last limit v_limit
  )
  select coalesce(jsonb_agg(item order by sort_at desc nulls last),'[]'::jsonb)
  into v_sessions
  from limited;

  v_summary := coalesce(v_native->'summary','{}'::jsonb);
  begin
    v_native_last := nullif(v_summary->>'last_workout_at','')::timestamptz;
  exception when others then
    v_native_last := null;
  end;

  v_last := case
    when v_native_last is null then v_legacy_last
    when v_legacy_last is null then v_native_last
    else greatest(v_native_last,v_legacy_last)
  end;

  v_summary := v_summary || jsonb_build_object(
    'terminal_sessions',coalesce((v_summary->>'terminal_sessions')::integer,0)+v_legacy_terminal_30,
    'completed_sessions',coalesce((v_summary->>'completed_sessions')::integer,0)+v_legacy_completed_30,
    'last_workout_at',v_last,
    'legacy_sessions_included',v_legacy_total,
    'legacy_completion_excluded_from_average',true
  );

  return coalesce(v_native,'{}'::jsonb) || jsonb_build_object(
    'summary',v_summary,
    'sessions',v_sessions,
    'legacy_bridge',jsonb_build_object(
      'engine_version','CV12_NATIVE_READ_BRIDGE_V88',
      'source','cv12_legacy',
      'sessions_included',v_legacy_total,
      'read_only',true,
      'copied_to_native_workout_sessions',false,
      'auto_publish',false,
      'auto_program_edit',false
    )
  );
end;
$function$;

grant execute on function public.get_client_training_history(integer) to authenticated;

create or replace function public.unlink_cv12_pilot_native_v88(
  p_pilot_id uuid,
  p_expected_client_id uuid,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_role public.app_role;
  v_refresh jsonb;
begin
  if auth.uid() is null or auth.uid()<>p_actor_id then
    raise exception 'Actor authentication mismatch';
  end if;

  select role into v_role
  from public.profiles
  where id=p_actor_id and status='active'::public.profile_status;

  if v_role is null or v_role not in ('admin'::public.app_role,'coach'::public.app_role) then
    raise exception 'Coach/admin required';
  end if;

  update public.coach_intelligence_pilots
  set client_id=null,
      linked_at=null,
      updated_at=now()
  where id=p_pilot_id
    and client_id=p_expected_client_id
    and source_system='cv12_legacy';

  if not found then
    raise exception 'Pilot/client link not found or changed';
  end if;

  v_refresh := public.refresh_cv12_pilot_baseline_v87(p_pilot_id);

  return jsonb_build_object(
    'ok',true,
    'engine_version','CV12_NATIVE_READ_BRIDGE_V88',
    'pilot_id',p_pilot_id,
    'unlinked_client_id',p_expected_client_id,
    'legacy_history_preserved',true,
    'native_data_deleted',false,
    'baseline',v_refresh,
    'auto_publish',false,
    'auto_program_edit',false
  );
end;
$function$;

grant execute on function public.unlink_cv12_pilot_native_v88(uuid,uuid,uuid) to authenticated;

comment on function public.get_client_training_history(integer) is
  'V88 client history contract. Preserves native history and conditionally merges linked CV12 legacy sessions read-only.';
comment on function public.get_client_training_history_native_v88(integer) is
  'V88 internal native-history implementation preserved from the pre-V88 public contract.';
comment on function public.unlink_cv12_pilot_native_v88(uuid,uuid,uuid) is
  'V88 reversible unlink for CV12 pilot testing/cutover. Never deletes legacy or native training data.';
