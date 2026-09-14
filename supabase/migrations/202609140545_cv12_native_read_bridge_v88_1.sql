-- CV Coach V88.1 — stable CV12 linkage semantics
-- V87 baseline refresh can legitimately move pilot.status away from 'linked'.
-- The durable linkage contract is client_id + linked_at, not the mutable readiness/status field.

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
    and p.linked_at is not null;

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
      and p.linked_at is not null
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
      'engine_version','CV12_NATIVE_READ_BRIDGE_V88_1',
      'source','cv12_legacy',
      'sessions_included',v_legacy_total,
      'read_only',true,
      'link_contract','client_id+linked_at',
      'copied_to_native_workout_sessions',false,
      'auto_publish',false,
      'auto_program_edit',false
    )
  );
end;
$function$;

grant execute on function public.get_client_training_history(integer) to authenticated;

comment on function public.get_client_training_history(integer) is
  'V88.1 client history contract. Linked CV12 history is resolved by client_id + linked_at so baseline status refreshes cannot hide preserved history.';
