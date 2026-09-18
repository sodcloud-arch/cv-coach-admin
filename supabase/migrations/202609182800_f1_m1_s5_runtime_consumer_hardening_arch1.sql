-- ARCH-1.0 · F1.M1.S5 Wave H3A — Runtime consumer tenant hardening
-- Remove legacy global Coach/Client authorization from high-value training/onboarding consumers.

create or replace function public.get_client_training_trends_v84(
  p_actor_id uuid,
  p_client_id uuid,
  p_weeks integer default 12
)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_role public.app_role;
  v_organization uuid;
  v_weeks integer:=greatest(4,least(coalesce(p_weeks,12),52));
  v_sessions jsonb;
  v_exercises jsonb;
  v_history jsonb;
  v_events jsonb;
  v_summary jsonb;
begin
  if auth.uid() is null or auth.uid()<>p_actor_id then
    raise exception 'Actor authentication mismatch';
  end if;

  select role into v_role
  from public.profiles
  where id=p_actor_id and status='active'::public.profile_status;

  if v_role is null
     or v_role not in ('admin'::public.app_role,'coach'::public.app_role) then
    raise exception 'Coach/admin role required';
  end if;

  v_organization:=private.resolve_legacy_professional_organization_v1(
    p_actor_id,p_client_id
  );

  if not (
    private.is_org_admin(v_organization)
    or private.actor_can_manage_client_in_org_v1(
      p_actor_id,v_organization,p_client_id
    )
  ) then
    raise exception 'Actor cannot manage client in organization';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',x.id,
        'date',x.started_at,
        'status',x.status::text,
        'completion_pct',x.completion_pct,
        'duration_minutes',case when x.duration_seconds is null then null else round(x.duration_seconds/60.0,1) end,
        'total_volume',x.total_volume,
        'effort',x.client_effort,
        'fatigue',x.fatigue_score,
        'pain',x.pain_score,
        'program_id',x.program_id,
        'program_name',p.name
      )
      order by x.started_at
    ),
    '[]'::jsonb
  )
  into v_sessions
  from public.workout_sessions x
  left join public.programs p
    on p.id=x.program_id
   and p.organization_id=v_organization
  where x.organization_id=v_organization
    and x.client_id=p_client_id
    and x.status in (
      'completed'::public.workout_session_status,
      'partial'::public.workout_session_status
    )
    and x.started_at>=now()-(v_weeks||' weeks')::interval;

  with m as (
    select tm.*,
           coalesce(tm.finished_at,tm.started_at) as at
    from private.training_session_exercise_metrics tm
    join public.workout_sessions ws
      on ws.id=tm.session_id
     and ws.organization_id=v_organization
    where tm.client_id=p_client_id
      and tm.done_sets>0
      and tm.workout_status in ('completed','partial')
      and coalesce(tm.finished_at,tm.started_at)>=now()-(v_weeks||' weeks')::interval
  ),
  firsts as (
    select distinct on (exercise_id)
      exercise_id,max_weight,avg_reps,avg_duration_seconds,volume,at
    from m
    order by exercise_id,at asc
  ),
  lasts as (
    select distinct on (exercise_id)
      exercise_id,max_weight,avg_reps,avg_duration_seconds,avg_rir,volume,at
    from m
    order by exercise_id,at desc
  ),
  agg as (
    select
      exercise_id,
      max(exercise_name) exercise_name,
      max(prescription_unit) prescription_unit,
      count(*)::integer exposures,
      min(at) first_at,
      max(at) last_at,
      max(max_weight) peak_load,
      max(max_reps) peak_reps,
      max(max_duration_seconds) peak_duration,
      max(volume) peak_volume
    from m
    group by exercise_id
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'exercise_id',a.exercise_id,
        'exercise_name',a.exercise_name,
        'prescription_unit',a.prescription_unit,
        'exposures',a.exposures,
        'first_at',a.first_at,
        'last_at',a.last_at,
        'peak_load',a.peak_load,
        'peak_reps',a.peak_reps,
        'peak_duration_seconds',a.peak_duration,
        'peak_volume',a.peak_volume,
        'first_load',f.max_weight,
        'latest_load',l.max_weight,
        'load_delta',case when f.max_weight is null or l.max_weight is null then null else l.max_weight-f.max_weight end,
        'first_avg_reps',f.avg_reps,
        'latest_avg_reps',l.avg_reps,
        'first_avg_duration_seconds',f.avg_duration_seconds,
        'latest_avg_duration_seconds',l.avg_duration_seconds,
        'latest_avg_rir',l.avg_rir,
        'latest_volume',l.volume
      )
      order by a.exposures desc,a.last_at desc
    ),
    '[]'::jsonb
  )
  into v_exercises
  from agg a
  join firsts f using(exercise_id)
  join lasts l using(exercise_id);

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'session_id',m.session_id,
        'exercise_id',m.exercise_id,
        'exercise_name',m.exercise_name,
        'prescription_unit',m.prescription_unit,
        'date',coalesce(m.finished_at,m.started_at),
        'done_sets',m.done_sets,
        'max_weight',m.max_weight,
        'avg_reps',m.avg_reps,
        'max_reps',m.max_reps,
        'avg_duration_seconds',m.avg_duration_seconds,
        'max_duration_seconds',m.max_duration_seconds,
        'avg_rir',m.avg_rir,
        'volume',m.volume
      )
      order by coalesce(m.finished_at,m.started_at) desc
    ),
    '[]'::jsonb
  )
  into v_history
  from (
    select tm.*
    from private.training_session_exercise_metrics tm
    join public.workout_sessions ws
      on ws.id=tm.session_id
     and ws.organization_id=v_organization
    where tm.client_id=p_client_id
      and tm.done_sets>0
      and tm.workout_status in ('completed','partial')
      and coalesce(tm.finished_at,tm.started_at)>=now()-(v_weeks||' weeks')::interval
    order by coalesce(tm.finished_at,tm.started_at) desc
    limit 120
  ) m;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',ps.id,
        'exercise_id',ps.exercise_id,
        'exercise_name',e.name,
        'status',ps.status::text,
        'action',ps.action,
        'reviewed_at',ps.reviewed_at,
        'created_at',ps.created_at,
        'suggested_load',ps.suggested_load,
        'suggested_rep_min',ps.suggested_rep_min,
        'suggested_rep_max',ps.suggested_rep_max,
        'suggested_duration_seconds',ps.suggested_duration_seconds
      )
      order by coalesce(ps.reviewed_at,ps.created_at) desc
    ),
    '[]'::jsonb
  )
  into v_events
  from public.progression_suggestions ps
  join public.exercises e on e.id=ps.exercise_id
  where ps.organization_id=v_organization
    and ps.client_id=p_client_id
    and ps.status in (
      'approved'::public.progression_status,
      'modified'::public.progression_status,
      'applied'::public.progression_status,
      'rejected'::public.progression_status
    )
    and ps.created_at>=now()-(v_weeks||' weeks')::interval;

  select jsonb_build_object(
    'sessions_28d',count(*) filter(where started_at>=now()-interval '28 days'),
    'average_completion_28d',round(avg(completion_pct) filter(where started_at>=now()-interval '28 days'),1),
    'total_volume_28d',round(coalesce(sum(total_volume) filter(where started_at>=now()-interval '28 days'),0),1),
    'average_effort_28d',round(avg(client_effort) filter(where started_at>=now()-interval '28 days'),1),
    'pain_sessions_28d',count(*) filter(
      where started_at>=now()-interval '28 days'
        and (coalesce(pain_score,0)>=4 or coalesce(had_pain,false))
    )
  )
  into v_summary
  from public.workout_sessions
  where organization_id=v_organization
    and client_id=p_client_id
    and status in (
      'completed'::public.workout_session_status,
      'partial'::public.workout_session_status
    );

  return jsonb_build_object(
    'engine_version','TRAINING_TRENDS_V84',
    'organization_id',v_organization,
    'client_id',p_client_id,
    'weeks',v_weeks,
    'summary',coalesce(v_summary,'{}'::jsonb),
    'sessions',v_sessions,
    'exercise_summary',v_exercises,
    'exercise_history',v_history,
    'progression_events',v_events
  );
