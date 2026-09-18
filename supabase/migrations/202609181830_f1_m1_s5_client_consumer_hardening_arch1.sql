-- ARCH-1.0 · F1.M1.S5 Wave C3B — client consumer hardening
-- Moves the primary onboarding/training-preference consumers to explicit tenant context
-- while preserving all public signatures and the temporary global compatibility keys.

create or replace function private.actor_can_manage_client_in_org_v1(
  p_actor_id uuid,
  p_organization_id uuid,
  p_client_user_id uuid
)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select coalesce(
    exists(
      select 1
      from public.clients c
      join public.organization_members om
        on om.organization_id=c.organization_id
       and om.user_id=p_actor_id
       and om.status='active'::public.organization_member_status
      where c.organization_id=p_organization_id
        and c.user_id=p_client_user_id
        and c.status<>'archived'::public.client_status
        and om.role in (
          'owner'::public.organization_member_role,
          'org_admin'::public.organization_member_role
        )
    )
    or exists(
      select 1
      from public.clients c
      join public.coach_profiles cp
        on cp.organization_id=c.organization_id
       and cp.user_id=p_actor_id
       and cp.status='active'::public.coach_profile_status
      join public.client_coach_assignments a
        on a.organization_id=c.organization_id
       and a.client_id=c.id
       and a.coach_id=cp.id
       and a.status='active'::public.client_coach_assignment_status
      where c.organization_id=p_organization_id
        and c.user_id=p_client_user_id
        and c.status<>'archived'::public.client_status
    ),
    false
  )
$function$;

create or replace function private.week_start_for_client_in_org(
  p_organization_id uuid,
  p_client_id uuid
)
returns date
language sql
stable security definer
set search_path to ''
as $function$
  select date_trunc(
    'week',
    now() at time zone coalesce(
      nullif(cp.timezone,''),
      'America/Santiago'
    )
  )::date
  from public.client_profiles cp
  where cp.organization_id=p_organization_id
    and cp.client_id=p_client_id
$function$;

create or replace function private.week_start_for_client(
  p_client_id uuid
)
returns date
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

  return private.week_start_for_client_in_org(
    v_organization,p_client_id
  );
end;
$function$;

create or replace function private.get_client_training_schedule_in_org(
  p_organization_id uuid,
  p_client_id uuid
)
returns table(
  training_days_per_week integer,
  session_minutes integer,
  source text
)
language sql
stable security definer
set search_path to ''
as $function$
  with pref as (
    select
      p.client_id,
      p.training_days_per_week::integer as training_days_per_week,
      p.session_minutes::integer as session_minutes,
      p.source
    from public.client_training_schedule_preferences p
    where p.organization_id=p_organization_id
      and p.client_id=p_client_id
  ),
  onboarding as (
    select
      max(
        case
          when r.question_key in (
            'training_days_per_week','weekly_availability'
          )
          and trim(both '"' from r.response_value::text) ~ '^[0-9]+$'
          then trim(both '"' from r.response_value::text)::integer
        end
      ) as training_days_per_week,
      max(
        case
          when r.question_key in (
            'session_minutes','session_duration_minutes'
          )
          and trim(both '"' from r.response_value::text) ~ '^[0-9]+$'
          then trim(both '"' from r.response_value::text)::integer
        end
      ) as session_minutes
    from public.onboarding_responses r
    where r.organization_id=p_organization_id
      and r.client_id=p_client_id
  )
  select
    coalesce(p.training_days_per_week,o.training_days_per_week),
    coalesce(p.session_minutes,o.session_minutes),
    case
      when p.client_id is not null then p.source
      when o.training_days_per_week is not null
        or o.session_minutes is not null then 'onboarding'
      else 'unknown'
    end
  from onboarding o
  left join pref p on true
$function$;

