-- F1.M2.S1 follow-up — tenant-explicit client history read
-- Prevents a selected multi-tenant client from aggregating workout history across Organizations.

create or replace function public.get_client_training_history_in_org_v1(
  p_organization_id uuid,
  p_limit integer default 20
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_client_id uuid:=auth.uid();
  v_limit integer:=greatest(1,least(coalesce(p_limit,20),50));
  v_summary jsonb;
  v_sessions jsonb;
  v_records jsonb;
  v_duration_records jsonb;
  v_native jsonb;
  v_legacy_terminal_30 integer:=0;
  v_legacy_completed_30 integer:=0;
  v_legacy_last timestamptz;
  v_legacy_total integer:=0;
  v_native_last timestamptz;
  v_last timestamptz;
begin
  if v_client_id is null then
    raise exception 'Authentication required';
  end if;
  if p_organization_id is null then
    raise exception 'organization_id is required';
  end if;

  if not exists(
    select 1
    from public.organization_members om
    join public.organizations o on o.id=om.organization_id
    join public.clients c
      on c.organization_id=om.organization_id
     and c.user_id=om.user_id
    join public.profiles p on p.id=om.user_id
    where om.organization_id=p_organization_id
      and om.user_id=v_client_id
      and om.role='client'::public.organization_member_role
      and om.status='active'::public.organization_member_status
      and o.status in ('trial'::public.organization_status,'active'::public.organization_status)
      and c.status<>'archived'::public.client_status
      and p.role='client'::public.app_role
      and p.status='active'::public.profile_status
  ) then
    raise exception 'Active client membership required for organization';
  end if;

  select jsonb_build_object(
    'window_days',30,
    'terminal_sessions',count(*) filter(where ws.status::text in ('completed','partial','abandoned')),
    'completed_sessions',count(*) filter(where ws.status='completed'::public.workout_session_status),
    'partial_sessions',count(*) filter(where ws.status='partial'::public.workout_session_status),
    'abandoned_sessions',count(*) filter(where ws.status='abandoned'::public.workout_session_status),
    'total_volume',coalesce(sum(ws.total_volume) filter(where ws.total_volume is not null),0),
    'avg_completion',round(avg(ws.completion_pct) filter(where ws.completion_pct is not null),1),
    'last_workout_at',max(coalesce(ws.finished_at,ws.started_at))
  )
  into v_summary
  from public.workout_sessions ws
  where ws.organization_id=p_organization_id
    and ws.client_id=v_client_id
    and ws.status::text in ('completed','partial','abandoned')
    and coalesce(ws.finished_at,ws.started_at)>=now()-interval '30 days';

  select coalesce(jsonb_agg(to_jsonb(x) order by x.sort_at desc),'[]'::jsonb)
  into v_sessions
  from (
    select
      ws.id,ws.organization_id,ws.program_id,ws.program_day_id,
      pr.name as program_name,pd.name as day_name,pd.day_number,
      ws.started_at,ws.finished_at,ws.status::text as status,ws.completion_pct,
      ws.duration_seconds,ws.total_volume,ws.difficulty_level,ws.had_pain,
      ws.pain_context,ws.client_effort,ws.fatigue_score,ws.pain_score,
      ws.pain_notes,ws.session_notes,coalesce(ws.finished_at,ws.started_at) as sort_at,
      'native'::text as source,false as legacy
    from public.workout_sessions ws
    left join public.programs pr
      on pr.organization_id=ws.organization_id
     and pr.id=ws.program_id
    left join public.program_days pd
      on pd.organization_id=ws.organization_id
     and pd.id=ws.program_day_id
    where ws.organization_id=p_organization_id
      and ws.client_id=v_client_id
      and ws.status::text in ('completed','partial','abandoned')
    order by coalesce(ws.finished_at,ws.started_at) desc
    limit v_limit
  ) x;

  with completed_sets as (
    select
      se.exercise_id,e.name as exercise_name,sl.weight_kg,sl.reps,sl.rir,
      coalesce(sl.completed_at,sl.updated_at,sl.created_at) as performed_at,
      ws.id as session_id
    from public.set_logs sl
    join public.session_exercises se
      on se.organization_id=sl.organization_id
     and se.id=sl.session_exercise_id
    join public.workout_sessions ws
      on ws.organization_id=se.organization_id
     and ws.id=se.workout_session_id
    join public.exercises e on e.id=se.exercise_id
    where ws.organization_id=p_organization_id
      and ws.client_id=v_client_id
      and sl.completed=true
      and sl.reps is not null and sl.reps>0
      and coalesce(se.prescription_unit_snapshot,e.prescription_unit,'reps')='reps'
      and ws.status::text in ('completed','partial','abandoned')
  ),
  best_weight as (
    select distinct on (exercise_id)
      exercise_id,weight_kg as best_weight_kg,reps as reps_at_best_weight,
      rir as rir_at_best_weight,performed_at as best_weight_at,
      session_id as best_weight_session_id
    from completed_sets
    where weight_kg is not null and weight_kg>0
    order by exercise_id,weight_kg desc,reps desc,performed_at desc
  ),
  stats as (
    select exercise_id,max(exercise_name) as exercise_name,max(reps) as max_reps,
           count(*)::integer as completed_sets,max(performed_at) as last_performed_at
    from completed_sets
    group by exercise_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'exercise_id',s.exercise_id,'exercise_name',s.exercise_name,'prescription_unit','reps',
    'best_weight_kg',bw.best_weight_kg,'reps_at_best_weight',bw.reps_at_best_weight,
    'rir_at_best_weight',bw.rir_at_best_weight,'best_weight_at',bw.best_weight_at,
    'max_reps',s.max_reps,'completed_sets',s.completed_sets,
    'last_performed_at',s.last_performed_at
  ) order by s.last_performed_at desc),'[]'::jsonb)
  into v_records
  from stats s
  left join best_weight bw on bw.exercise_id=s.exercise_id;

  with timed_sets as (
    select
      se.exercise_id,e.name as exercise_name,sl.duration_seconds,sl.rir,
      coalesce(sl.completed_at,sl.updated_at,sl.created_at) as performed_at,
      ws.id as session_id
    from public.set_logs sl
    join public.session_exercises se
      on se.organization_id=sl.organization_id
     and se.id=sl.session_exercise_id
    join public.workout_sessions ws
      on ws.organization_id=se.organization_id
     and ws.id=se.workout_session_id
    join public.exercises e on e.id=se.exercise_id
    where ws.organization_id=p_organization_id
      and ws.client_id=v_client_id
      and sl.completed=true
      and sl.duration_seconds is not null and sl.duration_seconds>0
      and coalesce(se.prescription_unit_snapshot,e.prescription_unit,'reps')='seconds'
      and ws.status::text in ('completed','partial','abandoned')
  ),
  timed_stats as (
    select exercise_id,max(exercise_name) as exercise_name,
           max(duration_seconds) as max_duration_seconds,
           count(*)::integer as completed_sets,max(performed_at) as last_performed_at
    from timed_sets
    group by exercise_id
  ),
  best_duration as (
    select distinct on (exercise_id)
      exercise_id,duration_seconds as best_duration_seconds,
      rir as rir_at_best_duration,performed_at as best_duration_at,
      session_id as best_duration_session_id
    from timed_sets
    order by exercise_id,duration_seconds desc,performed_at desc
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'exercise_id',s.exercise_id,'exercise_name',s.exercise_name,'prescription_unit','seconds',
    'max_duration_seconds',s.max_duration_seconds,
    'best_duration_seconds',bd.best_duration_seconds,
    'rir_at_best_duration',bd.rir_at_best_duration,
    'best_duration_at',bd.best_duration_at,
    'completed_sets',s.completed_sets,'last_performed_at',s.last_performed_at
  ) order by s.last_performed_at desc),'[]'::jsonb)
  into v_duration_records
  from timed_stats s
  left join best_duration bd on bd.exercise_id=s.exercise_id;

  v_native:=jsonb_build_object(
    'organization_id',p_organization_id,
    'summary',coalesce(v_summary,'{}'::jsonb),
    'sessions',coalesce(v_sessions,'[]'::jsonb),
    'records',coalesce(v_records,'[]'::jsonb),
    'duration_records',coalesce(v_duration_records,'[]'::jsonb),
    'generated_at',now(),
    'definitions',jsonb_build_object(
      'difficulty_level','Dificultad percibida por el cliente en escala simple de 1 a 5.',
      'had_pain','Indica si el cliente reportó molestia o dolor al finalizar la sesión.',
      'pain_context','Contexto estructurado del reporte de molestia.',
      'best_weight','Máxima carga registrada en un set marcado como completado.',
      'max_reps','Máximo de repeticiones registrado en un set marcado como completado.',
      'max_duration_seconds','Máxima duración en segundos registrada en un set por tiempo marcado como completado.',
      'volume','Suma persistida de peso por repeticiones de las series completadas.'
    )
  );

  select
    count(*)::integer,
    count(*) filter(
      where l.completed_at>=now()-interval '30 days'
        and (coalesce(l.counted,false)=true or lower(coalesce(l.state,'')) like '%final%')
    )::integer,
    count(*) filter(
      where l.completed_at>=now()-interval '30 days'
        and (coalesce(l.counted,false)=true or lower(coalesce(l.state,'')) like '%final%')
    )::integer,
    max(l.completed_at)
  into v_legacy_total,v_legacy_terminal_30,v_legacy_completed_30,v_legacy_last
  from public.coach_intelligence_pilots p
  join public.legacy_cv12_sessions_v87 l on l.pilot_id=p.id
  where p.organization_id=p_organization_id
    and p.client_id=v_client_id
    and p.source_system='cv12_legacy'
    and p.linked_at is not null;

  with combined as (
    select
      j.value as item,
      nullif(j.value->>'sort_at','')::timestamptz as sort_at
    from jsonb_array_elements(coalesce(v_native->'sessions','[]'::jsonb)) j

    union all

    select jsonb_build_object(
      'id',l.id,
      'organization_id',p.organization_id,
      'program_id',null,
      'program_day_id',null,
      'program_name','CV12 · Historial importado',
      'day_name',coalesce(l.title,l.day_label,'Entrenamiento CV12'),
      'day_number',case
        when substring(coalesce(l.day_label,'') from '([0-9]+)') is null then null
        else substring(l.day_label from '([0-9]+)')::integer
      end,
      'started_at',l.completed_at,
      'finished_at',l.completed_at,
      'status',case
        when coalesce(l.counted,false)=true or lower(coalesce(l.state,'')) like '%final%'
          then 'completed'
        else 'partial'
      end,
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
    where p.organization_id=p_organization_id
      and p.client_id=v_client_id
      and p.source_system='cv12_legacy'
      and p.linked_at is not null
  ),
  limited as (
    select item,sort_at
    from combined
    order by sort_at desc nulls last
    limit v_limit
  )
  select coalesce(jsonb_agg(item order by sort_at desc nulls last),'[]'::jsonb)
  into v_sessions
  from limited;

  v_summary:=coalesce(v_native->'summary','{}'::jsonb);
  begin
    v_native_last:=nullif(v_summary->>'last_workout_at','')::timestamptz;
  exception when others then
    v_native_last:=null;
  end;

  v_last:=case
    when v_native_last is null then v_legacy_last
    when v_legacy_last is null then v_native_last
    else greatest(v_native_last,v_legacy_last)
  end;

  v_summary:=v_summary||jsonb_build_object(
    'terminal_sessions',coalesce((v_summary->>'terminal_sessions')::integer,0)+v_legacy_terminal_30,
    'completed_sessions',coalesce((v_summary->>'completed_sessions')::integer,0)+v_legacy_completed_30,
    'last_workout_at',v_last,
    'legacy_sessions_included',v_legacy_total,
    'legacy_completion_excluded_from_average',true
  );

  return v_native||jsonb_build_object(
    'summary',v_summary,
    'sessions',v_sessions,
    'legacy_bridge',jsonb_build_object(
      'engine_version','CV12_NATIVE_READ_BRIDGE_V88_1_TENANT',
      'organization_id',p_organization_id,
      'source','cv12_legacy',
      'sessions_included',v_legacy_total,
      'read_only',true,
      'link_contract','organization_id+client_id+linked_at',
      'copied_to_native_workout_sessions',false,
      'auto_publish',false,
      'auto_program_edit',false
    )
  );
end;
$function$;

revoke all on function public.get_client_training_history_in_org_v1(uuid,integer) from public,anon;
grant execute on function public.get_client_training_history_in_org_v1(uuid,integer) to authenticated,service_role;

comment on function public.get_client_training_history_in_org_v1(uuid,integer)
is 'F1.M2.S1 tenant-explicit client history reader; selected ActiveOrganizationContext is mandatory and all native + legacy history is Organization-scoped.';
