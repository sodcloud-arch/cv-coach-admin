-- ARCH-1.0 · F1.M1.S5 Wave G1B2 — Authoring / Workout tenant scope
-- Hardens client-only authoring paths and workout start while preserving public signatures.

create or replace function private.get_client_time_learning_in_org(
  p_organization_id uuid,
  p_client_id uuid
)
returns table(
  sample_count integer,
  median_ratio numeric,
  applied_factor numeric
)
language sql
stable security definer
set search_path to ''
as $function$
with recent as (
  select
    ws.id,
    ws.duration_seconds::numeric/60.0 as actual_minutes,
    greatest(
      coalesce(pd.estimated_minutes,0),
      private.estimate_program_day_minutes(ws.program_day_id)
    )::numeric as reference_minutes
  from public.workout_sessions ws
  join public.program_days pd
    on pd.organization_id=ws.organization_id
   and pd.id=ws.program_day_id
  where ws.organization_id=p_organization_id
    and ws.client_id=p_client_id
    and ws.status='completed'::public.workout_session_status
    and ws.completion_pct>=80
    and ws.duration_seconds between 300 and 14400
  order by ws.finished_at desc nulls last,ws.started_at desc
  limit 10
),
ratios as (
  select actual_minutes/nullif(reference_minutes,0) as ratio
  from recent
  where reference_minutes>0
),
agg as (
  select
    count(*)::integer as n,
    percentile_cont(0.5) within group(order by ratio)::numeric as median
  from ratios
  where ratio between 0.4 and 2.5
)
select
  n,
  case when n>=3 then round(median,3) else null end,
  case
    when n>=3 then round(
      greatest(1.0::numeric,least(1.5::numeric,median)),
      3
    )
    else 1.0::numeric
  end
from agg;
$function$;

