-- ARCH-1.0 · F1.M1.S5 Wave G1B3B — AI / Quality / Publish tenant scope

alter table public.ai_program_generations
  drop constraint if exists ai_program_generations_idempotency_key_key;
drop index if exists public.ai_program_generations_idempotency_key_key;
create unique index if not exists uq_ai_program_generations_org_idempotency
  on public.ai_program_generations(organization_id,idempotency_key);

CREATE OR REPLACE FUNCTION private.inject_ai_generation_quality_context()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_constraints jsonb;
  v_exposures jsonb;
  v_time jsonb;
begin
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'constraint_code',c.constraint_code,
        'label',cat.label,
        'region',cat.region,
        'action',c.action,
        'note',c.note
      )
      order by cat.region,cat.label
    ),
    '[]'::jsonb
  )
  into v_constraints
  from public.client_training_constraints c
  join public.training_constraint_catalog cat
    on cat.code=c.constraint_code
  where c.organization_id=new.organization_id
    and c.client_id=new.client_id
    and c.active=true
    and c.valid_from<=current_date
    and (c.valid_until is null or c.valid_until>=current_date);

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'exercise_id',eme.exercise_id,
        'constraint_code',eme.constraint_code,
        'exposure_level',eme.exposure_level
      )
    ),
    '[]'::jsonb
  )
  into v_exposures
  from public.exercise_mechanical_exposures eme
  join public.exercises e
    on e.id=eme.exercise_id
   and e.active=true;

  select jsonb_build_object(
    'sample_count',t.sample_count,
    'median_ratio',t.median_ratio,
    'applied_factor',t.applied_factor
  )
  into v_time
  from private.get_client_time_learning_in_org(new.organization_id,new.client_id) t;

  new.input_snapshot:=coalesce(new.input_snapshot,'{}'::jsonb)
    ||jsonb_build_object(
      'organization_id',new.organization_id,
      'training_constraints',coalesce(v_constraints,'[]'::jsonb),
      'exercise_mechanical_exposures',coalesce(v_exposures,'[]'::jsonb),
      'time_learning',coalesce(v_time,'{}'::jsonb)
    );

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.prepare_ai_program_generation(p_actor_id uuid, p_client_id uuid, p_program_id uuid DEFAULT NULL::uuid, p_scope text DEFAULT 'program'::text, p_target_day_number integer DEFAULT NULL::integer, p_idempotency_key text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_request_role text:=coalesce(auth.role(),'');
  v_request_user uuid:=auth.uid(); v_organization uuid;
  v_program public.programs%rowtype;
  v_generation public.ai_program_generations%rowtype;
  v_key text:=nullif(pg_catalog.btrim(p_idempotency_key),'');
  v_context jsonb;
  v_onboarding jsonb;
  v_weekly jsonb;
  v_catalog jsonb;
  v_current_program jsonb;
  v_client_profile jsonb;
  v_mesocycle jsonb;
  v_constraints jsonb;
  v_exposures jsonb;
  v_time_learning jsonb;
begin
  if p_actor_id is null or p_client_id is null then raise exception 'actor_id and client_id are required'; end if;
  if p_scope not in ('program','day') then raise exception 'scope must be program or day'; end if;
  if p_scope='day' and (p_target_day_number is null or p_target_day_number<1) then raise exception 'target_day_number is required for day scope'; end if;
  if v_key is null then raise exception 'idempotency_key is required'; end if;
  if v_request_role<>'service_role' and (v_request_user is null or v_request_user<>p_actor_id) then raise exception 'actor identity mismatch'; end if;

  if p_program_id is null then
    v_organization:=private.resolve_legacy_professional_organization_v1(
      p_actor_id,p_client_id
    );
    select p.* into v_program
    from public.programs p
    where p.organization_id=v_organization
      and p.client_id=p_client_id
      and p.status='draft'::public.program_status
    order by p.updated_at desc,p.created_at desc
    limit 1;
  else
    select p.* into v_program
    from public.programs p
    where p.id=p_program_id
      and p.client_id=p_client_id;
    if v_program.id is not null then
      v_organization:=v_program.organization_id;
    end if;
  end if;

  if v_program.id is null then raise exception 'Draft program not found'; end if;
  if v_program.status<>'draft'::public.program_status then raise exception 'AI generation can only target draft programs'; end if;

  if v_request_role<>'service_role'
     and not private.actor_can_manage_client_in_org_v1(
       p_actor_id,v_organization,p_client_id
     ) then
    raise exception 'Forbidden';
  end if;

  select g.* into v_generation from public.ai_program_generations g where g.organization_id=v_organization and g.idempotency_key=v_key limit 1;
  if v_generation.id is not null then
    if v_generation.program_id<>v_program.id or v_generation.client_id<>p_client_id or v_generation.coach_id<>p_actor_id or v_generation.scope<>p_scope or coalesce(v_generation.target_day_number,0)<>coalesce(p_target_day_number,0) then
      raise exception 'idempotency_key already used for another generation';
    end if;
    return jsonb_build_object('generation_id',v_generation.id,'program_id',v_generation.program_id,'client_id',v_generation.client_id,'scope',v_generation.scope,'target_day_number',v_generation.target_day_number,'status',v_generation.status,'engine_version',v_generation.engine_version,'context',v_generation.input_snapshot);
  end if;

  select coalesce(jsonb_object_agg(r.question_key,r.response_value),'{}'::jsonb) into v_onboarding from public.onboarding_responses r where r.client_id=p_client_id;
  select coalesce(to_jsonb(w),'{}'::jsonb) into v_weekly from (select wc.* from public.weekly_checkins wc where wc.client_id=p_client_id order by wc.submitted_at desc limit 1) w;
  select coalesce(to_jsonb(cp),'{}'::jsonb) into v_client_profile from public.client_profiles cp where cp.organization_id=v_organization and cp.client_id=p_client_id;
  select coalesce(to_jsonb(t),'{}'::jsonb) into v_time_learning from private.get_client_time_learning_in_org(v_organization,p_client_id) t;
  select coalesce(jsonb_agg(jsonb_build_object('constraint_code',c.constraint_code,'label',cat.label,'region',cat.region,'action',c.action,'note',c.note)),'[]'::jsonb)
    into v_constraints from public.client_training_constraints c join public.training_constraint_catalog cat on cat.code=c.constraint_code
    where c.organization_id=v_organization and c.client_id=p_client_id and c.active=true and (c.valid_until is null or c.valid_until>=current_date);
  select coalesce(jsonb_agg(jsonb_build_object('exercise_id',e.exercise_id,'constraint_code',e.constraint_code,'exposure_level',e.exposure_level)),'[]'::jsonb)
    into v_exposures from public.exercise_mechanical_exposures e;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',e.id,'name',e.name,'primary_muscle',e.primary_muscle,'equipment',e.equipment,'movement_pattern',e.movement_pattern,
    'difficulty',e.difficulty,'default_tempo',e.default_tempo,'default_rest_sec',e.default_rest_sec,'prescription_unit',e.prescription_unit
  ) order by e.name),'[]'::jsonb)
  into v_catalog from public.exercises e where e.active=true;

  select jsonb_build_object(
    'program',to_jsonb(p),
    'days',coalesce((select jsonb_agg(jsonb_build_object(
      'id',pd.id,'day_number',pd.day_number,'name',pd.name,'focus',pd.focus,'estimated_minutes',pd.estimated_minutes,'notes',pd.notes,
      'exercises',coalesce((select jsonb_agg(jsonb_build_object(
        'id',pe.id,'exercise_id',pe.exercise_id,'exercise_order',pe.exercise_order,'target_sets',pe.target_sets,
        'rep_min',pe.rep_min,'rep_max',pe.rep_max,'prescription_unit',pe.prescription_unit,'rir_target',pe.rir_target,'tempo',pe.tempo,
        'rest_seconds',pe.rest_seconds,'load_strategy',pe.load_strategy,'coach_notes',pe.coach_notes,'client_notes',pe.client_notes,
        'allow_substitution',pe.allow_substitution,'initial_weight_kg',pe.initial_weight_kg
      ) order by pe.exercise_order) from public.program_exercises pe where pe.program_day_id=pd.id and pe.active=true),'[]'::jsonb)
    ) order by pd.day_number) from public.program_days pd where pd.program_id=p.id),'[]'::jsonb)
  ) into v_current_program from public.programs p where p.id=v_program.id;

  v_mesocycle:=private.compute_mesocycle_intelligence_in_org_v85(v_organization,p_client_id,v_program.id);

  v_context:=jsonb_build_object(
    'client_profile',coalesce(v_client_profile,'{}'::jsonb),
    'onboarding',coalesce(v_onboarding,'{}'::jsonb),
    'training_preferences',coalesce((select to_jsonb(tp) from public.client_training_preferences tp where tp.client_id=p_client_id),'{}'::jsonb),
    'schedule_preferences',coalesce((select to_jsonb(sp) from public.client_training_schedule_preferences sp where sp.client_id=p_client_id),'{}'::jsonb),
    'training_constraints',coalesce(v_constraints,'[]'::jsonb),
    'time_learning',coalesce(v_time_learning,'{}'::jsonb),
    'exercise_mechanical_exposures',coalesce(v_exposures,'[]'::jsonb),
    'latest_weekly_checkin',coalesce(v_weekly,'{}'::jsonb),
    'mesocycle_intelligence',coalesce(v_mesocycle,'{}'::jsonb),
    'current_draft',coalesce(v_current_program,'{}'::jsonb),
    'exercise_catalog',coalesce(v_catalog,'[]'::jsonb),
    'guardrails',jsonb_build_object('draft_only',true,'coach_review_required',true,'auto_publish',false,'blocking_conflicts_must_be_empty',true,'mesocycle_memory_is_evidence',true)
  );

  insert into public.ai_program_generations(organization_id,program_id,client_id,coach_id,scope,target_day_number,status,engine_version,idempotency_key,input_snapshot)
  values(v_organization,v_program.id,p_client_id,p_actor_id,p_scope,p_target_day_number,'prepared','cv-coach-ai-program-v85',v_key,v_context)
  returning * into v_generation;

  return jsonb_build_object('generation_id',v_generation.id,'program_id',v_generation.program_id,'client_id',v_generation.client_id,'scope',v_generation.scope,'target_day_number',v_generation.target_day_number,'status',v_generation.status,'engine_version',v_generation.engine_version,'context',v_generation.input_snapshot);
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_program_quality_audit_backend(p_actor_id uuid, p_program_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_request_role text:=coalesce(auth.role(),''); v_request_user uuid:=auth.uid(); v_organization uuid; v_client_id uuid; v_days integer;
  v_required_days integer; v_session_minutes integer; v_schedule_source text; v_available_next integer;
  v_samples integer; v_median numeric; v_factor numeric:=1; v_day_rows jsonb; v_constraints jsonb; v_safety_matches jsonb;
  v_blocked integer:=0; v_caution integer:=0; v_time_blocked integer:=0;
begin
  if p_actor_id is null or p_program_id is null then raise exception 'actor_id and program_id are required'; end if;
  if v_request_role<>'service_role' and (v_request_user is null or v_request_user<>p_actor_id) then raise exception 'actor identity mismatch'; end if;
  select organization_id,client_id into v_organization,v_client_id from public.programs where id=p_program_id;
  if v_client_id is null then raise exception 'Program not found'; end if;
  if v_request_role<>'service_role'
     and not private.actor_can_manage_client_in_org_v1(
       p_actor_id,v_organization,v_client_id
     ) then
    raise exception 'Forbidden';
  end if;

  select count(*)::integer into v_days from public.program_days where program_id=p_program_id;
  select s.training_days_per_week,s.session_minutes,s.source into v_required_days,v_session_minutes,v_schedule_source from private.get_client_training_schedule_in_org(v_organization,v_client_id) s;
  select wc.available_days_next_week into v_available_next from public.weekly_checkins wc where wc.organization_id=v_organization and wc.client_id=v_client_id order by wc.submitted_at desc limit 1;
  select t.sample_count,t.median_ratio,t.applied_factor into v_samples,v_median,v_factor from private.get_client_time_learning_in_org(v_organization,v_client_id) t;
  v_factor:=coalesce(v_factor,1);

  select coalesce(jsonb_agg(jsonb_build_object(
    'day_id',x.id,'day_number',x.day_number,'name',x.name,'model_minutes',x.estimated_minutes,
    'deterministic_minutes',x.det_minutes,'learned_minutes',ceil(x.det_minutes*v_factor)::integer,
    'effective_minutes',greatest(coalesce(x.estimated_minutes,0),ceil(x.det_minutes*v_factor)::integer),
    'max_minutes',v_session_minutes,
    'status',case when v_session_minutes is null then 'not_available' when greatest(coalesce(x.estimated_minutes,0),ceil(x.det_minutes*v_factor)::integer)>v_session_minutes then 'blocked' else 'ok' end
  ) order by x.day_number),'[]'::jsonb),
  count(*) filter(where v_session_minutes is not null and greatest(coalesce(x.estimated_minutes,0),ceil(x.det_minutes*v_factor)::integer)>v_session_minutes)::integer
  into v_day_rows,v_time_blocked
  from (select pd.*,private.estimate_program_day_minutes(pd.id) as det_minutes from public.program_days pd where pd.program_id=p_program_id) x;

  select coalesce(jsonb_agg(jsonb_build_object('constraint_code',c.constraint_code,'label',cat.label,'region',cat.region,'action',c.action,'note',c.note) order by cat.region,cat.label),'[]'::jsonb)
  into v_constraints
  from public.client_training_constraints c join public.training_constraint_catalog cat on cat.code=c.constraint_code
  where c.organization_id=v_organization and c.client_id=v_client_id and c.active=true and c.valid_from<=current_date and (c.valid_until is null or c.valid_until>=current_date);

  select coalesce(jsonb_agg(jsonb_build_object('exercise_id',e.id,'exercise_name',e.name,'day_number',pd.day_number,'constraint_code',c.constraint_code,'label',cat.label,'action',c.action,'exposure_level',eme.exposure_level) order by pd.day_number,e.name),'[]'::jsonb),
         count(*) filter(where c.action='avoid')::integer,
         count(*) filter(where c.action='caution')::integer
  into v_safety_matches,v_blocked,v_caution
  from public.program_exercises pe
  join public.program_days pd on pd.id=pe.program_day_id and pd.program_id=p_program_id
  join public.exercises e on e.id=pe.exercise_id
  join public.exercise_mechanical_exposures eme on eme.exercise_id=e.id
  join public.client_training_constraints c on c.organization_id=v_organization and c.client_id=v_client_id and c.constraint_code=eme.constraint_code and c.active=true and c.valid_from<=current_date and (c.valid_until is null or c.valid_until>=current_date)
  join public.training_constraint_catalog cat on cat.code=c.constraint_code
  where pe.active=true;

  return jsonb_build_object(
    'program_id',p_program_id,'organization_id',v_organization,'client_id',v_client_id,
    'overall_status',case when (v_required_days is not null and v_days<>v_required_days) or v_time_blocked>0 or v_blocked>0 then 'blocked' else 'ok' end,
    'schedule',jsonb_build_object('required_days',v_required_days,'program_days',v_days,'frequency_status',case when v_required_days is null then 'not_available' when v_days=v_required_days then 'ok' else 'blocked' end,'session_minutes_max',v_session_minutes,'source',v_schedule_source,'available_days_next_week',v_available_next),
    'time_learning',jsonb_build_object('sample_count',coalesce(v_samples,0),'median_ratio',v_median,'applied_factor',v_factor,'rule','Se aplica solo con 3 o más sesiones válidas; nunca reduce el tiempo estimado y se limita a 1.50x.'),
    'days',v_day_rows,
    'safety',jsonb_build_object('constraints',v_constraints,'matches',v_safety_matches,'blocked_count',v_blocked,'caution_count',v_caution,'rule','EVITAR bloquea publicación; PRECAUCIÓN requiere revisión del coach y no constituye indicación clínica.')
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.publish_program_backend_core_v100(p_actor_id uuid, p_program_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_organization uuid; v_client_id uuid; v_status public.program_status; v_days integer; v_exercises integer;
  v_required_days integer; v_session_minutes integer; v_schedule_source text;
  v_samples integer; v_median numeric; v_factor numeric:=1; v_day record; v_effective_minutes integer;
  v_request_role text:=coalesce(auth.role(),''); v_request_user uuid:=auth.uid(); v_restricted_names text;
begin
  if p_actor_id is null or p_program_id is null then raise exception 'actor_id and program_id are required'; end if;
  if v_request_role<>'service_role' and (v_request_user is null or v_request_user<>p_actor_id) then raise exception 'actor identity mismatch'; end if;
  select p.organization_id,p.client_id,p.status into v_organization,v_client_id,v_status from public.programs p where p.id=p_program_id for update;
  if v_client_id is null then raise exception 'Program not found'; end if;
  if v_request_role<>'service_role'
     and not private.actor_can_manage_client_in_org_v1(
       p_actor_id,v_organization,v_client_id
     ) then
    raise exception 'Forbidden';
  end if;
  if v_status<>'draft'::public.program_status then raise exception 'Only draft programs can be published'; end if;
  select count(*)::integer into v_days from public.program_days where program_id=p_program_id;
  select count(*)::integer into v_exercises from public.program_exercises pe join public.program_days pd on pd.id=pe.program_day_id where pd.program_id=p_program_id and pe.active=true;
  if v_days<1 or v_exercises<1 then raise exception 'Program requires at least one day and one active exercise'; end if;
  if exists(select 1 from public.program_days pd where pd.program_id=p_program_id and not exists(select 1 from public.program_exercises pe where pe.program_day_id=pd.id and pe.active=true)) then raise exception 'Each program day requires at least one active exercise'; end if;

  select s.training_days_per_week,s.session_minutes,s.source into v_required_days,v_session_minutes,v_schedule_source from private.get_client_training_schedule_in_org(v_organization,v_client_id) s;
  if v_required_days is not null and v_days<>v_required_days then raise exception 'Program has % days but client current availability requires % days per week',v_days,v_required_days; end if;
  select t.sample_count,t.median_ratio,t.applied_factor into v_samples,v_median,v_factor from private.get_client_time_learning_in_org(v_organization,v_client_id) t;
  v_factor:=coalesce(v_factor,1);
  if v_session_minutes is not null then
    for v_day in select pd.id,pd.day_number,pd.estimated_minutes,private.estimate_program_day_minutes(pd.id) as deterministic_minutes from public.program_days pd where pd.program_id=p_program_id order by pd.day_number loop
      v_effective_minutes:=greatest(coalesce(v_day.estimated_minutes,0),ceil(v_day.deterministic_minutes*v_factor)::integer);
      if v_effective_minutes>v_session_minutes then raise exception 'Day % requires about % minutes but client maximum is % minutes',v_day.day_number,v_effective_minutes,v_session_minutes; end if;
    end loop;
  end if;

  select string_agg(distinct e.name,', ' order by e.name) into v_restricted_names
  from public.program_exercises pe
  join public.program_days pd on pd.id=pe.program_day_id and pd.program_id=p_program_id
  join public.exercises e on e.id=pe.exercise_id
  join public.exercise_mechanical_exposures eme on eme.exercise_id=e.id
  join public.client_training_constraints c on c.organization_id=v_organization and c.client_id=v_client_id and c.constraint_code=eme.constraint_code and c.action='avoid' and c.active=true and c.valid_from<=current_date and (c.valid_until is null or c.valid_until>=current_date)
  where pe.active=true;
  if v_restricted_names is not null then raise exception 'Program contains exercises blocked by current client constraints: %',v_restricted_names; end if;

  update public.programs set status='archived'::public.program_status,updated_at=now() where organization_id=v_organization and client_id=v_client_id and status='active'::public.program_status and id<>p_program_id;
  update public.programs set status='active'::public.program_status,published_at=now(),updated_at=now() where id=p_program_id;
  return jsonb_build_object('program_id',p_program_id,'organization_id',v_organization,'client_id',v_client_id,'status','active','days',v_days,'exercises',v_exercises,'schedule_days_per_week',v_required_days,'session_minutes_max',v_session_minutes,'schedule_source',v_schedule_source,'time_learning_factor',v_factor,'published_at',now());
end;
$function$;

comment on index public.uq_ai_program_generations_org_idempotency is
  'F1.M1.S5 G1B3B AI generation idempotency is independent per Organization.';
comment on function public.prepare_ai_program_generation(uuid,uuid,uuid,text,integer,text) is
  'F1.M1.S5 G1B3B AI preparation binds authorization and all context inputs to Program Organization.';
comment on function public.get_program_quality_audit_backend(uuid,uuid) is
  'F1.M1.S5 G1B3B Program audit reads schedule, recovery, time-learning and constraints inside Program Organization.';
