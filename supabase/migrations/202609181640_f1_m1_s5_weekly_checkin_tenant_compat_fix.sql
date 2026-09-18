-- ARCH-1.0 · F1.M1.S5 hotfix — weekly check-in tenant compatibility
-- Repairs the legacy public weekly check-in RPC after uniqueness became tenant-scoped.
-- The public signature is preserved. Legacy calls are allowed only when the authenticated
-- client resolves to exactly one active canonical Organization.

create or replace function public.submit_weekly_checkin(
  p_sleep_hours_avg numeric,
  p_sleep_quality integer,
  p_energy_level integer,
  p_stress_level integer,
  p_soreness_score integer,
  p_pain_score integer,
  p_pain_notes text default null::text,
  p_motivation_level integer default null::integer,
  p_available_days_next_week integer default null::integer,
  p_notes text default null::text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_client uuid:=auth.uid();
  v_organization uuid;
  v_week date;
  v_checkin public.weekly_checkins%rowtype;
  v_event uuid;
  v_habit_logs integer:=0;
  v_habit_done integer:=0;
  v_nutrition_days integer:=0;
  v_nutrition_avg numeric;
  v_workouts integer:=0;
  v_last_workout timestamptz;
  v_risk jsonb;
begin
  if v_client is null then
    raise exception 'Authentication required';
  end if;

  if not exists(
    select 1
    from public.profiles p
    where p.id=v_client
      and p.role='client'::public.app_role
      and p.status::text='active'
  ) then
    raise exception 'Active client account required';
  end if;

  -- Legacy RPCs have no tenant argument. Never guess when the same user is
  -- active in more than one Organization.
  v_organization:=private.resolve_legacy_client_organization_v1(v_client,null);

  if p_sleep_hours_avg is not null and (p_sleep_hours_avg<0 or p_sleep_hours_avg>14) then
    raise exception 'sleep_hours_avg out of range';
  end if;
  if p_sleep_quality is not null and p_sleep_quality not between 1 and 5 then
    raise exception 'sleep_quality out of range';
  end if;
  if p_energy_level is not null and p_energy_level not between 1 and 5 then
    raise exception 'energy_level out of range';
  end if;
  if p_stress_level is not null and p_stress_level not between 1 and 5 then
    raise exception 'stress_level out of range';
  end if;
  if p_soreness_score is not null and p_soreness_score not between 0 and 10 then
    raise exception 'soreness_score out of range';
  end if;
  if p_pain_score is not null and p_pain_score not between 0 and 10 then
    raise exception 'pain_score out of range';
  end if;
  if p_motivation_level is not null and p_motivation_level not between 1 and 5 then
    raise exception 'motivation_level out of range';
  end if;
  if p_available_days_next_week is not null and p_available_days_next_week not between 0 and 7 then
    raise exception 'available_days_next_week out of range';
  end if;
  if char_length(coalesce(p_pain_notes,''))>500
     or char_length(coalesce(p_notes,''))>1000 then
    raise exception 'notes too long';
  end if;

  v_week:=coalesce(
    private.week_start_for_client(v_client),
    date_trunc('week',now() at time zone 'America/Santiago')::date
  );

  select count(*) filter(where ws.status='completed'::public.workout_session_status),
         max(ws.finished_at)
    into v_workouts,v_last_workout
  from public.workout_sessions ws
  where ws.organization_id=v_organization
    and ws.client_id=v_client
    and ws.finished_at>=now()-interval '7 days';

  -- Habit tables are still in the legacy compatibility wave. This RPC is
  -- deliberately rejected for multi-tenant clients above, so these metrics
  -- cannot mix two active tenant contexts.
  select count(*),count(*) filter(where hl.completed=true)
    into v_habit_logs,v_habit_done
  from public.habit_logs hl
  where hl.client_id=v_client
    and hl.log_date>=v_week-interval '6 days';

  select count(*),
         avg(ndl.adherence_pct) filter(where ndl.adherence_pct is not null)
    into v_nutrition_days,v_nutrition_avg
  from public.nutrition_daily_logs ndl
  where ndl.organization_id=v_organization
    and ndl.client_id=v_client
    and ndl.log_date>=v_week-interval '6 days';

  insert into public.weekly_checkins(
    organization_id,client_id,week_start,submitted_at,
    sleep_hours_avg,sleep_quality,energy_level,stress_level,soreness_score,
    pain_score,pain_notes,motivation_level,available_days_next_week,notes,
    workouts_completed_7d,habit_logs_7d,habit_completion_pct_7d,
    nutrition_days_7d,nutrition_adherence_pct_7d,last_workout_at
  )
  values(
    v_organization,v_client,v_week,now(),
    p_sleep_hours_avg,p_sleep_quality,p_energy_level,p_stress_level,p_soreness_score,
    p_pain_score,nullif(btrim(coalesce(p_pain_notes,'')),''),
    p_motivation_level,p_available_days_next_week,
    nullif(btrim(coalesce(p_notes,'')),''),
    v_workouts,v_habit_logs,
    case when v_habit_logs>0
      then round(v_habit_done::numeric*100/v_habit_logs,2)
      else null
    end,
    v_nutrition_days,round(v_nutrition_avg,2),v_last_workout
  )
  on conflict(organization_id,client_id,week_start) do update set
    submitted_at=now(),
    sleep_hours_avg=excluded.sleep_hours_avg,
    sleep_quality=excluded.sleep_quality,
    energy_level=excluded.energy_level,
    stress_level=excluded.stress_level,
    soreness_score=excluded.soreness_score,
    pain_score=excluded.pain_score,
    pain_notes=excluded.pain_notes,
    motivation_level=excluded.motivation_level,
    available_days_next_week=excluded.available_days_next_week,
    notes=excluded.notes,
    workouts_completed_7d=excluded.workouts_completed_7d,
    habit_logs_7d=excluded.habit_logs_7d,
    habit_completion_pct_7d=excluded.habit_completion_pct_7d,
    nutrition_days_7d=excluded.nutrition_days_7d,
    nutrition_adherence_pct_7d=excluded.nutrition_adherence_pct_7d,
    last_workout_at=excluded.last_workout_at,
    updated_at=now()
  returning * into v_checkin;

  v_event:=private.enqueue_event(
    'CHECKIN_SUBMITTED',
    'weekly_checkin',
    v_checkin.id,
    v_client,
    jsonb_build_object(
      'organization_id',v_organization,
      'checkin_id',v_checkin.id,
      'client_id',v_client,
      'week_start',v_checkin.week_start,
      'submitted_at',v_checkin.submitted_at,
      'sleep_hours_avg',v_checkin.sleep_hours_avg,
      'sleep_quality',v_checkin.sleep_quality,
      'energy_level',v_checkin.energy_level,
      'stress_level',v_checkin.stress_level,
      'soreness_score',v_checkin.soreness_score,
      'pain_score',v_checkin.pain_score,
      'pain_notes',v_checkin.pain_notes,
      'motivation_level',v_checkin.motivation_level,
      'available_days_next_week',v_checkin.available_days_next_week,
      'notes',v_checkin.notes,
      'workouts_completed_7d',v_checkin.workouts_completed_7d,
      'habit_logs_7d',v_checkin.habit_logs_7d,
      'habit_completion_pct_7d',v_checkin.habit_completion_pct_7d,
      'nutrition_days_7d',v_checkin.nutrition_days_7d,
      'nutrition_adherence_pct_7d',v_checkin.nutrition_adherence_pct_7d,
      'last_workout_at',v_checkin.last_workout_at
    ),
    'weekly_checkin:'||v_organization::text||':'||v_client::text||':'||v_week::text,
    v_checkin.submitted_at
  );

  v_risk:=private.assess_weekly_checkin_risk(v_checkin.id,v_event);
  perform public.ack_event_outbox(v_event);

  return jsonb_build_object(
    'organization_id',v_organization,
    'checkin',to_jsonb(v_checkin),
    'risk',v_risk,
    'event_id',v_event,
    'event_status','processed'
  );
end;
$function$;

create or replace function private.evaluate_weekly_program_review(
  p_checkin_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  c public.weekly_checkins%rowtype;
  p public.programs%rowtype;
  v_programmed_days integer:=0;
  v_reasons jsonb:='[]'::jsonb;
  v_priority text:='MEDIUM';
  v_action text:='REVIEW_PROGRAM';
  v_summary text;
  v_review public.weekly_program_reviews%rowtype;
  v_review_key text;
  v_program_age date;
  v_training_adherence numeric;
  v_has_availability boolean:=false;
  v_has_recovery boolean:=false;
  v_has_adherence boolean:=false;
  v_severity public.alert_severity:='warning'::public.alert_severity;
begin
  select * into c
  from public.weekly_checkins
  where id=p_checkin_id;

  if not found then
    return jsonb_build_object('created',false,'reason','checkin_not_found');
  end if;

  select * into p
  from public.programs
  where organization_id=c.organization_id
    and client_id=c.client_id
    and status='active'::public.program_status
  order by updated_at desc,created_at desc,id desc
  limit 1;

  if not found then
    return jsonb_build_object(
      'created',false,
      'reason','no_active_program',
      'organization_id',c.organization_id
    );
  end if;

  select count(*)::integer into v_programmed_days
  from public.program_days
  where organization_id=c.organization_id
    and program_id=p.id;

  if v_programmed_days<=0 then
    return jsonb_build_object(
      'created',false,
      'reason','active_program_has_no_days',
      'organization_id',c.organization_id,
      'program_id',p.id
    );
  end if;

  if c.available_days_next_week is not null
     and c.available_days_next_week<v_programmed_days then
    v_has_availability:=true;
    v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object(
      'code','AVAILABILITY_CONFLICT',
      'programmed_days',v_programmed_days,
      'available_days_next_week',c.available_days_next_week,
      'gap',v_programmed_days-c.available_days_next_week
    ));
    if c.available_days_next_week=0
       or v_programmed_days-c.available_days_next_week>=2 then
      v_priority:='HIGH';
    end if;
  end if;

  if c.pain_score is not null and c.pain_score>=4 then
    v_has_recovery:=true;
    v_reasons:=v_reasons||jsonb_build_array(
      jsonb_build_object('code','PAIN_SIGNAL','pain_score',c.pain_score)
    );
    if c.pain_score>=7 then v_priority:='CRITICAL';
    else v_priority:='HIGH';
    end if;
  end if;

  if c.sleep_hours_avg is not null and c.sleep_hours_avg<5
     and c.energy_level is not null and c.energy_level<=2 then
    v_has_recovery:=true;
    v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object(
      'code','LOW_SLEEP_LOW_ENERGY',
      'sleep_hours_avg',c.sleep_hours_avg,
      'energy_level',c.energy_level
    ));
    if v_priority<>'CRITICAL' then v_priority:='HIGH'; end if;
  end if;

  if c.stress_level is not null and c.stress_level>=5
     and c.energy_level is not null and c.energy_level<=2 then
    v_has_recovery:=true;
    v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object(
      'code','HIGH_STRESS_LOW_ENERGY',
      'stress_level',c.stress_level,
      'energy_level',c.energy_level
    ));
    if v_priority<>'CRITICAL' then v_priority:='HIGH'; end if;
  end if;

  if c.soreness_score is not null and c.soreness_score>=8
     and c.energy_level is not null and c.energy_level<=2 then
    v_has_recovery:=true;
    v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object(
      'code','HIGH_SORENESS_LOW_ENERGY',
      'soreness_score',c.soreness_score,
      'energy_level',c.energy_level
    ));
    if v_priority<>'CRITICAL' then v_priority:='HIGH'; end if;
  end if;

  v_program_age:=coalesce(p.start_date,p.published_at::date,p.created_at::date);
  if v_program_age<=c.week_start-7 then
    v_training_adherence:=round(
      c.workouts_completed_7d::numeric*100/greatest(v_programmed_days,1),1
    );
    if v_training_adherence<50 then
      v_has_adherence:=true;
      v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object(
        'code','LOW_TRAINING_ADHERENCE',
        'workouts_completed_7d',c.workouts_completed_7d,
        'programmed_days',v_programmed_days,
        'adherence_pct',v_training_adherence
      ));
    end if;
  end if;

  v_review_key:=c.organization_id::text||':'||c.client_id::text||':'||
                c.week_start::text||':'||p.id::text;

  if jsonb_array_length(v_reasons)=0 then
    update public.weekly_program_reviews
      set status='cleared',
          checkin_id=c.id,
          available_days_next_week=c.available_days_next_week,
          evidence=jsonb_build_object(
            'workouts_completed_7d',c.workouts_completed_7d,
            'habit_logs_7d',c.habit_logs_7d,
            'habit_completion_pct_7d',c.habit_completion_pct_7d,
            'nutrition_days_7d',c.nutrition_days_7d,
            'nutrition_adherence_pct_7d',c.nutrition_adherence_pct_7d,
            'sleep_hours_avg',c.sleep_hours_avg,
            'energy_level',c.energy_level,
            'stress_level',c.stress_level,
            'soreness_score',c.soreness_score,
            'pain_score',c.pain_score,
            'motivation_level',c.motivation_level
          ),
          updated_at=now()
    where organization_id=c.organization_id
      and client_id=c.client_id
      and week_start=c.week_start
      and program_id=p.id
      and status='pending';

    update public.coach_alerts
      set status='resolved'::public.alert_status,
          resolved_at=now(),
          updated_at=now()
    where organization_id=c.organization_id
      and coach_id=p.coach_id
      and client_id=c.client_id
      and alert_type='weekly_program_review'
      and source_data->>'review_key'=v_review_key
      and status in (
        'open'::public.alert_status,
        'acknowledged'::public.alert_status
      );

    return jsonb_build_object(
      'created',false,
      'reason','no_review_signal',
      'organization_id',c.organization_id,
      'program_id',p.id,
      'programmed_days',v_programmed_days
    );
  end if;

  if v_has_availability and v_has_recovery then
    v_action:='REVIEW_FREQUENCY_AND_RECOVERY';
  elsif v_has_recovery then
    v_action:='REVIEW_RECOVERY';
  elsif v_has_availability then
    v_action:='REVIEW_FREQUENCY';
  elsif v_has_adherence then
    v_action:='REVIEW_ADHERENCE';
  else
    v_action:='REVIEW_PROGRAM';
  end if;

  v_summary:=case v_action
    when 'REVIEW_FREQUENCY_AND_RECOVERY'
      then 'Revisar frecuencia y recuperación antes de mantener la programación semanal.'
    when 'REVIEW_RECOVERY'
      then 'Revisar recuperación antes de mantener o progresar la programación semanal.'
    when 'REVIEW_FREQUENCY'
      then 'La disponibilidad declarada es menor que los días programados; revisar la frecuencia semanal.'
    when 'REVIEW_ADHERENCE'
      then 'La adherencia reciente al entrenamiento es baja; revisar barreras antes de modificar la programación.'
    else 'Revisar la programación semanal con el contexto actual del alumno.'
  end;

  insert into public.weekly_program_reviews(
    organization_id,client_id,coach_id,program_id,checkin_id,week_start,
    programmed_days,available_days_next_week,priority,reason_codes,
    suggested_action,summary,evidence,status,reviewed_by,reviewed_at,coach_notes
  )
  values(
    c.organization_id,c.client_id,p.coach_id,p.id,c.id,c.week_start,
    v_programmed_days,c.available_days_next_week,v_priority,v_reasons,
    v_action,v_summary,
    jsonb_build_object(
      'workouts_completed_7d',c.workouts_completed_7d,
      'training_adherence_pct_7d',v_training_adherence,
      'habit_logs_7d',c.habit_logs_7d,
      'habit_completion_pct_7d',c.habit_completion_pct_7d,
      'nutrition_days_7d',c.nutrition_days_7d,
      'nutrition_adherence_pct_7d',c.nutrition_adherence_pct_7d,
      'sleep_hours_avg',c.sleep_hours_avg,
      'sleep_quality',c.sleep_quality,
      'energy_level',c.energy_level,
      'stress_level',c.stress_level,
      'soreness_score',c.soreness_score,
      'pain_score',c.pain_score,
      'pain_notes',c.pain_notes,
      'motivation_level',c.motivation_level,
      'last_workout_at',c.last_workout_at,
      'program_version',p.version
    ),
    'pending',null,null,null
  )
  on conflict(client_id,week_start,program_id) do update set
    organization_id=excluded.organization_id,
    coach_id=excluded.coach_id,
    checkin_id=excluded.checkin_id,
    programmed_days=excluded.programmed_days,
    available_days_next_week=excluded.available_days_next_week,
    priority=excluded.priority,
    reason_codes=excluded.reason_codes,
    suggested_action=excluded.suggested_action,
    summary=excluded.summary,
    evidence=excluded.evidence,
    status='pending',
    reviewed_by=null,
    reviewed_at=null,
    coach_notes=null,
    updated_at=now()
  returning * into v_review;

  if v_priority='CRITICAL' then
    v_severity:='critical'::public.alert_severity;
  else
    v_severity:='warning'::public.alert_severity;
  end if;

  update public.coach_alerts
    set severity=v_severity,
        title='Revisión semanal del programa',
        message=v_summary,
        source_data=jsonb_build_object(
          'organization_id',c.organization_id,
          'review_id',v_review.id,
          'review_key',v_review_key,
          'week_start',c.week_start,
          'program_id',p.id,
          'priority',v_priority,
          'suggested_action',v_action,
          'reason_codes',v_reasons
        ),
        updated_at=now()
  where organization_id=c.organization_id
    and coach_id=p.coach_id
    and client_id=c.client_id
    and alert_type='weekly_program_review'
    and source_data->>'review_key'=v_review_key
    and status in (
      'open'::public.alert_status,
      'acknowledged'::public.alert_status
    );

  if not found then
    insert into public.coach_alerts(
      organization_id,coach_id,client_id,alert_type,severity,
      title,message,source_data,status
    )
    values(
      c.organization_id,p.coach_id,c.client_id,'weekly_program_review',
      v_severity,'Revisión semanal del programa',v_summary,
      jsonb_build_object(
        'organization_id',c.organization_id,
        'review_id',v_review.id,
        'review_key',v_review_key,
        'week_start',c.week_start,
        'program_id',p.id,
        'priority',v_priority,
        'suggested_action',v_action,
        'reason_codes',v_reasons
      ),
      'open'::public.alert_status
    );
  end if;

  return jsonb_build_object(
    'created',true,
    'organization_id',c.organization_id,
    'review_id',v_review.id,
    'status',v_review.status,
    'priority',v_review.priority,
    'suggested_action',v_review.suggested_action,
    'reason_codes',v_review.reason_codes,
    'programmed_days',v_programmed_days,
    'available_days_next_week',c.available_days_next_week
  );
end;
$function$;

comment on function public.submit_weekly_checkin(
  numeric,integer,integer,integer,integer,integer,text,integer,integer,text
) is
  'F1.M1.S5 compatibility RPC: resolves exactly one active client Organization, scopes weekly metrics and conflict keys by tenant, and rejects ambiguous multi-tenant legacy calls.';