create or replace function private.get_client_training_schedule(
  p_client_id uuid
)
returns table(
  training_days_per_week integer,
  session_minutes integer,
  source text
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
  from private.get_client_training_schedule_in_org(
    v_organization,p_client_id
  );
end;
$function$;

create or replace function private.inject_ai_generation_quality_context()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
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
  from private.get_client_time_learning(new.client_id) t;

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

create or replace function private.enqueue_weekly_checkin_reminders()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  r record;
  v_inserted integer:=0;
  v_skipped_completed integer:=0;
  v_skipped_demo integer:=0;
  v_week date;
  v_local timestamp;
  v_hour integer;
begin
  for r in
    select
      c.organization_id,
      c.user_id as client_id,
      coalesce(nullif(cp.timezone,''),'America/Santiago') as timezone
    from public.clients c
    join public.profiles p
      on p.id=c.user_id
     and p.role='client'::public.app_role
     and p.status::text='active'
    left join public.client_profiles cp
      on cp.organization_id=c.organization_id
     and cp.client_id=c.user_id
    where c.user_id is not null
      and c.status<>'archived'::public.client_status
  loop
    if private.is_demo_client(r.client_id) then
      v_skipped_demo:=v_skipped_demo+1;
      continue;
    end if;

    begin
      v_local:=now() at time zone r.timezone;
    exception when others then
      v_local:=now() at time zone 'America/Santiago';
    end;

    v_week:=date_trunc('week',v_local)::date;
    v_hour:=extract(hour from v_local)::integer;

    if v_local<date_trunc('week',v_local)+interval '9 hours'
       or v_hour<9
       or v_hour>=20 then
      continue;
    end if;

    if exists(
      select 1
      from public.weekly_checkins c
      where c.organization_id=r.organization_id
        and c.client_id=r.client_id
        and c.week_start=v_week
    ) then
      v_skipped_completed:=v_skipped_completed+1;
      continue;
    end if;

    if exists(
      select 1
      from public.notifications n
      where n.user_id=r.client_id
        and n.type='weekly_checkin_due'
        and n.metadata->>'organization_id'=r.organization_id::text
        and n.metadata->>'week_start'=v_week::text
    ) then
      continue;
    end if;

    insert into public.notifications(
      user_id,type,title,body,action_url,metadata
    )
    values(
      r.client_id,
      'weekly_checkin_due',
      'Tu check-in semanal está pendiente',
      'Cuéntanos cómo llegas esta semana: sueño, energía, estrés y molestias. Ve a Progreso y completa el check-in en aproximadamente 1 minuto.',
      null,
      jsonb_build_object(
        'organization_id',r.organization_id,
        'week_start',v_week,
        'source','weekly_checkin_reminder',
        'timezone',r.timezone
      )
    );

    v_inserted:=v_inserted+1;
  end loop;

  return jsonb_build_object(
    'inserted',v_inserted,
    'skipped_completed',v_skipped_completed,
    'skipped_demo',v_skipped_demo
  );
end;
$function$;

create or replace function private.enqueue_workout_reminders_v101()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  r record;
  v_local timestamp;
  v_today date;
  v_time time;
  v_dow integer;
  v_day_match boolean;
  v_inserted integer:=0;
begin
  for r in
    select
      c.organization_id,
      c.user_id as user_id,
      pref.timezone,
      pref.workout_reminder_time,
      (
        select o.response_value::text
        from public.onboarding_responses o
        where o.organization_id=c.organization_id
          and o.client_id=c.user_id
          and o.question_key='preferred_training_days'
        order by o.created_at desc
        limit 1
      ) as preferred_days
    from public.clients c
    join public.profiles p
      on p.id=c.user_id
     and p.role::text='client'
     and p.status::text='active'
    join public.push_preferences_v101 pref
      on pref.user_id=c.user_id
    where c.user_id is not null
      and c.status<>'archived'::public.client_status
      and pref.enabled=true
      and pref.training_reminders=true
      and pref.workout_reminder_time is not null
      and exists(
        select 1
        from public.push_subscriptions_v101 s
        where s.user_id=c.user_id
          and s.enabled=true
      )
      and exists(
        select 1
        from public.programs pr
        where pr.organization_id=c.organization_id
          and pr.client_id=c.user_id
          and pr.status::text='active'
      )
  loop
    begin
      v_local:=now() at time zone coalesce(
        nullif(r.timezone,''),
        'America/Santiago'
      );
    exception when others then
      v_local:=now() at time zone 'America/Santiago';
    end;

    v_today:=v_local::date;
    v_time:=v_local::time;
    v_dow:=extract(isodow from v_local)::int;

    if v_time<r.workout_reminder_time
       or v_time>=r.workout_reminder_time+interval '10 minutes' then
      continue;
    end if;

    v_day_match:=case v_dow
      when 1 then lower(coalesce(r.preferred_days,'')) like '%lunes%'
      when 2 then lower(coalesce(r.preferred_days,'')) like '%martes%'
      when 3 then lower(coalesce(r.preferred_days,'')) like '%miércoles%'
        or lower(coalesce(r.preferred_days,'')) like '%miercoles%'
      when 4 then lower(coalesce(r.preferred_days,'')) like '%jueves%'
      when 5 then lower(coalesce(r.preferred_days,'')) like '%viernes%'
      when 6 then lower(coalesce(r.preferred_days,'')) like '%sábado%'
        or lower(coalesce(r.preferred_days,'')) like '%sabado%'
      when 7 then lower(coalesce(r.preferred_days,'')) like '%domingo%'
      else false
    end;

    if not v_day_match then
      continue;
    end if;

    if exists(
      select 1
      from public.workout_sessions ws
      where ws.organization_id=r.organization_id
        and ws.client_id=r.user_id
        and ws.status::text in ('completed','partial')
        and (
          coalesce(ws.finished_at,ws.started_at,ws.created_at)
          at time zone coalesce(
            nullif(r.timezone,''),
            'America/Santiago'
          )
        )::date=v_today
    ) then
      continue;
    end if;

    if exists(
      select 1
      from public.notifications n
      where n.user_id=r.user_id
        and n.type='workout_reminder'
        and n.metadata->>'organization_id'=r.organization_id::text
        and n.metadata->>'local_date'=v_today::text
    ) then
      continue;
    end if;

    insert into public.notifications(
      user_id,type,title,body,action_url,metadata
    )
    values(
      r.user_id,
      'workout_reminder',
      'Tu entrenamiento de hoy',
      'Tienes una sesión programada para hoy. Abre CV Coach cuando estés listo para comenzar.',
      '/routine',
      jsonb_build_object(
        'organization_id',r.organization_id,
        'source','push_v101_workout_reminder',
        'local_date',v_today,
        'timezone',r.timezone
      )
    );

    v_inserted:=v_inserted+1;
  end loop;

  return jsonb_build_object(
    'inserted',v_inserted,
    'version','PUSH_NOTIFICATIONS_OS_V101'
  );
end;
$function$;

create or replace function public.replace_client_training_constraints_backend(
  p_actor_id uuid,
  p_client_id uuid,
  p_constraints jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_request_role text:=coalesce(auth.role(),'');
  v_request_user uuid:=auth.uid();
  v_item jsonb;
  v_code text;
  v_action text;
  v_note text;
  v_count integer:=0;
  v_organization uuid;
begin
  if p_actor_id is null or p_client_id is null then
    raise exception 'actor_id and client_id are required';
  end if;
  if p_constraints is null or jsonb_typeof(p_constraints)<>'array' then
    raise exception 'constraints must be an array';
  end if;
  if jsonb_array_length(p_constraints)>30 then
    raise exception 'too many constraints';
  end if;
  if v_request_role<>'service_role'
     and (v_request_user is null or v_request_user<>p_actor_id) then
    raise exception 'actor identity mismatch';
  end if;

  v_organization:=private.resolve_legacy_professional_organization_v1(
    p_actor_id,p_client_id
  );

  if not private.actor_can_manage_client_in_org_v1(
    p_actor_id,v_organization,p_client_id
  ) then
    raise exception 'Forbidden';
  end if;

  update public.client_training_constraints
  set active=false,
      updated_by=p_actor_id,
      updated_at=now()
  where organization_id=v_organization
    and client_id=p_client_id
    and active=true;

  for v_item in
    select value from jsonb_array_elements(p_constraints)
  loop
    v_code:=nullif(btrim(v_item->>'constraint_code'),'');
    v_action:=nullif(btrim(v_item->>'action'),'');
    v_note:=nullif(
      left(btrim(coalesce(v_item->>'note','')),500),
      ''
    );

    if v_code is null
       or not exists(
         select 1
         from public.training_constraint_catalog c
         where c.code=v_code and c.active=true
       ) then
      raise exception 'invalid constraint_code';
    end if;

    if v_action not in ('caution','avoid') then
      raise exception 'invalid constraint action';
    end if;

    insert into public.client_training_constraints(
      organization_id,client_id,constraint_code,action,note,
      active,source,updated_by,valid_from,valid_until,updated_at
    )
    values(
      v_organization,p_client_id,v_code,v_action,v_note,
      true,'coach',p_actor_id,current_date,null,now()
    )
    on conflict(client_id,constraint_code) do update set
      organization_id=excluded.organization_id,
      action=excluded.action,
      note=excluded.note,
      active=true,
      source='coach',
      updated_by=p_actor_id,
      valid_from=current_date,
      valid_until=null,
      updated_at=now();

    v_count:=v_count+1;
  end loop;

  return jsonb_build_object(
    'organization_id',v_organization,
    'client_id',p_client_id,
    'active_constraints',v_count,
    'updated_at',now()
  );
end;
$function$;

create or replace function public.set_client_training_focus_backend(
  p_actor_id uuid,
  p_client_id uuid,
  p_muscle_focus text[]
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_request_role text:=coalesce(auth.role(),'');
  v_request_user uuid:=auth.uid();
  v_focus text[];
  v_organization uuid;
  v_allowed constant text[]:=array[
    'full_body','glutes','quadriceps','hamstrings','calves',
    'back','chest','shoulders','biceps','triceps','core'
  ];
begin
  if p_actor_id is null or p_client_id is null then
    raise exception 'actor_id and client_id are required';
  end if;

  if v_request_role<>'service_role'
     and (v_request_user is null or v_request_user<>p_actor_id) then
    raise exception 'actor identity mismatch';
  end if;

  v_organization:=private.resolve_legacy_professional_organization_v1(
    p_actor_id,p_client_id
  );

  if not private.actor_can_manage_client_in_org_v1(
    p_actor_id,v_organization,p_client_id
  ) then
    raise exception 'Forbidden';
  end if;

  select coalesce(array_agg(x order by x),array[]::text[])
  into v_focus
  from (
    select distinct lower(btrim(v)) as x
    from unnest(coalesce(p_muscle_focus,array[]::text[])) v
    where nullif(btrim(v),'') is not null
  ) q;

  if cardinality(v_focus)<1 then
    raise exception 'At least one muscle focus is required';
  end if;
  if not (v_focus<@v_allowed) then
    raise exception 'Invalid muscle focus';
  end if;
  if 'full_body'=any(v_focus) and cardinality(v_focus)<>1 then
    raise exception 'full_body must be exclusive';
  end if;

  insert into public.client_training_preferences(
    organization_id,client_id,muscle_focus,source,updated_by
  )
  values(
    v_organization,p_client_id,v_focus,'coach',p_actor_id
  )
  on conflict(client_id) do update set
    organization_id=excluded.organization_id,
    muscle_focus=excluded.muscle_focus,
    source='coach',
    updated_by=p_actor_id,
    updated_at=now();

  return jsonb_build_object(
    'organization_id',v_organization,
    'client_id',p_client_id,
    'muscle_focus',to_jsonb(v_focus),
    'source','coach',
    'updated_at',now()
  );
end;
$function$;

create or replace function public.set_client_training_schedule_backend(
  p_actor_id uuid,
  p_client_id uuid,
  p_training_days_per_week integer,
  p_session_minutes integer
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_request_role text:=coalesce(auth.role(),'');
  v_request_user uuid:=auth.uid();
  v_row public.client_training_schedule_preferences%rowtype;
  v_organization uuid;
begin
  if p_actor_id is null or p_client_id is null then
    raise exception 'actor_id and client_id are required';
  end if;
  if p_training_days_per_week is null
     or p_training_days_per_week not between 1 and 7 then
    raise exception 'training_days_per_week must be between 1 and 7';
  end if;
  if p_session_minutes is null
     or p_session_minutes not between 10 and 240 then
    raise exception 'session_minutes must be between 10 and 240';
  end if;
  if v_request_role<>'service_role'
     and (v_request_user is null or v_request_user<>p_actor_id) then
    raise exception 'actor identity mismatch';
  end if;

  v_organization:=private.resolve_legacy_professional_organization_v1(
    p_actor_id,p_client_id
  );

  if not private.actor_can_manage_client_in_org_v1(
    p_actor_id,v_organization,p_client_id
  ) then
    raise exception 'Forbidden';
  end if;

  insert into public.client_training_schedule_preferences(
    organization_id,client_id,training_days_per_week,
    session_minutes,source,updated_by,updated_at
  )
  values(
    v_organization,p_client_id,p_training_days_per_week,
    p_session_minutes,'coach',p_actor_id,now()
  )
  on conflict(client_id) do update set
    organization_id=excluded.organization_id,
    training_days_per_week=excluded.training_days_per_week,
    session_minutes=excluded.session_minutes,
    source='coach',
    updated_by=p_actor_id,
    updated_at=now()
  returning * into v_row;

  return jsonb_build_object(
    'organization_id',v_organization,
    'client_id',v_row.client_id,
    'training_days_per_week',v_row.training_days_per_week,
    'session_minutes',v_row.session_minutes,
    'source',v_row.source,
    'updated_at',v_row.updated_at
  );
end;
$function$;

create or replace function public.submit_onboarding_backend(
  p_actor_id uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_role text;
  v_status text;
  v_key text;
  v_value jsonb;
  v_focus text[];
  v_organization uuid;
  v_allowed constant text[]:=array[
    'training_days_per_week','session_minutes','equipment',
    'preferred_training_days','pain_injuries','limitations',
    'sleep_hours','daily_steps_baseline','notes_for_coach','muscle_focus'
  ];
  v_allowed_focus constant text[]:=array[
    'full_body','glutes','quadriceps','hamstrings','calves',
    'back','chest','shoulders','biceps','triceps','core'
  ];
begin
  if p_actor_id is null or p_payload is null then
    raise exception 'actor_id and payload are required';
  end if;

  select p.role::text into v_role
  from public.profiles p
  where p.id=p_actor_id
    and p.status::text='active';

  if v_role<>'client' then
    raise exception 'only active clients can submit onboarding';
  end if;

  v_organization:=private.resolve_legacy_client_organization_v1(
    p_actor_id,null
  );

  select cp.onboarding_status::text into v_status
  from public.client_profiles cp
  where cp.organization_id=v_organization
    and cp.client_id=p_actor_id
  for update;

  if v_status='approved' then
    raise exception 'onboarding is already approved';
  end if;

  update public.profiles
  set first_name=coalesce(
        nullif(btrim(p_payload->>'first_name'),''),
        first_name
      ),
      last_name=coalesce(
        nullif(btrim(p_payload->>'last_name'),''),
        last_name
      ),
      phone=coalesce(
        nullif(btrim(p_payload->>'phone'),''),
        phone
      ),
      updated_at=now()
  where id=p_actor_id;

  insert into public.client_profiles(
    organization_id,client_id,birth_date,gender,height_cm,
    current_weight_kg,experience_level,primary_goal,secondary_goal,
    timezone,onboarding_status
  )
  values(
    v_organization,
    p_actor_id,
    nullif(p_payload->>'birth_date','')::date,
    nullif(btrim(p_payload->>'gender'),''),
    nullif(p_payload->>'height_cm','')::numeric,
    nullif(p_payload->>'current_weight_kg','')::numeric,
    nullif(p_payload->>'experience_level','')::public.experience_level,
    nullif(btrim(p_payload->>'primary_goal'),''),
    nullif(btrim(p_payload->>'secondary_goal'),''),
    coalesce(
      nullif(btrim(p_payload->>'timezone'),''),
      'America/Santiago'
    ),
    'completed'::public.onboarding_status
  )
  on conflict(client_id) do update set
    organization_id=excluded.organization_id,
    birth_date=excluded.birth_date,
    gender=excluded.gender,
    height_cm=excluded.height_cm,
    current_weight_kg=excluded.current_weight_kg,
    experience_level=excluded.experience_level,
    primary_goal=excluded.primary_goal,
    secondary_goal=excluded.secondary_goal,
    timezone=excluded.timezone,
    onboarding_status='completed'::public.onboarding_status,
    updated_at=now();

  if jsonb_typeof(p_payload->'answers')='object' then
    for v_key,v_value in
      select key,value
      from jsonb_each(p_payload->'answers')
    loop
      if v_key=any(v_allowed) then
        insert into public.onboarding_responses(
          organization_id,client_id,question_key,response_value,completed_at
        )
        values(
          v_organization,p_actor_id,v_key,v_value,now()
        )
        on conflict(client_id,question_key) do update set
          organization_id=excluded.organization_id,
          response_value=excluded.response_value,
          completed_at=now(),
          updated_at=now();
      end if;
    end loop;

    if p_payload->'answers' ? 'muscle_focus' then
      if jsonb_typeof(
        p_payload->'answers'->'muscle_focus'
      )<>'array' then
        raise exception 'muscle_focus must be an array';
      end if;

      select coalesce(array_agg(x order by x),array[]::text[])
      into v_focus
      from (
        select distinct lower(btrim(value)) as x
        from jsonb_array_elements_text(
          p_payload->'answers'->'muscle_focus'
        )
        where nullif(btrim(value),'') is not null
      ) q;

      if cardinality(v_focus)<1 then
        raise exception 'At least one muscle focus is required';
      end if;
      if not (v_focus<@v_allowed_focus) then
        raise exception 'Invalid muscle focus';
      end if;
      if 'full_body'=any(v_focus)
         and cardinality(v_focus)<>1 then
        raise exception 'full_body must be exclusive';
      end if;

      insert into public.client_training_preferences(
        organization_id,client_id,muscle_focus,source,updated_by
      )
      values(
        v_organization,p_actor_id,v_focus,'onboarding',p_actor_id
      )
      on conflict(client_id) do update set
        organization_id=excluded.organization_id,
        muscle_focus=excluded.muscle_focus,
        source='onboarding',
        updated_by=p_actor_id,
        updated_at=now();
    end if;
  end if;

  return jsonb_build_object(
    'organization_id',v_organization,
    'client_id',p_actor_id,
    'onboarding_status','completed',
    'submitted_at',now()
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

  if not private.actor_can_manage_client_in_org_v1(
    p_actor_id,v_organization,p_client_id
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
      where cc.coach_id=p_actor_id
        and cc.client_id=p_client_id
        and cc.status='active'::public.coach_client_status
    ) then
      insert into public.coach_clients(
        coach_id,client_id,status,assigned_at
      )
      values(
        p_actor_id,p_client_id,
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
      coach_id,client_id,note,pinned
    )
    values(
      p_actor_id,p_client_id,trim(p_note),false
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

comment on function private.actor_can_manage_client_in_org_v1(uuid,uuid,uuid) is
  'F1.M1.S5 C3B actor-aware canonical authorization for SECURITY DEFINER compatibility RPCs.';
comment on function private.get_client_training_schedule_in_org(uuid,uuid) is
  'F1.M1.S5 tenant-explicit training schedule reader.';
comment on function private.week_start_for_client_in_org(uuid,uuid) is
  'F1.M1.S5 tenant-explicit client week resolver.';
