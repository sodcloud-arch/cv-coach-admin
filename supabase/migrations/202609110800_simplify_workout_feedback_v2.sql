alter table public.workout_sessions
  add column if not exists difficulty_level smallint,
  add column if not exists had_pain boolean,
  add column if not exists pain_context jsonb;

alter table public.workout_sessions
  drop constraint if exists workout_sessions_difficulty_level_check;
alter table public.workout_sessions
  add constraint workout_sessions_difficulty_level_check
  check (difficulty_level is null or difficulty_level between 1 and 5);

create or replace function public.save_workout_feedback_v2(
  p_session_id uuid,
  p_difficulty_level integer,
  p_had_pain boolean,
  p_pain_general boolean default false,
  p_pain_session_exercise_ids uuid[] default '{}'::uuid[],
  p_pain_description text default null,
  p_session_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_session public.workout_sessions%rowtype;
  v_notes text:=nullif(btrim(coalesce(p_session_notes,'')),'');
  v_pain_notes text:=nullif(btrim(coalesce(p_pain_description,'')),'');
  v_ids uuid[]:=coalesce(p_pain_session_exercise_ids,'{}'::uuid[]);
  v_context jsonb:=null;
  v_valid_count integer:=0;
  v_requested_count integer:=0;
begin
  if p_session_id is null then raise exception 'session_id is required'; end if;
  if not private.can_edit_workout_session(p_session_id) then raise exception 'Not authorized to edit this workout'; end if;

  select * into v_session from public.workout_sessions where id=p_session_id for update;
  if not found then raise exception 'workout session not found'; end if;
  if v_session.status<>'in_progress'::public.workout_session_status then raise exception 'feedback can only be saved while workout is in progress'; end if;
  if p_difficulty_level is null or p_difficulty_level<1 or p_difficulty_level>5 then raise exception 'difficulty_level must be between 1 and 5'; end if;
  if p_had_pain is null then raise exception 'had_pain is required'; end if;
  if char_length(coalesce(v_notes,''))>1200 then raise exception 'session_notes too long'; end if;
  if char_length(coalesce(v_pain_notes,''))>700 then raise exception 'pain_description too long'; end if;

  if p_had_pain then
    if coalesce(p_pain_general,false) and coalesce(array_length(v_ids,1),0)>0 then
      raise exception 'choose general pain or specific exercises, not both';
    end if;
    if not coalesce(p_pain_general,false) and coalesce(array_length(v_ids,1),0)=0 then
      raise exception 'select general routine or at least one exercise when pain is reported';
    end if;

    if coalesce(array_length(v_ids,1),0)>0 then
      select count(distinct x)::integer into v_requested_count from unnest(v_ids) x;
      select count(*)::integer into v_valid_count
      from public.session_exercises se
      where se.workout_session_id=p_session_id and se.id=any(v_ids);
      if v_valid_count<>v_requested_count then raise exception 'one or more selected exercises do not belong to this workout'; end if;
    end if;

    select jsonb_build_object(
      'general',coalesce(p_pain_general,false),
      'exercises',coalesce(jsonb_agg(jsonb_build_object(
        'session_exercise_id',se.id,
        'exercise_id',se.exercise_id,
        'exercise_name',e.name
      ) order by se.exercise_order) filter (where se.id is not null),'[]'::jsonb)
    )
    into v_context
    from public.session_exercises se
    join public.exercises e on e.id=se.exercise_id
    where se.workout_session_id=p_session_id and se.id=any(v_ids);

    if coalesce(p_pain_general,false) and (v_context is null or v_context->'exercises' is null) then
      v_context:=jsonb_build_object('general',true,'exercises','[]'::jsonb);
    end if;
  end if;

  update public.workout_sessions
  set difficulty_level=p_difficulty_level,
      had_pain=p_had_pain,
      pain_context=case when p_had_pain then v_context else null end,
      client_effort=p_difficulty_level*2,
      fatigue_score=null,
      pain_score=case when p_had_pain then 4 else 0 end,
      pain_notes=case when p_had_pain then v_pain_notes else null end,
      session_notes=v_notes,
      updated_at=now()
  where id=p_session_id;

  return jsonb_build_object(
    'session_id',p_session_id,
    'saved',true,
    'difficulty_level',p_difficulty_level,
    'client_effort_legacy',p_difficulty_level*2,
    'had_pain',p_had_pain,
    'pain_score_legacy',case when p_had_pain then 4 else 0 end,
    'pain_context',case when p_had_pain then v_context else null end,
    'has_pain_description',(p_had_pain and v_pain_notes is not null),
    'has_session_notes',(v_notes is not null)
  );
end;
$function$;

grant execute on function public.save_workout_feedback_v2(uuid,integer,boolean,boolean,uuid[],text,text) to authenticated;
