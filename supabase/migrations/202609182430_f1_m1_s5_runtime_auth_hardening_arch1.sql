-- ARCH-1.0 · F1.M1.S5 Wave G1B1 — runtime authorization hardening
-- Preserves existing business logic while replacing client-global Coach/Client
-- authorization with canonical Organization-scoped authorization.

CREATE OR REPLACE FUNCTION public.apply_ai_program_generation(p_actor_id uuid, p_generation_id uuid, p_plan jsonb, p_warnings jsonb DEFAULT '[]'::jsonb, p_conflicts jsonb DEFAULT '[]'::jsonb, p_explanations jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_request_role text:=coalesce(auth.role(),'');
  v_request_user uuid:=auth.uid();
  v_generation public.ai_program_generations%rowtype;
  v_program public.programs%rowtype;
  v_days jsonb;
  v_day jsonb;
  v_ex jsonb;
  v_day_id uuid;
  v_exercise_id uuid;
  v_exercise_unit text;
  v_day_count integer:=0;
  v_exercise_count integer:=0;
  v_target_day integer;
begin
  if p_actor_id is null or p_generation_id is null or p_plan is null then raise exception 'actor_id, generation_id and plan are required'; end if;
  if v_request_role<>'service_role' and (v_request_user is null or v_request_user<>p_actor_id) then raise exception 'actor identity mismatch'; end if;
  select g.* into v_generation from public.ai_program_generations g where g.id=p_generation_id for update;
  if v_generation.id is null then raise exception 'Generation not found'; end if;
  if v_generation.coach_id<>p_actor_id and v_request_role<>'service_role' then raise exception 'Forbidden'; end if;
  if v_generation.status='applied' then return jsonb_build_object('generation_id',v_generation.id,'program_id',v_generation.program_id,'status',v_generation.status,'applied_at',v_generation.applied_at); end if;
  if v_generation.status<>'prepared' then raise exception 'Generation is not applyable'; end if;
  if jsonb_typeof(coalesce(p_conflicts,'[]'::jsonb))<>'array' then raise exception 'conflicts must be an array'; end if;
  if exists(select 1 from jsonb_array_elements(coalesce(p_conflicts,'[]'::jsonb)) c where lower(coalesce(c->>'severity','')) in ('block','critical') or coalesce((c->>'blocking')::boolean,false)=true) then raise exception 'Blocking safety conflicts must be resolved before applying'; end if;

  select p.* into v_program from public.programs p where p.id=v_generation.program_id for update;
  if v_program.id is null or v_program.status<>'draft'::public.program_status then raise exception 'AI generation can only be applied to a draft program'; end if;
  if v_request_role<>'service_role'
     and not private.actor_can_manage_client_in_org_v1(
       p_actor_id,v_program.organization_id,v_program.client_id
     ) then
    raise exception 'Forbidden';
  end if;

  v_days:=p_plan->'days';
  if jsonb_typeof(v_days)<>'array' or jsonb_array_length(v_days)<1 then raise exception 'plan.days must be a non-empty array'; end if;
  if jsonb_array_length(v_days)>14 then raise exception 'plan exceeds maximum day count'; end if;
  if v_generation.scope='program' then delete from public.program_days where program_id=v_program.id;
  else
    v_target_day:=v_generation.target_day_number;
    if jsonb_array_length(v_days)<>1 then raise exception 'day regeneration requires exactly one day'; end if;
    if coalesce((v_days->0->>'day_number')::integer,0)<>v_target_day then raise exception 'day_number does not match target_day_number'; end if;
    delete from public.program_days where program_id=v_program.id and day_number=v_target_day;
  end if;

  for v_day in select value from jsonb_array_elements(v_days) loop
    if coalesce((v_day->>'day_number')::integer,0)<1 then raise exception 'day_number must be positive'; end if;
    if nullif(pg_catalog.btrim(v_day->>'name'),'') is null then raise exception 'day name is required'; end if;
    if jsonb_typeof(v_day->'exercises')<>'array' or jsonb_array_length(v_day->'exercises')<1 then raise exception 'each day requires at least one exercise'; end if;
    if jsonb_array_length(v_day->'exercises')>20 then raise exception 'day exceeds maximum exercise count'; end if;
    insert into public.program_days(program_id,day_number,name,focus,estimated_minutes,notes)
    values(v_program.id,(v_day->>'day_number')::integer,pg_catalog.btrim(v_day->>'name'),nullif(pg_catalog.btrim(v_day->>'focus'),''),case when nullif(v_day->>'estimated_minutes','') is null then null else (v_day->>'estimated_minutes')::integer end,nullif(pg_catalog.btrim(v_day->>'notes'),'')) returning id into v_day_id;
    v_day_count:=v_day_count+1;

    for v_ex in select value from jsonb_array_elements(v_day->'exercises') loop
      v_exercise_id:=(v_ex->>'exercise_id')::uuid;
      select e.prescription_unit into v_exercise_unit from public.exercises e where e.id=v_exercise_id and e.active=true;
      if v_exercise_unit is null then raise exception 'exercise_id % is not active',v_exercise_id; end if;
      if nullif(v_ex->>'prescription_unit','') is not null and (v_ex->>'prescription_unit')<>v_exercise_unit then raise exception 'prescription_unit does not match exercise catalog'; end if;
      if coalesce((v_ex->>'exercise_order')::integer,0)<1 then raise exception 'exercise_order must be positive'; end if;
      if coalesce((v_ex->>'target_sets')::integer,0) not between 1 and 10 then raise exception 'target_sets must be between 1 and 10'; end if;
      if nullif(v_ex->>'rep_min','') is not null and ((v_exercise_unit='reps' and (v_ex->>'rep_min')::integer not between 1 and 100) or (v_exercise_unit='seconds' and (v_ex->>'rep_min')::integer not between 1 and 600)) then raise exception 'rep_min out of range for prescription unit'; end if;
      if nullif(v_ex->>'rep_max','') is not null and ((v_exercise_unit='reps' and (v_ex->>'rep_max')::integer not between 1 and 100) or (v_exercise_unit='seconds' and (v_ex->>'rep_max')::integer not between 1 and 600)) then raise exception 'rep_max out of range for prescription unit'; end if;
      if nullif(v_ex->>'rep_min','') is not null and nullif(v_ex->>'rep_max','') is not null and (v_ex->>'rep_max')::integer<(v_ex->>'rep_min')::integer then raise exception 'rep_max cannot be below rep_min'; end if;
      if nullif(v_ex->>'rir_target','') is not null and (v_ex->>'rir_target')::numeric not between 0 and 10 then raise exception 'rir_target out of range'; end if;
      if nullif(v_ex->>'rest_seconds','') is not null and (v_ex->>'rest_seconds')::integer not between 0 and 900 then raise exception 'rest_seconds out of range'; end if;
      if nullif(v_ex->>'initial_weight_kg','') is not null and (v_ex->>'initial_weight_kg')::numeric<0 then raise exception 'initial_weight_kg cannot be negative'; end if;
      if v_exercise_unit='seconds' and nullif(v_ex->>'initial_weight_kg','') is not null and (v_ex->>'initial_weight_kg')::numeric<>0 then raise exception 'time-based exercise cannot receive an initial load in v1'; end if;

      insert into public.program_exercises(program_day_id,exercise_id,exercise_order,target_sets,rep_min,rep_max,prescription_unit,rir_target,tempo,rest_seconds,load_strategy,coach_notes,client_notes,allow_substitution,active,initial_weight_kg)
      values(v_day_id,v_exercise_id,(v_ex->>'exercise_order')::integer,(v_ex->>'target_sets')::integer,
        case when nullif(v_ex->>'rep_min','') is null then null else (v_ex->>'rep_min')::integer end,
        case when nullif(v_ex->>'rep_max','') is null then null else (v_ex->>'rep_max')::integer end,
        v_exercise_unit,
        case when nullif(v_ex->>'rir_target','') is null then null else (v_ex->>'rir_target')::numeric end,
        nullif(pg_catalog.btrim(v_ex->>'tempo'),''),
        case when nullif(v_ex->>'rest_seconds','') is null then null else (v_ex->>'rest_seconds')::integer end,
        nullif(pg_catalog.btrim(v_ex->>'load_strategy'),''),nullif(pg_catalog.btrim(v_ex->>'coach_notes'),''),nullif(pg_catalog.btrim(v_ex->>'client_notes'),''),
        coalesce((v_ex->>'allow_substitution')::boolean,false),true,
        case when v_exercise_unit='seconds' then null when nullif(v_ex->>'initial_weight_kg','') is null then null else (v_ex->>'initial_weight_kg')::numeric end);
      v_exercise_count:=v_exercise_count+1;
    end loop;
  end loop;

  update public.ai_program_generations set status='applied',output_snapshot=p_plan,warnings=coalesce(p_warnings,'[]'::jsonb),conflicts=coalesce(p_conflicts,'[]'::jsonb),explanations=coalesce(p_explanations,'{}'::jsonb),applied_at=now(),updated_at=now() where id=v_generation.id;
  return jsonb_build_object('generation_id',v_generation.id,'program_id',v_program.id,'client_id',v_program.client_id,'status','applied','days_written',v_day_count,'exercises_written',v_exercise_count,'publish_required',true);
end;
$function$


CREATE OR REPLACE FUNCTION public.clone_program_version_backend(p_actor_id uuid, p_source_program_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_source public.programs%rowtype;
  v_existing_draft uuid;
  v_new_program_id uuid;
  v_new_day_id uuid;
  v_new_version integer;
  v_day record;
  v_days integer := 0;
  v_exercises integer := 0;
  v_inserted integer := 0;
  v_auth_uid uuid := auth.uid();
begin
  if p_actor_id is null or p_source_program_id is null then raise exception 'actor_id and source_program_id are required'; end if;
  if v_auth_uid is not null and v_auth_uid <> p_actor_id then raise exception 'Forbidden'; end if;
  select p.* into v_source from public.programs p where p.id=p_source_program_id for update;
  if v_source.id is null then raise exception 'Program not found'; end if;
  if v_source.status <> 'active'::public.program_status then raise exception 'Only active programs can create a new version'; end if;
  if not private.actor_can_manage_client_in_org_v1(
    p_actor_id,v_source.organization_id,v_source.client_id
  ) then
    raise exception 'Forbidden';
  end if;
  perform 1 from public.programs p where p.organization_id=v_source.organization_id and p.client_id=v_source.client_id for update;
  select p.id into v_existing_draft from public.programs p where p.organization_id=v_source.organization_id and p.client_id=v_source.client_id and p.status='draft'::public.program_status order by p.updated_at desc,p.created_at desc limit 1;
  if v_existing_draft is not null then raise exception 'Client already has a draft program'; end if;
  select coalesce(max(p.version),0)+1 into v_new_version from public.programs p where p.organization_id=v_source.organization_id and p.client_id=v_source.client_id;
  insert into public.programs(organization_id,client_id,coach_id,name,goal,start_date,end_date,status,version)
  values(v_source.organization_id,v_source.client_id,p_actor_id,v_source.name,v_source.goal,null,null,'draft'::public.program_status,v_new_version)
  returning id into v_new_program_id;
  for v_day in select pd.* from public.program_days pd where pd.program_id=p_source_program_id order by pd.day_number,pd.created_at loop
    insert into public.program_days(program_id,day_number,name,focus,estimated_minutes,notes)
    values(v_new_program_id,v_day.day_number,v_day.name,v_day.focus,v_day.estimated_minutes,v_day.notes)
    returning id into v_new_day_id;
    v_days:=v_days+1;
    insert into public.program_exercises(program_day_id,exercise_id,exercise_order,target_sets,rep_min,rep_max,prescription_unit,rir_target,tempo,rest_seconds,load_strategy,coach_notes,client_notes,allow_substitution,active,initial_weight_kg)
    select v_new_day_id,pe.exercise_id,pe.exercise_order,pe.target_sets,pe.rep_min,pe.rep_max,pe.prescription_unit,pe.rir_target,pe.tempo,pe.rest_seconds,pe.load_strategy,pe.coach_notes,pe.client_notes,pe.allow_substitution,pe.active,pe.initial_weight_kg
    from public.program_exercises pe where pe.program_day_id=v_day.id order by pe.exercise_order,pe.created_at;
    get diagnostics v_inserted=row_count;
    v_exercises:=v_exercises+v_inserted;
  end loop;
  return jsonb_build_object('source_program_id',p_source_program_id,'program_id',v_new_program_id,'client_id',v_source.client_id,'status','draft','version',v_new_version,'days',v_days,'exercises',v_exercises,'contract','CLONE_PROGRAM_V84_PRESERVES_UNIT');
end;
$function$


CREATE OR REPLACE FUNCTION public.get_program_asset_preflight_v100(p_actor_id uuid, p_program_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_role text:=coalesce(auth.role(),'');
  v_uid uuid:=auth.uid();
  v_organization uuid;
  v_client_id uuid;
  v_ready integer:=0;
  v_total integer:=0;
  v_blocking jsonb:='[]'::jsonb;
begin
  if p_actor_id is null or p_program_id is null then raise exception 'actor_id and program_id are required'; end if;
  if v_role<>'service_role' and (v_uid is null or v_uid<>p_actor_id) then raise exception 'actor identity mismatch'; end if;
  select organization_id,client_id into v_organization,v_client_id from public.programs where id=p_program_id;
  if v_client_id is null then raise exception 'Program not found'; end if;
  if v_role<>'service_role'
     and not private.actor_can_manage_client_in_org_v1(
       p_actor_id,v_organization,v_client_id
     ) then
    raise exception 'Forbidden';
  end if;

  select count(*)::integer,
         count(*) filter(where r.status in ('approved','external_verified') and nullif(btrim(e.image_path),'') is not null)::integer,
         coalesce(jsonb_agg(jsonb_build_object('exercise_id',e.id,'exercise_name',e.name,'asset_status',coalesce(r.status,'missing'),'source_type',coalesce(r.source_type,'none')) order by pd.day_number,pe.exercise_order)
           filter(where r.exercise_id is null or r.status not in ('approved','external_verified') or nullif(btrim(e.image_path),'') is null),'[]'::jsonb)
  into v_total,v_ready,v_blocking
  from public.program_days pd
  join public.program_exercises pe on pe.program_day_id=pd.id and pe.active=true
  join public.exercises e on e.id=pe.exercise_id
  left join public.exercise_asset_registry_v100 r on r.exercise_id=e.id
  where pd.program_id=p_program_id;

  return jsonb_build_object(
    'engine_version','EXERCISE_ASSET_GUARDRAIL_V100',
    'program_id',p_program_id,
    'organization_id',v_organization,
    'client_id',v_client_id,
    'total_exercises',v_total,
    'ready_exercises',v_ready,
    'blocking_count',jsonb_array_length(v_blocking),
    'blocking_exercises',v_blocking,
    'ready',v_total>0 and v_total=v_ready,
    'publish_blocked',not(v_total>0 and v_total=v_ready),
    'allowed_statuses',jsonb_build_array('approved','external_verified')
  );
end;
$function$


CREATE OR REPLACE FUNCTION public.review_progression_suggestion_v83(p_actor_id uuid, p_suggestion_id uuid, p_decision text, p_suggested_load numeric DEFAULT NULL::numeric, p_suggested_rep_min integer DEFAULT NULL::integer, p_suggested_rep_max integer DEFAULT NULL::integer, p_suggested_duration_seconds integer DEFAULT NULL::integer, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  s public.progression_suggestions%rowtype;
  v_role public.app_role;
  r jsonb;
  v_action text;
  v_note text:=nullif(btrim(coalesce(p_note,'')),'');
  v_engine_load numeric;
  v_engine_rep_min integer;
  v_engine_rep_max integer;
  v_engine_duration integer;
  v_current_load numeric;
  v_current_duration integer;
  v_target_rep_min integer;
  v_load numeric;
  v_rep_min integer;
  v_rep_max integer;
  v_duration integer;
begin
  if (select auth.uid()) is null or (select auth.uid())<>p_actor_id then
    raise exception 'Actor authentication mismatch';
  end if;
  select role into v_role from public.profiles where id=p_actor_id and status::text='active';
  if v_role is null or v_role not in ('admin'::public.app_role,'coach'::public.app_role) then
    raise exception 'Coach/admin role required';
  end if;

  select * into s
  from public.progression_suggestions
  where id=p_suggestion_id
  for update;
  if not found then raise exception 'Progression suggestion not found'; end if;

  if not private.actor_can_manage_client_in_org_v1(
    p_actor_id,s.organization_id,s.client_id
  ) then
    raise exception 'Coach/admin is not authorized for this client in organization';
  end if;

  if p_decision not in ('approved','modified','rejected') then
    raise exception 'Unsupported progression decision';
  end if;
  if v_note is not null and char_length(v_note)>1000 then
    raise exception 'Coach note too long';
  end if;

  r:=private.progression_recommendation_v83(s.source_session_id,s.exercise_id);
  v_action:=coalesce(r->>'action','collect_more_data');
  perform pg_catalog.set_config('cv.v83_review','1',true);

  if p_decision='rejected' then
    update public.progression_suggestions
    set status='rejected'::public.progression_status,
        reviewed_by=p_actor_id,
        reviewed_at=now(),
        evidence=coalesce(evidence,'{}'::jsonb)||jsonb_build_object(
          'coach_review',jsonb_build_object('decision','rejected','note',v_note,'at',now())
        ),
        updated_at=now()
    where id=s.id;
  else
    if v_action not in ('increase_load','build_reps','build_time','maintain') then
      raise exception 'Current evidence does not allow progression approval';
    end if;

    v_engine_load:=nullif(r->>'suggested_load','')::numeric;
    v_engine_rep_min:=nullif(r->>'suggested_rep_min','')::integer;
    v_engine_rep_max:=nullif(r->>'suggested_rep_max','')::integer;
    v_engine_duration:=nullif(r->>'suggested_duration_seconds','')::integer;
    v_current_load:=nullif(r->>'current_load','')::numeric;
    v_current_duration:=coalesce(
      nullif(r->>'current_min_duration_seconds','')::integer,
      nullif(r->>'previous_duration_seconds','')::integer
    );
    v_target_rep_min:=nullif(r->>'target_rep_min','')::integer;

    if p_decision='approved' then
      v_load:=v_engine_load;
      v_rep_min:=v_engine_rep_min;
      v_rep_max:=v_engine_rep_max;
      v_duration:=v_engine_duration;
    else
      v_load:=coalesce(p_suggested_load,v_engine_load);
      v_rep_min:=coalesce(p_suggested_rep_min,v_engine_rep_min);
      v_rep_max:=coalesce(p_suggested_rep_max,v_engine_rep_max);
      v_duration:=coalesce(p_suggested_duration_seconds,v_engine_duration);

      if v_engine_load is not null then
        if v_load is null or v_load<0 or v_load>v_engine_load then
          raise exception 'Modified load exceeds V83 safe ceiling';
        end if;
        if v_action='increase_load' and v_current_load is not null and v_load<v_current_load then
          raise exception 'Modified increase-load target cannot be below current load';
        end if;
      elsif v_load is not null then
        raise exception 'Load modification is not valid for this recommendation';
      end if;

      if v_engine_rep_min is not null then
        if v_rep_min is null
           or (v_target_rep_min is not null and v_rep_min<v_target_rep_min)
           or v_rep_min>v_engine_rep_min then
          raise exception 'Modified repetition target exceeds V83 safe bounds';
        end if;
        if v_rep_max is null then v_rep_max:=v_engine_rep_max; end if;
        if v_rep_max<v_rep_min
           or (v_engine_rep_max is not null and v_rep_max>v_engine_rep_max) then
          raise exception 'Modified repetition range exceeds V83 safe bounds';
        end if;
      elsif v_rep_min is not null or v_rep_max is not null then
        raise exception 'Repetition modification is not valid for this recommendation';
      end if;

      if v_engine_duration is not null then
        if v_duration is null
           or v_duration>v_engine_duration
           or (v_current_duration is not null and v_duration<v_current_duration) then
          raise exception 'Modified duration exceeds V83 safe bounds';
        end if;
      elsif v_duration is not null then
        raise exception 'Duration modification is not valid for this recommendation';
      end if;
    end if;

    update public.progression_suggestions
    set status=case when p_decision='approved'
                    then 'approved'::public.progression_status
                    else 'modified'::public.progression_status end,
        suggested_load=v_load,
        suggested_rep_min=v_rep_min,
        suggested_rep_max=v_rep_max,
        suggested_duration_seconds=v_duration,
        action=v_action,
        engine_version='PROGRESSION_ENGINE_V83',
        confidence=coalesce((r->>'confidence')::numeric,confidence),
        confidence_band=coalesce(r->>'confidence_band',confidence_band),
        evidence_sessions=coalesce((r->>'evidence_sessions')::integer,evidence_sessions),
        suggested_increment_kg=nullif(r->>'suggested_increment_kg','')::numeric,
        reason_code=left(coalesce(r->>'signal',reason_code,v_action),120),
        reason_text=left(coalesce(r->>'reason',reason_text,'Recomendación V83'),1000),
        reviewed_by=p_actor_id,
        reviewed_at=now(),
        evidence=r||jsonb_build_object(
          'coach_review',jsonb_build_object(
            'decision',p_decision,'note',v_note,'at',now(),
            'suggested_load',v_load,
            'suggested_rep_min',v_rep_min,
            'suggested_rep_max',v_rep_max,
            'suggested_duration_seconds',v_duration
          )
        ),
        updated_at=now()
    where id=s.id;
  end if;

  select * into s from public.progression_suggestions where id=p_suggestion_id;
  return jsonb_build_object(
    'id',s.id,'client_id',s.client_id,'exercise_id',s.exercise_id,
    'status',s.status::text,'action',s.action,
    'suggested_load',s.suggested_load,
    'suggested_rep_min',s.suggested_rep_min,
    'suggested_rep_max',s.suggested_rep_max,
    'suggested_duration_seconds',s.suggested_duration_seconds,
    'reviewed_by',s.reviewed_by,'reviewed_at',s.reviewed_at,
    'engine_version',s.engine_version
  );
end;
$function$


CREATE OR REPLACE FUNCTION public.review_training_adaptation_v83(p_actor_id uuid, p_review_id uuid, p_decision text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  r public.training_adaptation_reviews%rowtype;
  v_role public.app_role;
  v_note text:=nullif(btrim(coalesce(p_note,'')),'');
begin
  if (select auth.uid()) is null or (select auth.uid())<>p_actor_id then
    raise exception 'Actor authentication mismatch';
  end if;
  select role into v_role from public.profiles where id=p_actor_id and status::text='active';
  if v_role is null or v_role not in ('admin'::public.app_role,'coach'::public.app_role) then
    raise exception 'Coach/admin role required';
  end if;

  select * into r from public.training_adaptation_reviews where id=p_review_id for update;
  if not found then raise exception 'Adaptation review not found'; end if;

  if not private.actor_can_manage_client_in_org_v1(
    p_actor_id,r.organization_id,r.client_id
  ) then
    raise exception 'Coach/admin is not authorized for this client in organization';
  end if;

  if p_decision not in ('reviewed','dismissed') then
    raise exception 'Unsupported adaptation decision';
  end if;
  if v_note is not null and char_length(v_note)>1000 then raise exception 'Coach note too long'; end if;

  update public.training_adaptation_reviews
  set status=p_decision,
      reviewed_by=p_actor_id,
      reviewed_at=now(),
      coach_notes=v_note,
      updated_at=now()
  where id=p_review_id
  returning * into r;

  return jsonb_build_object(
    'id',r.id,'client_id',r.client_id,'program_id',r.program_id,
    'state',r.state,'status',r.status,'reviewed_at',r.reviewed_at
  );
end;
$function$


comment on function public.apply_ai_program_generation(uuid,uuid,jsonb,jsonb,jsonb,jsonb) is
  'F1.M1.S5 G1B1: AI generation apply authorization is bound to Program Organization.';
comment on function public.clone_program_version_backend(uuid,uuid) is
  'F1.M1.S5 G1B1: Program cloning scopes authorization, draft uniqueness and versioning to Organization.';
