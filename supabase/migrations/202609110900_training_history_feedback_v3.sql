create or replace function public.get_client_training_history(p_limit integer default 20)
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
  v_role text;
  v_status text;
begin
  if v_client_id is null then raise exception 'Authentication required'; end if;
  select p.role::text,p.status::text into v_role,v_status from public.profiles p where p.id=v_client_id;
  if v_role is distinct from 'client' or v_status is distinct from 'active' then raise exception 'Active client profile required'; end if;

  select jsonb_build_object(
    'window_days',30,
    'terminal_sessions',count(*) filter(where ws.status::text in ('completed','partial','abandoned')),
    'completed_sessions',count(*) filter(where ws.status='completed'::public.workout_session_status),
    'partial_sessions',count(*) filter(where ws.status='partial'::public.workout_session_status),
    'abandoned_sessions',count(*) filter(where ws.status='abandoned'::public.workout_session_status),
    'total_volume',coalesce(sum(ws.total_volume) filter(where ws.total_volume is not null),0),
    'avg_completion',round(avg(ws.completion_pct) filter(where ws.completion_pct is not null),1),
    'last_workout_at',max(coalesce(ws.finished_at,ws.started_at))
  ) into v_summary
  from public.workout_sessions ws
  where ws.client_id=v_client_id and ws.status::text in ('completed','partial','abandoned')
    and coalesce(ws.finished_at,ws.started_at)>=now()-interval '30 days';

  select coalesce(jsonb_agg(to_jsonb(x) order by x.sort_at desc),'[]'::jsonb) into v_sessions
  from (
    select ws.id,ws.program_id,ws.program_day_id,pr.name as program_name,pd.name as day_name,pd.day_number,
           ws.started_at,ws.finished_at,ws.status::text as status,ws.completion_pct,ws.duration_seconds,
           ws.total_volume,ws.difficulty_level,ws.had_pain,ws.pain_context,
           ws.client_effort,ws.fatigue_score,ws.pain_score,ws.pain_notes,ws.session_notes,
           coalesce(ws.finished_at,ws.started_at) as sort_at
    from public.workout_sessions ws
    left join public.programs pr on pr.id=ws.program_id
    left join public.program_days pd on pd.id=ws.program_day_id
    where ws.client_id=v_client_id and ws.status::text in ('completed','partial','abandoned')
    order by coalesce(ws.finished_at,ws.started_at) desc limit v_limit
  ) x;

  with completed_sets as (
    select se.exercise_id,e.name as exercise_name,sl.weight_kg,sl.reps,sl.rir,
           coalesce(sl.completed_at,sl.updated_at,sl.created_at) as performed_at,ws.id as session_id
    from public.set_logs sl
    join public.session_exercises se on se.id=sl.session_exercise_id
    join public.workout_sessions ws on ws.id=se.workout_session_id
    join public.exercises e on e.id=se.exercise_id
    where ws.client_id=v_client_id and sl.completed=true and sl.reps is not null and sl.reps>0
      and coalesce(se.prescription_unit_snapshot,e.prescription_unit,'reps')='reps'
      and ws.status::text in ('completed','partial','abandoned')
  ), best_weight as (
    select distinct on (exercise_id) exercise_id,weight_kg as best_weight_kg,reps as reps_at_best_weight,rir as rir_at_best_weight,
      performed_at as best_weight_at,session_id as best_weight_session_id
    from completed_sets where weight_kg is not null and weight_kg>0
    order by exercise_id,weight_kg desc,reps desc,performed_at desc
  ), stats as (
    select exercise_id,max(exercise_name) as exercise_name,max(reps) as max_reps,count(*)::integer as completed_sets,max(performed_at) as last_performed_at
    from completed_sets group by exercise_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'exercise_id',s.exercise_id,'exercise_name',s.exercise_name,'prescription_unit','reps',
    'best_weight_kg',bw.best_weight_kg,'reps_at_best_weight',bw.reps_at_best_weight,'rir_at_best_weight',bw.rir_at_best_weight,
    'best_weight_at',bw.best_weight_at,'max_reps',s.max_reps,'completed_sets',s.completed_sets,'last_performed_at',s.last_performed_at
  ) order by s.last_performed_at desc),'[]'::jsonb) into v_records
  from stats s left join best_weight bw on bw.exercise_id=s.exercise_id;

  with timed_sets as (
    select se.exercise_id,e.name as exercise_name,sl.duration_seconds,sl.rir,
           coalesce(sl.completed_at,sl.updated_at,sl.created_at) as performed_at,ws.id as session_id
    from public.set_logs sl
    join public.session_exercises se on se.id=sl.session_exercise_id
    join public.workout_sessions ws on ws.id=se.workout_session_id
    join public.exercises e on e.id=se.exercise_id
    where ws.client_id=v_client_id and sl.completed=true and sl.duration_seconds is not null and sl.duration_seconds>0
      and coalesce(se.prescription_unit_snapshot,e.prescription_unit,'reps')='seconds'
      and ws.status::text in ('completed','partial','abandoned')
  ), timed_stats as (
    select exercise_id,max(exercise_name) as exercise_name,max(duration_seconds) as max_duration_seconds,
           count(*)::integer as completed_sets,max(performed_at) as last_performed_at
    from timed_sets group by exercise_id
  ), best_duration as (
    select distinct on (exercise_id) exercise_id,duration_seconds as best_duration_seconds,rir as rir_at_best_duration,
           performed_at as best_duration_at,session_id as best_duration_session_id
    from timed_sets order by exercise_id,duration_seconds desc,performed_at desc
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'exercise_id',s.exercise_id,'exercise_name',s.exercise_name,'prescription_unit','seconds',
    'max_duration_seconds',s.max_duration_seconds,'best_duration_seconds',bd.best_duration_seconds,
    'rir_at_best_duration',bd.rir_at_best_duration,'best_duration_at',bd.best_duration_at,
    'completed_sets',s.completed_sets,'last_performed_at',s.last_performed_at
  ) order by s.last_performed_at desc),'[]'::jsonb) into v_duration_records
  from timed_stats s left join best_duration bd on bd.exercise_id=s.exercise_id;

  return jsonb_build_object(
    'summary',coalesce(v_summary,'{}'::jsonb),
    'sessions',coalesce(v_sessions,'[]'::jsonb),
    'records',coalesce(v_records,'[]'::jsonb),
    'duration_records',coalesce(v_duration_records,'[]'::jsonb),
    'generated_at',now(),
    'definitions',jsonb_build_object(
      'difficulty_level','Dificultad percibida por el cliente en escala simple de 1 a 5.',
      'had_pain','Indica si el cliente reportó molestia o dolor al finalizar la sesión.',
      'pain_context','Contexto estructurado del reporte de molestia: rutina completa o ejercicios seleccionados.',
      'best_weight','Máxima carga registrada en un set marcado como completado.',
      'max_reps','Máximo de repeticiones registrado en un set marcado como completado.',
      'max_duration_seconds','Máxima duración en segundos registrada en un set por tiempo marcado como completado.',
      'volume','Suma persistida de peso por repeticiones de las series completadas; los ejercicios por tiempo no se suman al volumen de carga.'
    )
  );
end;
$function$;

grant execute on function public.get_client_training_history(integer) to authenticated;
