-- CV Coach V84 — Adaptive Programming OS
-- Combines progression E2E, adaptive deload/next-block drafts and longitudinal training trends.
-- Safety invariant: V84 may prepare drafts and recommendations, never publish an active program.

begin;

create table if not exists public.adaptive_program_drafts (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.profiles(id) on delete cascade,
  source_program_id uuid not null references public.programs(id) on delete cascade,
  draft_program_id uuid not null unique references public.programs(id) on delete cascade,
  adaptation_review_id uuid references public.training_adaptation_reviews(id) on delete set null,
  mode text not null check (mode in ('deload','next_mesocycle')),
  source_state text,
  source_block_week integer check (source_block_week is null or source_block_week >= 1),
  proposal jsonb not null default '{}'::jsonb,
  status text not null default 'prepared' check (status in ('prepared','published','discarded')),
  created_by uuid not null references public.profiles(id),
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_adaptive_program_drafts_client_created_v84
  on public.adaptive_program_drafts(client_id,created_at desc);
create unique index if not exists uq_adaptive_program_drafts_review_v84
  on public.adaptive_program_drafts(adaptation_review_id)
  where adaptation_review_id is not null and status in ('prepared','published');

alter table public.adaptive_program_drafts enable row level security;
revoke all on table public.adaptive_program_drafts from anon,authenticated;
grant all on table public.adaptive_program_drafts to service_role;

-- V84 fixes the generic version clone contract: time-based exercises must preserve prescription_unit.
create or replace function public.clone_program_version_backend(p_actor_id uuid, p_source_program_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
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
  if p_actor_id is null or p_source_program_id is null then
    raise exception 'actor_id and source_program_id are required';
  end if;
  if v_auth_uid is not null and v_auth_uid <> p_actor_id then raise exception 'Forbidden'; end if;

  select p.* into v_source from public.programs p where p.id=p_source_program_id for update;
  if v_source.id is null then raise exception 'Program not found'; end if;
  if v_source.status <> 'active'::public.program_status then raise exception 'Only active programs can create a new version'; end if;

  if not exists (
    select 1 from public.profiles a
    where a.id=p_actor_id and a.status='active'::public.profile_status and a.role='admin'::public.app_role
  ) and not exists (
    select 1 from public.coach_clients cc
    join public.profiles a on a.id=cc.coach_id
    where cc.coach_id=p_actor_id and cc.client_id=v_source.client_id
      and cc.status='active'::public.coach_client_status
      and a.status='active'::public.profile_status
      and a.role in ('coach'::public.app_role,'admin'::public.app_role)
  ) then raise exception 'Forbidden'; end if;

  perform 1 from public.programs p where p.client_id=v_source.client_id for update;
  select p.id into v_existing_draft
  from public.programs p
  where p.client_id=v_source.client_id and p.status='draft'::public.program_status
  order by p.updated_at desc,p.created_at desc limit 1;
  if v_existing_draft is not null then raise exception 'Client already has a draft program'; end if;

  select coalesce(max(p.version),0)+1 into v_new_version
  from public.programs p where p.client_id=v_source.client_id;

  insert into public.programs(client_id,coach_id,name,goal,start_date,end_date,status,version)
  values(v_source.client_id,p_actor_id,v_source.name,v_source.goal,null,null,'draft'::public.program_status,v_new_version)
  returning id into v_new_program_id;

  for v_day in
    select pd.* from public.program_days pd
    where pd.program_id=p_source_program_id order by pd.day_number,pd.created_at
  loop
    insert into public.program_days(program_id,day_number,name,focus,estimated_minutes,notes)
    values(v_new_program_id,v_day.day_number,v_day.name,v_day.focus,v_day.estimated_minutes,v_day.notes)
    returning id into v_new_day_id;
    v_days:=v_days+1;

    insert into public.program_exercises(
      program_day_id,exercise_id,exercise_order,target_sets,rep_min,rep_max,prescription_unit,
      rir_target,tempo,rest_seconds,load_strategy,coach_notes,client_notes,
      allow_substitution,active,initial_weight_kg
    )
    select v_new_day_id,pe.exercise_id,pe.exercise_order,pe.target_sets,pe.rep_min,pe.rep_max,pe.prescription_unit,
      pe.rir_target,pe.tempo,pe.rest_seconds,pe.load_strategy,pe.coach_notes,pe.client_notes,
      pe.allow_substitution,pe.active,pe.initial_weight_kg
    from public.program_exercises pe
    where pe.program_day_id=v_day.id
    order by pe.exercise_order,pe.created_at;
    get diagnostics v_inserted=row_count;
    v_exercises:=v_exercises+v_inserted;
  end loop;

  return jsonb_build_object(
    'source_program_id',p_source_program_id,'program_id',v_new_program_id,
    'client_id',v_source.client_id,'status','draft','version',v_new_version,
    'days',v_days,'exercises',v_exercises,'contract','CLONE_PROGRAM_V84_PRESERVES_UNIT'
  );
end;
$$;

comment on function public.clone_program_version_backend(uuid,uuid) is
  'V84 safe version clone. Preserves reps/seconds prescription_unit and never changes the active source program.';

create or replace function public.prepare_adaptive_program_draft_v84(
  p_actor_id uuid,
  p_review_id uuid,
  p_mode text default null
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  r public.training_adaptation_reviews%rowtype;
  src public.programs%rowtype;
  v_role public.app_role;
  v_adapt jsonb;
  v_mode text;
  v_state text;
  v_block_week integer;
  v_deload boolean;
  v_existing uuid;
  v_existing_meta public.adaptive_program_drafts%rowtype;
  v_new_program uuid;
  v_new_day uuid;
  v_new_version integer;
  v_day record;
  v_inserted integer:=0;
  v_days integer:=0;
  v_exercises integer:=0;
  v_proposal jsonb;
  v_note text;
begin
  if auth.uid() is null or auth.uid()<>p_actor_id then raise exception 'Actor authentication mismatch'; end if;
  select role into v_role from public.profiles where id=p_actor_id and status='active'::public.profile_status;
  if v_role is null or v_role not in ('admin'::public.app_role,'coach'::public.app_role) then
    raise exception 'Coach/admin role required';
  end if;

  select * into r from public.training_adaptation_reviews where id=p_review_id for update;
  if not found then raise exception 'Adaptation review not found'; end if;
  if v_role='coach'::public.app_role and not exists(
    select 1 from public.coach_clients cc
    where cc.coach_id=p_actor_id and cc.client_id=r.client_id and cc.status='active'::public.coach_client_status
  ) then raise exception 'Coach is not assigned to this client'; end if;

  select * into src from public.programs where id=r.program_id for update;
  if not found then raise exception 'Source program not found'; end if;
  if src.status<>'active'::public.program_status then raise exception 'Adaptive drafts can only be prepared from the active program'; end if;

  v_adapt:=private.compute_training_adaptation_v83(r.client_id,r.program_id,now());
  v_state:=coalesce(v_adapt->>'state',r.state,'stable');
  v_block_week:=coalesce(nullif(v_adapt->>'block_week','')::integer,r.block_week);
  v_deload:=coalesce((v_adapt->>'deload_recommended')::boolean,r.deload_recommended,false);

  if p_mode is null then
    if v_deload then v_mode:='deload';
    elsif coalesce(v_block_week,0)>=6 then v_mode:='next_mesocycle';
    else raise exception 'Block is not ready for deload or next mesocycle'; end if;
  else
    v_mode:=p_mode;
  end if;
  if v_mode not in ('deload','next_mesocycle') then raise exception 'Unsupported adaptive draft mode'; end if;
  if v_mode='deload' and not v_deload then raise exception 'Current adaptive evidence does not recommend deload'; end if;
  if v_mode='next_mesocycle' and coalesce(v_block_week,0)<6 then raise exception 'Next mesocycle requires block week 6 or later'; end if;

  perform 1 from public.programs p where p.client_id=r.client_id for update;
  select p.id into v_existing from public.programs p
  where p.client_id=r.client_id and p.status='draft'::public.program_status
  order by p.updated_at desc,p.created_at desc limit 1;
  if v_existing is not null then
    select * into v_existing_meta from public.adaptive_program_drafts where draft_program_id=v_existing;
    return jsonb_build_object(
      'status','existing_draft','program_id',v_existing,'client_id',r.client_id,
      'tracked_by_v84',v_existing_meta.id is not null,
      'mode',v_existing_meta.mode,'adaptive_draft_id',v_existing_meta.id
    );
  end if;

  select coalesce(max(version),0)+1 into v_new_version from public.programs where client_id=r.client_id;
  insert into public.programs(client_id,coach_id,name,goal,start_date,end_date,status,version)
  values(
    r.client_id,p_actor_id,
    src.name||case when v_mode='deload' then ' · DELOAD' else ' · SIGUIENTE BLOQUE' end,
    src.goal,null,null,'draft'::public.program_status,v_new_version
  ) returning id into v_new_program;

  for v_day in
    select * from public.program_days where program_id=src.id order by day_number,created_at
  loop
    insert into public.program_days(program_id,day_number,name,focus,estimated_minutes,notes)
    values(
      v_new_program,v_day.day_number,v_day.name,v_day.focus,v_day.estimated_minutes,
      concat_ws(E'\n',nullif(v_day.notes,''),
        case when v_mode='deload'
          then 'V84 DELOAD: borrador conservador; revisar antes de publicar.'
          else 'V84 SIGUIENTE BLOQUE: base preservada con memoria longitudinal; revisar/regenerar antes de publicar.' end)
    ) returning id into v_new_day;
    v_days:=v_days+1;

    insert into public.program_exercises(
      program_day_id,exercise_id,exercise_order,target_sets,rep_min,rep_max,prescription_unit,
      rir_target,tempo,rest_seconds,load_strategy,coach_notes,client_notes,
      allow_substitution,active,initial_weight_kg
    )
    select
      v_new_day,pe.exercise_id,pe.exercise_order,
      case when v_mode='deload' and pe.target_sets is not null
        then greatest(1,ceil(pe.target_sets*0.60)::integer) else pe.target_sets end,
      pe.rep_min,pe.rep_max,pe.prescription_unit,
      case when v_mode='deload' then greatest(coalesce(pe.rir_target,3),3) else pe.rir_target end,
      pe.tempo,pe.rest_seconds,pe.load_strategy,
      concat_ws(E'\n',nullif(pe.coach_notes,''),
        case when v_mode='deload'
          then 'V84: volumen aproximado -40%, RIR mínimo 3 y carga inicial -10% cuando existe referencia.'
          else 'V84: conservar patrón exitoso; usar tendencias y estado adaptativo antes de cambiar volumen/ejercicio.' end),
      pe.client_notes,pe.allow_substitution,pe.active,
      case when v_mode='deload' and pe.prescription_unit='reps' and pe.initial_weight_kg is not null
        then round((pe.initial_weight_kg*0.90)*2)/2.0
        else pe.initial_weight_kg end
    from public.program_exercises pe
    where pe.program_day_id=v_day.id
    order by pe.exercise_order,pe.created_at;
    get diagnostics v_inserted=row_count;
    v_exercises:=v_exercises+v_inserted;
  end loop;

  v_proposal:=jsonb_build_object(
    'engine_version','ADAPTIVE_PROGRAMMING_V84',
    'mode',v_mode,'source_adaptation',v_adapt,
    'guardrails',jsonb_build_object(
      'draft_only',true,'auto_publish',false,'coach_review_required',true,
      'preserve_prescription_unit',true
    ),
    'strategy',case when v_mode='deload' then jsonb_build_object(
      'volume_multiplier',0.60,'rir_floor',3,'initial_load_multiplier_when_known',0.90,
      'structural_exercise_changes',false,
      'reason','Disminuir fatiga sin inventar una rutina distinta.'
    ) else jsonb_build_object(
      'carry_forward_structure',true,'use_longitudinal_trends',true,
      'increase_volume_automatically',false,'structural_changes_require_review',true,
      'reason','Crear una base segura del siguiente bloque sin asumir que más volumen equivale a mejor progreso.'
    ) end
  );

  insert into public.adaptive_program_drafts(
    client_id,source_program_id,draft_program_id,adaptation_review_id,mode,
    source_state,source_block_week,proposal,status,created_by
  ) values(
    r.client_id,src.id,v_new_program,r.id,v_mode,v_state,v_block_week,v_proposal,'prepared',p_actor_id
  ) returning * into v_existing_meta;

  v_note:='V84 preparó borrador '||v_mode||' V'||v_new_version||'. El programa activo no fue modificado.';
  update public.training_adaptation_reviews
  set status='reviewed',reviewed_by=p_actor_id,reviewed_at=now(),
      coach_notes=concat_ws(E'\n',nullif(coach_notes,''),v_note),updated_at=now()
  where id=r.id;

  return jsonb_build_object(
    'status','prepared','adaptive_draft_id',v_existing_meta.id,
    'program_id',v_new_program,'source_program_id',src.id,'client_id',r.client_id,
    'mode',v_mode,'version',v_new_version,'days',v_days,'exercises',v_exercises,
    'proposal',v_proposal,'publish_required',true,'auto_publish',false
  );
end;
$$;

comment on function public.prepare_adaptive_program_draft_v84(uuid,uuid,text) is
  'V84 prepares a conservative deload or next-mesocycle draft from the active program. Never publishes automatically.';

create or replace function private.sync_adaptive_program_draft_status_v84()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if old.status='draft'::public.program_status and new.status='active'::public.program_status then
    update public.adaptive_program_drafts
    set status='published',published_at=coalesce(new.published_at,now()),updated_at=now()
    where draft_program_id=new.id and status='prepared';
  elsif old.status='draft'::public.program_status and new.status='archived'::public.program_status then
    update public.adaptive_program_drafts
    set status='discarded',updated_at=now()
    where draft_program_id=new.id and status='prepared';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sync_adaptive_program_draft_status_v84 on public.programs;
create trigger trg_sync_adaptive_program_draft_status_v84
after update of status on public.programs
for each row when (old.status is distinct from new.status)
execute function private.sync_adaptive_program_draft_status_v84();

create or replace function public.get_adaptive_programming_center_v84(
  p_actor_id uuid,
  p_client_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_center jsonb;
  v_planning jsonb:='[]'::jsonb;
  item jsonb;
  d public.adaptive_program_drafts%rowtype;
  v_ready boolean;
  v_mode text;
begin
  v_center:=public.get_progression_center_v83(p_actor_id,p_client_id);
  for item in select value from jsonb_array_elements(coalesce(v_center->'adaptations','[]'::jsonb)) loop
    v_mode:=case
      when coalesce((item->>'deload_recommended')::boolean,false) then 'deload'
      when coalesce(nullif(item->>'block_week','')::integer,0)>=6 then 'next_mesocycle'
      else null end;
    v_ready:=v_mode is not null;
    d:=null;
    select * into d from public.adaptive_program_drafts
    where adaptation_review_id=(item->>'id')::uuid and status in ('prepared','published')
    order by created_at desc limit 1;
    v_planning:=v_planning||jsonb_build_array(jsonb_build_object(
      'adaptation_review_id',item->>'id','client_id',item->>'client_id','program_id',item->>'program_id',
      'ready',v_ready,'recommended_mode',v_mode,
      'draft',case when d.id is null then null else jsonb_build_object(
        'id',d.id,'program_id',d.draft_program_id,'mode',d.mode,'status',d.status,
        'created_at',d.created_at,'published_at',d.published_at
      ) end
    ));
  end loop;
  return v_center||jsonb_build_object(
    'engine_version','ADAPTIVE_PROGRAMMING_V84','planning',v_planning,
    'summary_v84',jsonb_build_object(
      'planning_ready',(select count(*) from jsonb_array_elements(v_planning) x where coalesce((x->>'ready')::boolean,false)),
      'prepared_drafts',(select count(*) from jsonb_array_elements(v_planning) x where x->'draft' is not null and x->'draft'<>'null'::jsonb)
    )
  );
end;
$$;

create or replace function public.get_client_training_trends_v84(
  p_actor_id uuid,
  p_client_id uuid,
  p_weeks integer default 12
) returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_role public.app_role;
  v_weeks integer:=greatest(4,least(coalesce(p_weeks,12),52));
  v_sessions jsonb;
  v_exercises jsonb;
  v_history jsonb;
  v_events jsonb;
  v_summary jsonb;
begin
  if auth.uid() is null or auth.uid()<>p_actor_id then raise exception 'Actor authentication mismatch'; end if;
  select role into v_role from public.profiles where id=p_actor_id and status='active'::public.profile_status;
  if v_role is null or v_role not in ('admin'::public.app_role,'coach'::public.app_role) then raise exception 'Coach/admin role required'; end if;
  if v_role='coach'::public.app_role and not exists(
    select 1 from public.coach_clients where coach_id=p_actor_id and client_id=p_client_id and status='active'::public.coach_client_status
  ) then raise exception 'Coach is not assigned to this client'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',x.id,'date',x.started_at,'status',x.status::text,'completion_pct',x.completion_pct,
    'duration_minutes',case when x.duration_seconds is null then null else round(x.duration_seconds/60.0,1) end,
    'total_volume',x.total_volume,'effort',x.client_effort,'fatigue',x.fatigue_score,
    'pain',x.pain_score,'program_id',x.program_id,'program_name',p.name
  ) order by x.started_at),'[]'::jsonb)
  into v_sessions
  from public.workout_sessions x left join public.programs p on p.id=x.program_id
  where x.client_id=p_client_id
    and x.status in ('completed'::public.workout_session_status,'partial'::public.workout_session_status)
    and x.started_at>=now()-(v_weeks||' weeks')::interval;

  with m as (
    select *,coalesce(finished_at,started_at) as at
    from private.training_session_exercise_metrics
    where client_id=p_client_id and done_sets>0
      and workout_status in ('completed','partial')
      and coalesce(finished_at,started_at)>=now()-(v_weeks||' weeks')::interval
  ), firsts as (
    select distinct on (exercise_id) exercise_id,max_weight,avg_reps,avg_duration_seconds,volume,at
    from m order by exercise_id,at asc
  ), lasts as (
    select distinct on (exercise_id) exercise_id,max_weight,avg_reps,avg_duration_seconds,avg_rir,volume,at
    from m order by exercise_id,at desc
  ), agg as (
    select exercise_id,max(exercise_name) exercise_name,max(prescription_unit) prescription_unit,
      count(*)::integer exposures,min(at) first_at,max(at) last_at,
      max(max_weight) peak_load,max(max_reps) peak_reps,max(max_duration_seconds) peak_duration,
      max(volume) peak_volume
    from m group by exercise_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'exercise_id',a.exercise_id,'exercise_name',a.exercise_name,'prescription_unit',a.prescription_unit,
    'exposures',a.exposures,'first_at',a.first_at,'last_at',a.last_at,
    'peak_load',a.peak_load,'peak_reps',a.peak_reps,'peak_duration_seconds',a.peak_duration,'peak_volume',a.peak_volume,
    'first_load',f.max_weight,'latest_load',l.max_weight,
    'load_delta',case when f.max_weight is null or l.max_weight is null then null else l.max_weight-f.max_weight end,
    'first_avg_reps',f.avg_reps,'latest_avg_reps',l.avg_reps,
    'first_avg_duration_seconds',f.avg_duration_seconds,'latest_avg_duration_seconds',l.avg_duration_seconds,
    'latest_avg_rir',l.avg_rir,'latest_volume',l.volume
  ) order by a.exposures desc,a.last_at desc),'[]'::jsonb)
  into v_exercises
  from agg a join firsts f using(exercise_id) join lasts l using(exercise_id);

  select coalesce(jsonb_agg(jsonb_build_object(
    'session_id',m.session_id,'exercise_id',m.exercise_id,'exercise_name',m.exercise_name,
    'prescription_unit',m.prescription_unit,'date',coalesce(m.finished_at,m.started_at),
    'done_sets',m.done_sets,'max_weight',m.max_weight,'avg_reps',m.avg_reps,'max_reps',m.max_reps,
    'avg_duration_seconds',m.avg_duration_seconds,'max_duration_seconds',m.max_duration_seconds,
    'avg_rir',m.avg_rir,'volume',m.volume
  ) order by coalesce(m.finished_at,m.started_at) desc),'[]'::jsonb)
  into v_history
  from (select * from private.training_session_exercise_metrics
        where client_id=p_client_id and done_sets>0
          and workout_status in ('completed','partial')
          and coalesce(finished_at,started_at)>=now()-(v_weeks||' weeks')::interval
        order by coalesce(finished_at,started_at) desc limit 120) m;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',ps.id,'exercise_id',ps.exercise_id,'exercise_name',e.name,'status',ps.status::text,
    'action',ps.action,'reviewed_at',ps.reviewed_at,'created_at',ps.created_at,
    'suggested_load',ps.suggested_load,'suggested_rep_min',ps.suggested_rep_min,
    'suggested_rep_max',ps.suggested_rep_max,'suggested_duration_seconds',ps.suggested_duration_seconds
  ) order by coalesce(ps.reviewed_at,ps.created_at) desc),'[]'::jsonb)
  into v_events
  from public.progression_suggestions ps join public.exercises e on e.id=ps.exercise_id
  where ps.client_id=p_client_id and ps.status in (
    'approved'::public.progression_status,'modified'::public.progression_status,
    'applied'::public.progression_status,'rejected'::public.progression_status
  ) and ps.created_at>=now()-(v_weeks||' weeks')::interval;

  select jsonb_build_object(
    'sessions_28d',count(*) filter(where started_at>=now()-interval '28 days'),
    'average_completion_28d',round(avg(completion_pct) filter(where started_at>=now()-interval '28 days'),1),
    'total_volume_28d',round(coalesce(sum(total_volume) filter(where started_at>=now()-interval '28 days'),0),1),
    'average_effort_28d',round(avg(client_effort) filter(where started_at>=now()-interval '28 days'),1),
    'pain_sessions_28d',count(*) filter(where started_at>=now()-interval '28 days' and (coalesce(pain_score,0)>=4 or coalesce(had_pain,false)))
  ) into v_summary
  from public.workout_sessions
  where client_id=p_client_id and status in ('completed'::public.workout_session_status,'partial'::public.workout_session_status);

  return jsonb_build_object(
    'engine_version','TRAINING_TRENDS_V84','client_id',p_client_id,'weeks',v_weeks,
    'summary',coalesce(v_summary,'{}'::jsonb),'sessions',v_sessions,
    'exercise_summary',v_exercises,'exercise_history',v_history,'progression_events',v_events
  );