end;
$function$;

create or replace function public.get_progression_center_v83(
  p_actor_id uuid,
  p_client_id uuid default null::uuid
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_role public.app_role;
  v_suggestions jsonb;
  v_adaptations jsonb;
begin
  if (select auth.uid()) is null or (select auth.uid())<>p_actor_id then
    raise exception 'Actor authentication mismatch';
  end if;

  select role into v_role
  from public.profiles
  where id=p_actor_id and status::text='active';

  if v_role is null
     or v_role not in ('admin'::public.app_role,'coach'::public.app_role) then
    raise exception 'Coach/admin role required';
  end if;

  select coalesce(jsonb_agg(row_data order by created_at desc),'[]'::jsonb)
  into v_suggestions
  from (
    select
      ps.created_at,
      jsonb_build_object(
        'id',ps.id,
        'organization_id',ps.organization_id,
        'client_id',ps.client_id,
        'client_name',btrim(coalesce(cp.first_name,'')||' '||coalesce(cp.last_name,'')),
        'exercise_id',ps.exercise_id,
        'exercise_name',e.name,
        'prescription_unit',e.prescription_unit,
        'source_session_id',ps.source_session_id,
        'program_id',ws.program_id,
        'program_name',pr.name,
        'status',ps.status::text,
        'action',ps.action,
        'engine_version',ps.engine_version,
        'previous_load',ps.previous_load,
        'previous_reps',ps.previous_reps,
        'previous_duration_seconds',ps.previous_duration_seconds,
        'suggested_load',ps.suggested_load,
        'suggested_rep_min',ps.suggested_rep_min,
        'suggested_rep_max',ps.suggested_rep_max,
        'suggested_duration_seconds',ps.suggested_duration_seconds,
        'reason_code',ps.reason_code,
        'reason_text',ps.reason_text,
        'confidence',ps.confidence,
        'confidence_band',ps.confidence_band,
        'evidence_sessions',ps.evidence_sessions,
        'evidence',ps.evidence,
        'auto_generated',ps.auto_generated,
        'created_at',ps.created_at
      ) row_data
    from public.progression_suggestions ps
    join public.profiles cp on cp.id=ps.client_id
    join public.exercises e on e.id=ps.exercise_id
    left join public.workout_sessions ws
      on ws.id=ps.source_session_id
     and ws.organization_id=ps.organization_id
    left join public.programs pr
      on pr.id=ws.program_id
     and pr.organization_id=ps.organization_id
    where ps.status='pending'::public.progression_status
      and (p_client_id is null or ps.client_id=p_client_id)
      and (
        private.is_org_admin(ps.organization_id)
        or private.actor_can_manage_client_in_org_v1(
          p_actor_id,ps.organization_id,ps.client_id
        )
      )
  ) q;

  select coalesce(jsonb_agg(row_data order by created_at desc),'[]'::jsonb)
  into v_adaptations
  from (
    select distinct on (ar.organization_id,ar.client_id,ar.program_id)
      ar.organization_id,
      ar.client_id,
      ar.program_id,
      ar.created_at,
      jsonb_build_object(
        'id',ar.id,
        'organization_id',ar.organization_id,
        'client_id',ar.client_id,
        'client_name',btrim(coalesce(cp.first_name,'')||' '||coalesce(cp.last_name,'')),
        'program_id',ar.program_id,
        'program_name',pr.name,
        'source_session_id',ar.source_session_id,
        'state',ar.state,
        'block_week',ar.block_week,
        'recent_sessions',ar.recent_sessions,
        'progress_signals',ar.progress_signals,
        'stagnation_signals',ar.stagnation_signals,
        'data_gap_signals',ar.data_gap_signals,
        'recovery_flags',ar.recovery_flags,
        'average_completion_pct',ar.average_completion_pct,
        'deload_recommended',ar.deload_recommended,
        'reason_codes',ar.reason_codes,
        'evidence',ar.evidence,
        'status',ar.status,
        'coach_notes',ar.coach_notes,
        'created_at',ar.created_at
      ) row_data
    from public.training_adaptation_reviews ar
    join public.profiles cp on cp.id=ar.client_id
    join public.programs pr
      on pr.id=ar.program_id
     and pr.organization_id=ar.organization_id
    where (p_client_id is null or ar.client_id=p_client_id)
      and (
        private.is_org_admin(ar.organization_id)
        or private.actor_can_manage_client_in_org_v1(
          p_actor_id,ar.organization_id,ar.client_id
        )
      )
    order by ar.organization_id,ar.client_id,ar.program_id,ar.created_at desc
  ) q;

  return jsonb_build_object(
    'engine_version','ADAPTIVE_PROGRESSION_V83',
    'suggestions',v_suggestions,
    'adaptations',v_adaptations,
    'summary',jsonb_build_object(
      'pending_suggestions',jsonb_array_length(v_suggestions),
      'clients_with_adaptation_state',jsonb_array_length(v_adaptations),
      'deload_recommended',(
        select count(*)
        from jsonb_array_elements(v_adaptations) x
        where coalesce((x->>'deload_recommended')::boolean,false)
      )
    )
  );
end;
$function$;

create or replace function public.get_v85_pilot_readiness(
  p_actor_id uuid,
  p_client_id uuid default null::uuid
)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_role public.app_role;
  v_rows jsonb;
begin
  if auth.uid() is null or auth.uid()<>p_actor_id then
    raise exception 'Actor authentication mismatch';
  end if;

  select role into v_role
  from public.profiles
  where id=p_actor_id and status='active'::public.profile_status;

  if v_role is null
     or v_role not in ('admin'::public.app_role,'coach'::public.app_role) then
    raise exception 'Coach/admin role required';
  end if;

  with clients as (
    select
      c.organization_id,
      c.user_id as client_id
    from public.clients c
    join public.profiles p on p.id=c.user_id
    where c.user_id is not null
      and c.status<>'archived'::public.client_status
      and p.role='client'::public.app_role
      and p.status='active'::public.profile_status
      and (p_client_id is null or c.user_id=p_client_id)
      and (
        private.is_org_admin(c.organization_id)
        or private.actor_can_manage_client_in_org_v1(
          p_actor_id,c.organization_id,c.user_id
        )
      )
  ),
  facts as (
    select
      c.organization_id,
      c.client_id,
      (
        select p.id
        from public.programs p
        where p.organization_id=c.organization_id
          and p.client_id=c.client_id
          and p.status='active'::public.program_status
        order by p.version desc nulls last,p.updated_at desc
        limit 1
      ) active_program_id,
      (
        select count(*)
        from public.programs p
        where p.organization_id=c.organization_id
          and p.client_id=c.client_id
          and p.status='draft'::public.program_status
      )::integer draft_programs,
      (
        select count(*)
        from public.workout_sessions ws
        where ws.organization_id=c.organization_id
          and ws.client_id=c.client_id
          and ws.status in (
            'completed'::public.workout_session_status,
            'partial'::public.workout_session_status
          )
          and ws.started_at>=now()-interval '42 days'
      )::integer recent_sessions,
      (
        select count(*)
        from (
          select tm.exercise_id
          from private.training_session_exercise_metrics tm
          join public.workout_sessions ws
            on ws.id=tm.session_id
           and ws.organization_id=c.organization_id
          where tm.client_id=c.client_id
            and tm.done_sets>0
            and coalesce(tm.finished_at,tm.started_at)>=now()-interval '84 days'
          group by tm.exercise_id
          having count(*)>=2
        ) q
      )::integer evidence_exercises,
      (
        select max(wc.submitted_at)
        from public.weekly_checkins wc
        where wc.organization_id=c.organization_id
          and wc.client_id=c.client_id
      ) latest_checkin_at
    from clients c
  ),
  scored as (
    select
      f.*,
      case
        when f.active_program_id is null then 'no_active_program'
        when f.draft_programs>0 then 'draft_in_progress'
        when f.recent_sessions<3 or f.evidence_exercises<2 then 'collect_more_data'
        else 'ready_observed_pilot'
      end pilot_status,
      (
        f.active_program_id is not null
        and f.draft_programs=0
        and f.recent_sessions>=3
        and f.evidence_exercises>=2
      ) ready,
      jsonb_strip_nulls(jsonb_build_object(
        'active_program',case when f.active_program_id is null then 'required' else null end,
        'draft_program',case when f.draft_programs>0 then 'finish_or_discard_existing_draft_first' else null end,
        'recent_sessions',case when f.recent_sessions<3 then 'need_at_least_3_sessions_in_42d' else null end,
        'exercise_evidence',case when f.evidence_exercises<2 then 'need_at_least_2_exercises_with_2_exposures' else null end
      )) blockers
    from facts f
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'organization_id',s.organization_id,
        'client_id',s.client_id,
        'active_program_id',s.active_program_id,
        'draft_programs',s.draft_programs,
        'recent_sessions_42d',s.recent_sessions,
        'evidence_exercises_84d',s.evidence_exercises,
        'latest_checkin_at',s.latest_checkin_at,
        'ready',s.ready,
        'pilot_status',s.pilot_status,
        'blockers',s.blockers,
        'mode','observed_only',
        'mutates_client',false,
        'auto_publish',false
      )
      order by s.ready desc,s.recent_sessions desc,s.organization_id
    ),
    '[]'::jsonb
  )
  into v_rows
  from scored s;

  return jsonb_build_object(
    'engine_version','V85_PILOT_READINESS',
    'observed_only',true,
    'clients',v_rows
  );