create or replace function private.get_client_time_learning(
  p_client_id uuid
)
returns table(
  sample_count integer,
  median_ratio numeric,
  applied_factor numeric
)
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_organization uuid;
begin
  v_organization:=private.resolve_legacy_client_organization_v1(
    p_client_id,null
  );

  return query
  select *
  from private.get_client_time_learning_in_org(
    v_organization,p_client_id
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.create_program_draft_backend(p_actor_id uuid, p_client_id uuid, p_name text, p_goal text DEFAULT NULL::text, p_start_date date DEFAULT NULL::date, p_end_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_auth_uid uuid := auth.uid();
  v_organization uuid;
  v_existing_draft uuid;
  v_existing_active uuid;
  v_program_id uuid;
  v_version integer;
  v_name text := nullif(pg_catalog.btrim(p_name), '');
begin
  if p_actor_id is null or p_client_id is null then
    raise exception 'actor_id and client_id are required';
  end if;

  if v_name is null then
    raise exception 'Program name is required';
  end if;

  if p_start_date is not null and p_end_date is not null and p_end_date < p_start_date then
    raise exception 'End date cannot be before start date';
  end if;

  if v_auth_uid is not null and v_auth_uid <> p_actor_id then
    raise exception 'Forbidden';
  end if;

  v_organization:=private.resolve_legacy_professional_organization_v1(
    p_actor_id,p_client_id
  );

  if not exists (
      select 1
      from public.clients c
      join public.profiles p on p.id=c.user_id
      where c.organization_id=v_organization
        and c.user_id=p_client_id
        and c.status<>'archived'::public.client_status
        and p.role='client'::public.app_role
        and p.status='active'::public.profile_status
    ) then
    raise exception 'Active client not found in organization';
  end if;

  if not private.actor_can_manage_client_in_org_v1(
    p_actor_id,v_organization,p_client_id
  ) then
    raise exception 'Forbidden';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_organization::text||':'||p_client_id::text, 0));

  select p.id into v_existing_draft
  from public.programs p
  where p.organization_id = v_organization
    and p.client_id = p_client_id
    and p.status = 'draft'::public.program_status
  order by p.updated_at desc, p.created_at desc
  limit 1;

  if v_existing_draft is not null then
    raise exception 'Client already has a draft program';
  end if;

  select p.id into v_existing_active
  from public.programs p
  where p.organization_id = v_organization
    and p.client_id = p_client_id
    and p.status = 'active'::public.program_status
  limit 1;

  if v_existing_active is not null then
    raise exception 'Client already has an active program; create a new version instead';
  end if;

  select coalesce(max(p.version),0) + 1
    into v_version
  from public.programs p
  where p.organization_id = v_organization
    and p.client_id = p_client_id;

  insert into public.programs (
    organization_id, client_id, coach_id, name, goal, start_date, end_date, status, version
  ) values (
    v_organization,
    p_client_id,
    p_actor_id,
    v_name,
    nullif(pg_catalog.btrim(p_goal), ''),
    p_start_date,
    p_end_date,
    'draft'::public.program_status,
    v_version
  )
  returning id into v_program_id;

  return jsonb_build_object(
    'program_id', v_program_id,
    'organization_id', v_organization,
    'client_id', p_client_id,
    'status', 'draft',
    'version', v_version
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.start_workout_backend(p_program_day_id uuid, p_actor_id uuid, p_client_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_target_client uuid:=coalesce(p_client_id,p_actor_id);
  v_organization uuid;
  v_actor_role text;
  v_program_id uuid;
  v_program_client uuid;
  v_program_coach uuid;
  v_program_status text;
  v_start_date date;
  v_end_date date;
  v_session_id uuid;
  v_session_exercise_id uuid;
  v_prev_session_id uuid;
  v_prev_session_exercise_id uuid;
  v_prev_best_set_id uuid;
  v_prev_best_weight numeric;
  v_prev_best_reps integer;
  v_prev_best_duration integer;
  v_ref_set_id uuid;
  v_ref_weight numeric;
  v_ref_reps integer;
  v_ref_duration integer;
  v_base_reps integer;
  v_suggested_reps integer;
  v_suggested_duration integer;
  v_source text;
  v_unit text;
  v_count integer:=0;
  v_set_no integer;
  pe public.program_exercises%rowtype;
  ps public.progression_suggestions%rowtype;
begin
  if p_program_day_id is null or p_actor_id is null then raise exception 'program_day_id and actor_id are required'; end if;
  select p.role::text into v_actor_role from public.profiles p where p.id=p_actor_id and p.status::text='active';
  if v_actor_role is null then raise exception 'actor is not an active CV Coach user'; end if;

  select pr.organization_id,pr.id,pr.client_id,pr.coach_id,pr.status::text,pr.start_date,pr.end_date
    into v_organization,v_program_id,v_program_client,v_program_coach,v_program_status,v_start_date,v_end_date
  from public.program_days pd join public.programs pr on pr.id=pd.program_id where pd.id=p_program_day_id;
  if v_program_id is null then raise exception 'program day not found'; end if;
  if v_program_client<>v_target_client then raise exception 'program day does not belong to target client'; end if;
  if v_program_status<>'active' then raise exception 'program is not active'; end if;
  if v_start_date is not null and current_date<v_start_date then raise exception 'program has not started yet'; end if;
  if v_end_date is not null and current_date>v_end_date then raise exception 'program has ended'; end if;

  if p_actor_id=v_target_client then
    if not private.is_org_member(v_organization) then
      raise exception 'client is not active in workout organization';
    end if;
  elsif not private.actor_can_manage_client_in_org_v1(
    p_actor_id,v_organization,v_target_client
  ) then
    raise exception 'actor is not authorized to start this workout';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(v_organization::text||':'||v_target_client::text),pg_catalog.hashtext('cv_coach_active_workout'));
  select ws.id into v_session_id from public.workout_sessions ws
  where ws.organization_id=v_organization and ws.client_id=v_target_client and ws.status='in_progress'::public.workout_session_status
  order by ws.started_at desc,ws.created_at desc limit 1;
  if v_session_id is not null then return private.start_workout_payload(v_session_id,true)||jsonb_build_object('organization_id',v_organization); end if;

  insert into public.workout_sessions(organization_id,client_id,program_id,program_day_id,started_at,status,completion_pct)
  values(v_organization,v_target_client,v_program_id,p_program_day_id,now(),'in_progress'::public.workout_session_status,0)
  returning id into v_session_id;

  for pe in select pex.* from public.program_exercises pex where pex.program_day_id=p_program_day_id and pex.active=true order by pex.exercise_order loop
    v_count:=v_count+1;
    v_unit:=coalesce(pe.prescription_unit,'reps');
    v_prev_session_id:=null; v_prev_session_exercise_id:=null; v_prev_best_set_id:=null;
    v_prev_best_weight:=null; v_prev_best_reps:=null; v_prev_best_duration:=null;

    select ws.id,se.id into v_prev_session_id,v_prev_session_exercise_id
    from public.workout_sessions ws join public.session_exercises se on se.workout_session_id=ws.id
    where ws.organization_id=v_organization and ws.client_id=v_target_client and ws.id<>v_session_id
      and ws.status in ('completed'::public.workout_session_status,'partial'::public.workout_session_status)
      and se.exercise_id=pe.exercise_id
    order by coalesce(ws.finished_at,ws.started_at) desc,ws.started_at desc limit 1;

    ps:=null;
    if v_unit='reps' then
      if v_prev_session_exercise_id is not null then
        select sl.id,sl.weight_kg,sl.reps into v_prev_best_set_id,v_prev_best_weight,v_prev_best_reps
        from public.set_logs sl where sl.session_exercise_id=v_prev_session_exercise_id and sl.completed=true and sl.reps is not null
        order by sl.weight_kg desc nulls last,sl.reps desc nulls last,sl.set_number asc limit 1;
      end if;

      update public.progression_suggestions x
      set status='rejected'::public.progression_status,reviewed_at=coalesce(x.reviewed_at,now()),updated_at=now()
      where x.organization_id=v_organization and x.client_id=v_target_client and x.exercise_id=pe.exercise_id
        and x.status in ('approved'::public.progression_status,'modified'::public.progression_status)
        and not private.progression_suggestion_is_fresh(x.id,v_program_id,v_target_client,pe.exercise_id);

      select x.* into ps from public.progression_suggestions x
      where x.organization_id=v_organization and x.client_id=v_target_client and x.exercise_id=pe.exercise_id
        and x.status in ('approved'::public.progression_status,'modified'::public.progression_status)
        and private.progression_suggestion_is_fresh(x.id,v_program_id,v_target_client,pe.exercise_id)
      order by x.reviewed_at desc nulls last,x.created_at desc limit 1;
    else
      if v_prev_session_exercise_id is not null then
        select sl.id,sl.duration_seconds into v_prev_best_set_id,v_prev_best_duration
        from public.set_logs sl where sl.session_exercise_id=v_prev_session_exercise_id and sl.completed=true and sl.duration_seconds is not null
        order by sl.duration_seconds desc,sl.set_number asc limit 1;
      end if;
      update public.progression_suggestions x
      set status='rejected'::public.progression_status,reviewed_at=coalesce(x.reviewed_at,now()),updated_at=now()
      where x.organization_id=v_organization and x.client_id=v_target_client and x.exercise_id=pe.exercise_id
        and x.status in ('pending'::public.progression_status,'approved'::public.progression_status,'modified'::public.progression_status);
    end if;

    v_base_reps:=case when v_unit='reps' then coalesce(v_prev_best_reps,pe.rep_min,pe.rep_max) else null end;
    if v_unit='reps' and ps.id is not null then
      if v_base_reps is null then v_base_reps:=coalesce(ps.suggested_rep_min,ps.suggested_rep_max); end if;
      if ps.suggested_rep_min is not null and v_base_reps is not null then v_base_reps:=greatest(v_base_reps,ps.suggested_rep_min); end if;
      if ps.suggested_rep_max is not null and v_base_reps is not null then v_base_reps:=least(v_base_reps,ps.suggested_rep_max); end if;
    end if;

    insert into public.session_exercises(
      workout_session_id,program_exercise_id,exercise_id,exercise_order,status,target_sets_snapshot,rep_min_snapshot,rep_max_snapshot,prescription_unit_snapshot,
      rir_target_snapshot,tempo_snapshot,rest_seconds_snapshot,load_strategy_snapshot,coach_notes_snapshot,client_notes_snapshot,allow_substitution_snapshot,
      previous_session_id,previous_session_exercise_id,previous_best_weight_kg,previous_best_reps,previous_best_duration_seconds,progression_suggestion_id,coach_weight_kg_snapshot
    ) values(
      v_session_id,pe.id,pe.exercise_id,pe.exercise_order,'pending'::public.session_exercise_status,pe.target_sets,pe.rep_min,pe.rep_max,v_unit,
      pe.rir_target,pe.tempo,pe.rest_seconds,pe.load_strategy,pe.coach_notes,pe.client_notes,pe.allow_substitution,
      v_prev_session_id,v_prev_session_exercise_id,case when v_unit='reps' then v_prev_best_weight else null end,
      case when v_unit='reps' then v_prev_best_reps else null end,case when v_unit='seconds' then v_prev_best_duration else null end,
      case when v_unit='reps' then ps.id else null end,case when v_unit='reps' then pe.initial_weight_kg else null end
    ) returning id into v_session_exercise_id;

    for v_set_no in 1..pe.target_sets loop
      v_ref_set_id:=null; v_ref_weight:=null; v_ref_reps:=null; v_ref_duration:=null;
      if v_prev_session_exercise_id is not null then
        if v_unit='reps' then
          select sl.id,sl.weight_kg,sl.reps into v_ref_set_id,v_ref_weight,v_ref_reps
          from public.set_logs sl where sl.session_exercise_id=v_prev_session_exercise_id and sl.set_number=v_set_no and sl.completed=true limit 1;
        else
          select sl.id,sl.duration_seconds into v_ref_set_id,v_ref_duration
          from public.set_logs sl where sl.session_exercise_id=v_prev_session_exercise_id and sl.set_number=v_set_no and sl.completed=true limit 1;
        end if;
      end if;
      if v_ref_set_id is null then v_ref_set_id:=v_prev_best_set_id; end if;
      if v_unit='reps' then
        if v_ref_weight is null then v_ref_weight:=v_prev_best_weight; end if;
        if v_ref_reps is null then v_ref_reps:=v_prev_best_reps; end if;
        if ps.id is not null and coalesce(ps.suggested_rep_min,ps.suggested_rep_max) is not null then v_suggested_reps:=coalesce(ps.suggested_rep_min,ps.suggested_rep_max);
        else v_suggested_reps:=coalesce(v_ref_reps,v_base_reps,pe.rep_min,pe.rep_max); end if;
        v_suggested_duration:=null;
        if ps.id is not null and ps.suggested_load is not null then v_source:='coach_progression';
        elsif v_ref_weight is not null then v_source:='previous_session';
        elsif pe.initial_weight_kg is not null then v_source:='coach_program';
        else v_source:='program_prescription'; end if;
      else
        if v_ref_duration is null then v_ref_duration:=v_prev_best_duration; end if;
        v_suggested_reps:=null;
        v_suggested_duration:=coalesce(v_ref_duration,pe.rep_min,pe.rep_max);
        if v_ref_duration is not null then v_source:='previous_session'; else v_source:='program_prescription'; end if;
      end if;

      insert into public.set_logs(session_exercise_id,set_number,weight_kg,reps,duration_seconds,rir,completed,source,
        suggested_weight_kg,suggested_reps,suggested_duration_seconds,reference_set_log_id,suggestion_source,
        previous_weight_kg,previous_reps,previous_duration_seconds)
      values(v_session_exercise_id,v_set_no,null,null,null,null,false,'manual'::public.log_source,
        case when v_unit='reps' then coalesce(ps.suggested_load,v_ref_weight,pe.initial_weight_kg) else null end,
        v_suggested_reps,v_suggested_duration,v_ref_set_id,v_source,
        case when v_unit='reps' then v_ref_weight else null end,case when v_unit='reps' then v_ref_reps else null end,
        case when v_unit='seconds' then v_ref_duration else null end);
    end loop;

    if v_unit='reps' and ps.id is not null then
      update public.progression_suggestions set status='applied'::public.progression_status,updated_at=now() where id=ps.id;
    end if;
  end loop;

  if v_count=0 then raise exception 'program day has no active exercises'; end if;
  return private.start_workout_payload(v_session_id,false)||jsonb_build_object('organization_id',v_organization);
end;
$function$;

comment on function private.get_client_time_learning_in_org(uuid,uuid) is
  'F1.M1.S5 G1B2 tenant-explicit workout duration learning.';
comment on function public.create_program_draft_backend(uuid,uuid,text,text,date,date) is
  'F1.M1.S5 G1B2 legacy authoring RPC: resolves exactly one actor/client Organization and scopes program lifecycle to it.';
comment on function public.start_workout_backend(uuid,uuid,uuid) is
  'F1.M1.S5 G1B2 workout start authorization and active-session identity are Program Organization scoped.';