end;
$$;

-- Dedicated service-role E2E. All synthetic rows are created inside a subtransaction and rolled back before returning.
create or replace function public.run_adaptive_programming_e2e_v84(p_run_id text default null)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_client uuid;
  v_actor uuid;
  v_program uuid;
  v_day uuid;
  v_pe public.program_exercises%rowtype;
  v_exercise uuid;
  v_source uuid;
  v_source_se uuid;
  v_suggestion uuid;
  v_next uuid;
  v_next_se uuid;
  v_set uuid;
  v_rec jsonb;
  v_review jsonb;
  v_trends jsonb;
  v_status text;
  v_target integer;
  v_result jsonb;
begin
  if coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;

  begin
    select client_id into v_client from public.cv_canary_clients
    where label='production-v76' and enabled=true limit 1;
    if v_client is null then raise exception 'V84 canary client missing'; end if;
    select id into v_actor from public.profiles
    where role='admin'::public.app_role and status='active'::public.profile_status order by created_at limit 1;
    if v_actor is null then raise exception 'V84 admin actor missing'; end if;
    select id into v_program from public.programs
    where client_id=v_client and status='active'::public.program_status order by updated_at desc limit 1;
    if v_program is null then raise exception 'V84 active canary program missing'; end if;
    select id into v_day from public.program_days where program_id=v_program order by day_number limit 1;
    select pe.* into v_pe from public.program_exercises pe
    where pe.program_day_id=v_day and pe.active=true order by pe.exercise_order limit 1;
    if v_pe.id is null then raise exception 'V84 canary exercise missing'; end if;
    v_exercise:=v_pe.exercise_id;

    insert into public.workout_sessions(
      client_id,program_id,program_day_id,started_at,finished_at,status,completion_pct,
      duration_seconds,client_effort,fatigue_score,pain_score,difficulty_level,had_pain,session_notes
    ) values(
      v_client,v_program,v_day,now()-interval '2 minutes',now()-interval '1 minute',
      'completed'::public.workout_session_status,100,60,6,3,0,3,false,
      'CV_V84_E2E_SOURCE '||coalesce(p_run_id,'local')
    ) returning id into v_source;

    insert into public.session_exercises(
      workout_session_id,program_exercise_id,exercise_id,exercise_order,status,
      target_sets_snapshot,rep_min_snapshot,rep_max_snapshot,rir_target_snapshot,
      rest_seconds_snapshot,allow_substitution_snapshot,prescription_unit_snapshot
    ) values(
      v_source,v_pe.id,v_exercise,1,'completed'::public.session_exercise_status,
      2,30,45,2,60,false,'seconds'
    ) returning id into v_source_se;

    insert into public.set_logs(session_exercise_id,set_number,duration_seconds,rir,completed,completed_at)
    values(v_source_se,1,30,2,true,now()-interval '70 seconds'),(v_source_se,2,30,2,true,now()-interval '65 seconds');

    v_rec:=private.progression_recommendation_v83(v_source,v_exercise);
    if coalesce(v_rec->>'action','')<>'build_time' or (v_rec->>'suggested_duration_seconds')::integer<>35 then
      raise exception 'V84 E2E recommendation mismatch: %',v_rec;
    end if;

    insert into public.progression_suggestions(
      client_id,exercise_id,source_session_id,previous_duration_seconds,suggested_duration_seconds,
      reason_code,reason_text,confidence,status,action,engine_version,evidence_sessions,
      confidence_band,evidence,auto_generated
    ) values(
      v_client,v_exercise,v_source,30,35,'v84_e2e','V84 isolated progression E2E',95,
      'pending'::public.progression_status,'build_time','PROGRESSION_ENGINE_V83',1,'high',v_rec,true
    ) returning id into v_suggestion;

    perform pg_catalog.set_config('request.jwt.claim.sub',v_actor::text,true);
    v_review:=public.review_progression_suggestion_v83(
      v_actor,v_suggestion,'modified',null,null,null,35,'V84 E2E conservative modification'
    );
    if coalesce(v_review->>'status','')<>'modified' then raise exception 'V84 E2E review failed'; end if;
    perform pg_catalog.set_config('cv.v83_review','',true);

    insert into public.workout_sessions(client_id,program_id,program_day_id,status,session_notes)
    values(v_client,v_program,v_day,'in_progress'::public.workout_session_status,'CV_V84_E2E_NEXT')
    returning id into v_next;

    insert into public.session_exercises(
      workout_session_id,program_exercise_id,exercise_id,exercise_order,status,
      target_sets_snapshot,rep_min_snapshot,rep_max_snapshot,rir_target_snapshot,
      rest_seconds_snapshot,allow_substitution_snapshot,prescription_unit_snapshot
    ) values(
      v_next,v_pe.id,v_exercise,1,'pending'::public.session_exercise_status,
      2,30,45,2,60,false,'seconds'
    ) returning id into v_next_se;

    insert into public.set_logs(session_exercise_id,set_number,completed)
    values(v_next_se,1,false) returning id into v_set;

    select status::text into v_status from public.progression_suggestions where id=v_suggestion;
    select suggested_duration_seconds into v_target from public.set_logs where id=v_set;
    if v_status<>'applied' or v_target<>35 then
      raise exception 'V84 E2E next-session application failed: status %, target %',v_status,v_target;
    end if;

    v_trends:=public.get_client_training_trends_v84(v_actor,v_client,12);
    if jsonb_array_length(coalesce(v_trends->'exercise_history','[]'::jsonb))<1 then
      raise exception 'V84 E2E longitudinal history missing';
    end if;

    v_result:=jsonb_build_object(
      'ok',true,'contract','CV_V84_ADAPTIVE_PROGRAMMING_E2E_OK','run_id',p_run_id,
      'recommendation_action',v_rec->>'action','review_status',v_review->>'status',
      'next_session_progression_status',v_status,'suggested_duration_seconds',v_target,
      'history_visible',true,'rollback_isolated',true
    );
    raise exception using errcode='CV084',message='rollback_v84_e2e';
  exception when sqlstate 'CV084' then
    return v_result;
  end;
end;
$$;

revoke all on function public.prepare_adaptive_program_draft_v84(uuid,uuid,text) from public,anon;
revoke all on function public.get_adaptive_programming_center_v84(uuid,uuid) from public,anon;
revoke all on function public.get_client_training_trends_v84(uuid,uuid,integer) from public,anon;
grant execute on function public.prepare_adaptive_program_draft_v84(uuid,uuid,text) to authenticated,service_role;
grant execute on function public.get_adaptive_programming_center_v84(uuid,uuid) to authenticated,service_role;
grant execute on function public.get_client_training_trends_v84(uuid,uuid,integer) to authenticated,service_role;
revoke all on function public.run_adaptive_programming_e2e_v84(text) from public,anon,authenticated;
grant execute on function public.run_adaptive_programming_e2e_v84(text) to service_role;

commit;