end;
$function$;

create or replace function public.replace_draft_program_exercise_backend(
  p_actor_id uuid,
  p_program_exercise_id uuid,
  p_new_exercise_id uuid,
  p_reason text default null::text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_request_role text:=coalesce(auth.role(),'');
  v_request_user uuid:=auth.uid();
  v_organization uuid;
  v_program_id uuid;
  v_client_id uuid;
  v_old_exercise_id uuid;
begin
  if p_actor_id is null
     or p_program_exercise_id is null
     or p_new_exercise_id is null then
    raise exception 'actor_id, program_exercise_id and new_exercise_id are required';
  end if;

  if v_request_role<>'service_role'
     and (v_request_user is null or v_request_user<>p_actor_id) then
    raise exception 'actor identity mismatch';
  end if;

  select p.organization_id,p.id,p.client_id,pe.exercise_id
  into v_organization,v_program_id,v_client_id,v_old_exercise_id
  from public.program_exercises pe
  join public.program_days pd on pd.id=pe.program_day_id
  join public.programs p on p.id=pd.program_id
  where pe.id=p_program_exercise_id
    and p.status='draft'::public.program_status
  for update of pe;

  if v_program_id is null then
    raise exception 'Draft program exercise not found';
  end if;

  if v_request_role<>'service_role' then
    if not exists (
      select 1
      from public.profiles a
      where a.id=p_actor_id
        and a.status='active'::public.profile_status
        and a.role in ('coach'::public.app_role,'admin'::public.app_role)
    ) then
      raise exception 'Forbidden';
    end if;

    if not (
      private.is_org_admin(v_organization)
      or private.actor_can_manage_client_in_org_v1(
        p_actor_id,v_organization,v_client_id
      )
    ) then
      raise exception 'Forbidden';
    end if;
  end if;

  if not exists (
    select 1 from public.exercises e
    where e.id=p_new_exercise_id and e.active=true
  ) then
    raise exception 'New exercise is not active';
  end if;

  update public.program_exercises
  set exercise_id=p_new_exercise_id,
      coach_notes=case
        when nullif(pg_catalog.btrim(p_reason),'') is null then coach_notes
        when nullif(pg_catalog.btrim(coach_notes),'') is null
          then 'Sustitución: '||pg_catalog.btrim(p_reason)
        else coach_notes||E'\nSustitución: '||pg_catalog.btrim(p_reason)
      end,
      updated_at=now()
  where id=p_program_exercise_id;

  return jsonb_build_object(
    'organization_id',v_organization,
    'program_id',v_program_id,
    'client_id',v_client_id,
    'program_exercise_id',p_program_exercise_id,
    'old_exercise_id',v_old_exercise_id,
    'new_exercise_id',p_new_exercise_id,
    'status','draft',
    'publish_required',true
  );
end;
$function$;

create or replace function public.prepare_adaptive_program_draft_v84(
  p_actor_id uuid,
  p_review_id uuid,
  p_mode text default null::text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  r public.training_adaptation_reviews%rowtype;
  src public.programs%rowtype;
  v_role public.app_role;
  v_organization uuid;
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
  if auth.uid() is null or auth.uid()<>p_actor_id then
    raise exception 'Actor authentication mismatch';
  end if;

  select role into v_role
  from public.profiles
  where id=p_actor_id and status='active'::public.profile_status;

  if v_role is null
     or v_role not in ('admin'::public.app_role,'coach'::public.app_role) then
    raise exception 'Coach/admin role required';
  end if;

  select * into r
  from public.training_adaptation_reviews
  where id=p_review_id
  for update;

  if not found then raise exception 'Adaptation review not found'; end if;

  v_organization:=r.organization_id;

  if not (
    private.is_org_admin(v_organization)
    or private.actor_can_manage_client_in_org_v1(
      p_actor_id,v_organization,r.client_id
    )
  ) then
    raise exception 'Coach is not assigned to this client in organization';
  end if;

  select * into src
  from public.programs
  where id=r.program_id
    and organization_id=v_organization
  for update;

  if not found then raise exception 'Source program not found'; end if;

  if src.status<>'active'::public.program_status then
    raise exception 'Adaptive drafts can only be prepared from the active program';
  end if;

  v_adapt:=private.compute_training_adaptation_in_org_v83(
    v_organization,r.client_id,r.program_id,now()
  );
  v_state:=coalesce(v_adapt->>'state',r.state,'stable');
  v_block_week:=coalesce(
    nullif(v_adapt->>'block_week','')::integer,
    r.block_week
  );
  v_deload:=coalesce(
    (v_adapt->>'deload_recommended')::boolean,
    r.deload_recommended,
    false
  );

  if p_mode is null then
    if v_deload then
      v_mode:='deload';
    elsif coalesce(v_block_week,0)>=6 then
      v_mode:='next_mesocycle';
    else
      raise exception 'Block is not ready for deload or next mesocycle';
    end if;
  else
    v_mode:=p_mode;
  end if;

  if v_mode not in ('deload','next_mesocycle') then
    raise exception 'Unsupported adaptive draft mode';
  end if;
  if v_mode='deload' and not v_deload then
    raise exception 'Current adaptive evidence does not recommend deload';
  end if;
  if v_mode='next_mesocycle' and coalesce(v_block_week,0)<6 then
    raise exception 'Next mesocycle requires block week 6 or later';
  end if;

  perform 1
  from public.programs p
  where p.organization_id=v_organization
    and p.client_id=r.client_id
  for update;

  select p.id into v_existing
  from public.programs p
  where p.organization_id=v_organization
    and p.client_id=r.client_id
    and p.status='draft'::public.program_status
  order by p.updated_at desc,p.created_at desc
  limit 1;

  if v_existing is not null then
    select * into v_existing_meta
    from public.adaptive_program_drafts
    where organization_id=v_organization
      and draft_program_id=v_existing;

    return jsonb_build_object(
      'status','existing_draft',
      'organization_id',v_organization,
      'program_id',v_existing,
      'client_id',r.client_id,
      'tracked_by_v84',v_existing_meta.id is not null,
      'mode',v_existing_meta.mode,
      'adaptive_draft_id',v_existing_meta.id
    );
  end if;

  select coalesce(max(version),0)+1 into v_new_version
  from public.programs
  where organization_id=v_organization
    and client_id=r.client_id;

  insert into public.programs(
    organization_id,client_id,coach_id,name,goal,start_date,end_date,status,version
  )
  values(
    v_organization,r.client_id,p_actor_id,
    src.name||case when v_mode='deload' then ' · DELOAD' else ' · SIGUIENTE BLOQUE' end,
    src.goal,null,null,'draft'::public.program_status,v_new_version
  )
  returning id into v_new_program;

  for v_day in
    select *
    from public.program_days
    where program_id=src.id
    order by day_number,created_at
  loop
    insert into public.program_days(
      program_id,day_number,name,focus,estimated_minutes,notes
    )
    values(
      v_new_program,v_day.day_number,v_day.name,v_day.focus,
      v_day.estimated_minutes,
      concat_ws(
        E'\n',
        nullif(v_day.notes,''),
        case
          when v_mode='deload'
            then 'V84 DELOAD: borrador conservador; revisar antes de publicar.'
          else 'V84 SIGUIENTE BLOQUE: base preservada con memoria longitudinal; revisar/regenerar antes de publicar.'
        end
      )
    )
    returning id into v_new_day;

    v_days:=v_days+1;

    insert into public.program_exercises(
      program_day_id,exercise_id,exercise_order,target_sets,rep_min,rep_max,
      prescription_unit,rir_target,tempo,rest_seconds,load_strategy,
      coach_notes,client_notes,allow_substitution,active,initial_weight_kg
    )
    select
      v_new_day,pe.exercise_id,pe.exercise_order,
      case
        when v_mode='deload' and pe.target_sets is not null
          then greatest(1,ceil(pe.target_sets*0.60)::integer)
        else pe.target_sets
      end,
      pe.rep_min,pe.rep_max,pe.prescription_unit,
      case
        when v_mode='deload' then greatest(coalesce(pe.rir_target,3),3)
        else pe.rir_target
      end,
      pe.tempo,pe.rest_seconds,pe.load_strategy,
      concat_ws(
        E'\n',
        nullif(pe.coach_notes,''),
        case
          when v_mode='deload'
            then 'V84: volumen aproximado -40%, RIR mínimo 3 y carga inicial -10% cuando existe referencia.'
          else 'V84: conservar patrón exitoso; usar tendencias y estado adaptativo antes de cambiar volumen/ejercicio.'
        end
      ),
      pe.client_notes,pe.allow_substitution,pe.active,
      case
        when v_mode='deload'
             and pe.prescription_unit='reps'
             and pe.initial_weight_kg is not null
          then round((pe.initial_weight_kg*0.90)*2)/2.0
        else pe.initial_weight_kg
      end
    from public.program_exercises pe
    where pe.program_day_id=v_day.id
    order by pe.exercise_order,pe.created_at;

    get diagnostics v_inserted=row_count;
    v_exercises:=v_exercises+v_inserted;
  end loop;

  v_proposal:=jsonb_build_object(
    'engine_version','ADAPTIVE_PROGRAMMING_V84',
    'mode',v_mode,
    'source_adaptation',v_adapt,
    'guardrails',jsonb_build_object(
      'draft_only',true,
      'auto_publish',false,
      'coach_review_required',true,
      'preserve_prescription_unit',true
    ),
    'strategy',case
      when v_mode='deload' then jsonb_build_object(
        'volume_multiplier',0.60,
        'rir_floor',3,
        'initial_load_multiplier_when_known',0.90,
        'structural_exercise_changes',false,
        'reason','Disminuir fatiga sin inventar una rutina distinta.'
      )
      else jsonb_build_object(
        'carry_forward_structure',true,
        'use_longitudinal_trends',true,
        'increase_volume_automatically',false,
        'structural_changes_require_review',true,
        'reason','Crear una base segura del siguiente bloque sin asumir que más volumen equivale a mejor progreso.'
      )
    end
  );

  insert into public.adaptive_program_drafts(
    organization_id,client_id,source_program_id,draft_program_id,
    adaptation_review_id,mode,source_state,source_block_week,
    proposal,status,created_by
  )
  values(
    v_organization,r.client_id,src.id,v_new_program,r.id,
    v_mode,v_state,v_block_week,v_proposal,'prepared',p_actor_id
  )
  returning * into v_existing_meta;

  v_note:='V84 preparó borrador '||v_mode||' V'||v_new_version||
          '. El programa activo no fue modificado.';

  update public.training_adaptation_reviews
  set status='reviewed',
      reviewed_by=p_actor_id,
      reviewed_at=now(),
      coach_notes=concat_ws(E'\n',nullif(coach_notes,''),v_note),
      updated_at=now()
  where id=r.id
    and organization_id=v_organization;

  return jsonb_build_object(
    'status','prepared',
    'organization_id',v_organization,
    'adaptive_draft_id',v_existing_meta.id,
    'program_id',v_new_program,
    'source_program_id',src.id,
    'client_id',r.client_id,
    'mode',v_mode,
    'version',v_new_version,
    'days',v_days,
    'exercises',v_exercises,
    'proposal',v_proposal,
    'publish_required',true,
    'auto_publish',false
  );
end;
$function$;

create or replace function public.review_onboarding_backend(
  p_actor_id uuid,
  p_client_id uuid,
  p_decision text,
  p_note text default null::text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_request_role text:=coalesce(auth.role(),'');
  v_request_user uuid:=auth.uid();
  v_actor_role text;
  v_current_status text;
  v_organization uuid;
  v_client_entity uuid;
  v_coach_entity uuid;
  v_assignment_role public.client_coach_assignment_role;
begin
  if p_actor_id is null or p_client_id is null then
    raise exception 'actor_id and client_id are required';
  end if;

  if v_request_role<>'service_role'
     and (v_request_user is null or v_request_user<>p_actor_id) then
    raise exception 'actor identity mismatch';
  end if;

  select role::text into v_actor_role
  from public.profiles
  where id=p_actor_id
    and status::text='active';

  if v_actor_role not in ('admin','coach') then
    raise exception 'actor is not authorized to review onboarding';
  end if;

  v_organization:=private.resolve_legacy_professional_organization_v1(
    p_actor_id,p_client_id
  );

  if not (
    private.is_org_admin(v_organization)
    or private.actor_can_manage_client_in_org_v1(
      p_actor_id,v_organization,p_client_id
    )
  ) then
    raise exception 'actor is not assigned to this client in organization';
  end if;

  select c.id into v_client_entity
  from public.clients c
  where c.organization_id=v_organization
    and c.user_id=p_client_id
    and c.status<>'archived'::public.client_status;

  select onboarding_status::text into v_current_status
  from public.client_profiles
  where organization_id=v_organization
    and client_id=p_client_id
  for update;

  if v_current_status is null then
    raise exception 'client profile not found';
  end if;

  if lower(p_decision)='approve' then
    update public.client_profiles
    set onboarding_status='approved'::public.onboarding_status,
        start_date=coalesce(start_date,current_date),
        updated_at=now()
    where organization_id=v_organization
      and client_id=p_client_id;

    select cp.id into v_coach_entity
    from public.coach_profiles cp
    where cp.organization_id=v_organization
      and cp.user_id=p_actor_id
      and cp.status='active'::public.coach_profile_status
    limit 1;

    if v_coach_entity is not null
       and not exists(
         select 1
         from public.client_coach_assignments a
         where a.organization_id=v_organization
           and a.client_id=v_client_entity
           and a.coach_id=v_coach_entity
           and a.status='active'::public.client_coach_assignment_status
       ) then
      v_assignment_role:=case
        when exists(
          select 1
          from public.client_coach_assignments a
          where a.organization_id=v_organization
            and a.client_id=v_client_entity
            and a.assignment_role='primary'::public.client_coach_assignment_role
            and a.status='active'::public.client_coach_assignment_status
        )
        then 'secondary'::public.client_coach_assignment_role
        else 'primary'::public.client_coach_assignment_role
      end;

      insert into public.client_coach_assignments(
        organization_id,client_id,coach_id,assignment_role,
        status,assigned_at,assigned_by
      )
      values(
        v_organization,v_client_entity,v_coach_entity,v_assignment_role,
        'active'::public.client_coach_assignment_status,
        now(),p_actor_id
      );
    end if;

    if not exists(
      select 1
      from public.coach_clients cc
      where cc.organization_id=v_organization
        and cc.coach_id=p_actor_id
        and cc.client_id=p_client_id
        and cc.status='active'::public.coach_client_status
    ) then
      insert into public.coach_clients(
        organization_id,coach_id,client_id,status,assigned_at
      )
      values(
        v_organization,p_actor_id,p_client_id,
        'active'::public.coach_client_status,
        now()
      );
    end if;

    insert into public.notifications(
      user_id,type,title,body,action_url,metadata
    )
    values(
      p_client_id,
      'onboarding_approved',
      'Tu evaluación fue aprobada',
      'Tu coach ya revisó tu información. Tu plan está listo para la siguiente etapa.',
      '/',
      jsonb_build_object(
        'organization_id',v_organization,
        'reviewed_by',p_actor_id
      )
    );

  elsif lower(p_decision) in ('request_changes','changes') then
    update public.client_profiles
    set onboarding_status='in_progress'::public.onboarding_status,
        updated_at=now()
    where organization_id=v_organization
      and client_id=p_client_id;

    insert into public.notifications(
      user_id,type,title,body,action_url,metadata
    )
    values(
      p_client_id,
      'onboarding_changes_requested',
      'Necesitamos completar tu evaluación',
      coalesce(
        nullif(trim(p_note),''),
        'Tu coach necesita que revises algunos datos de tu evaluación.'
      ),
      '/',
      jsonb_build_object(
        'organization_id',v_organization,
        'reviewed_by',p_actor_id
      )
    );
  else
    raise exception 'decision must be approve or request_changes';
  end if;

  if p_note is not null and length(trim(p_note))>0 then
    insert into public.coach_client_notes(
      organization_id,coach_id,client_id,note,pinned
    )
    values(
      v_organization,p_actor_id,p_client_id,trim(p_note),false
    );
  end if;

  return jsonb_build_object(
    'organization_id',v_organization,
    'client_id',p_client_id,
    'decision',lower(p_decision),
    'onboarding_status',(
      select onboarding_status::text
      from public.client_profiles
      where organization_id=v_organization
        and client_id=p_client_id
    ),
    'assigned_to_actor',exists(
      select 1
      from public.coach_profiles cp
      join public.client_coach_assignments a
        on a.organization_id=cp.organization_id
       and a.coach_id=cp.id
       and a.status='active'::public.client_coach_assignment_status
      join public.clients c
        on c.organization_id=a.organization_id
       and c.id=a.client_id
      where cp.organization_id=v_organization
        and cp.user_id=p_actor_id
        and c.user_id=p_client_id
    )
  );
end;
$function$;

comment on function public.get_client_training_trends_v84(uuid,uuid,integer) is
  'F1.M1.S5 H3A: legacy client trends wrapper resolves one canonical Organization and scopes all training evidence.';
comment on function public.get_progression_center_v83(uuid,uuid) is
  'F1.M1.S5 H3A: progression/adaptation center authorizes every row through its canonical Organization.';
comment on function public.get_v85_pilot_readiness(uuid,uuid) is
  'F1.M1.S5 H3A: V85 readiness is Organization-aware and can represent the same user independently across tenants.';
comment on function public.replace_draft_program_exercise_backend(uuid,uuid,uuid,text) is
  'F1.M1.S5 H3A: draft replacement derives tenant from the Program object and uses canonical authorization.';
comment on function public.prepare_adaptive_program_draft_v84(uuid,uuid,text) is
  'F1.M1.S5 H3A: adaptive draft lifecycle is bound to the adaptation review Program Organization.';
comment on function public.review_onboarding_backend(uuid,uuid,text,text) is
  'F1.M1.S5 H3A: onboarding review authenticates actor and writes canonical + legacy shadow rows with explicit Organization.';
