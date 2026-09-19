-- F1.M1.S5 C3C — Composite personal-state identity cutover
-- Converts client personal state from global client identity to Organization + Client identity.

-- Precondition: all rows already carry organization_id and same-tenant FKs.
do $$
begin
  if exists(select 1 from public.client_profiles where organization_id is null)
     or exists(select 1 from public.client_training_preferences where organization_id is null)
     or exists(select 1 from public.client_training_schedule_preferences where organization_id is null)
     or exists(select 1 from public.onboarding_responses where organization_id is null) then
    raise exception 'C3C precondition failed: personal-state rows without organization_id';
  end if;
end
$$;

alter table public.client_profiles
  drop constraint if exists client_profiles_pkey;
alter table public.client_profiles
  add constraint client_profiles_pkey
  primary key(organization_id,client_id);

alter table public.client_training_preferences
  drop constraint if exists client_training_preferences_pkey;
alter table public.client_training_preferences
  add constraint client_training_preferences_pkey
  primary key(organization_id,client_id);

alter table public.client_training_schedule_preferences
  drop constraint if exists client_training_schedule_preferences_pkey;
alter table public.client_training_schedule_preferences
  add constraint client_training_schedule_preferences_pkey
  primary key(organization_id,client_id);

alter table public.onboarding_responses
  drop constraint if exists onboarding_responses_client_id_question_key_key;
alter table public.onboarding_responses
  drop constraint if exists onboarding_responses_org_client_question_key_key;
alter table public.onboarding_responses
  add constraint onboarding_responses_org_client_question_key_key
  unique(organization_id,client_id,question_key);

CREATE OR REPLACE FUNCTION public.submit_onboarding_in_org_backend(p_actor_id uuid, p_organization_id uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  if p_actor_id is null or p_organization_id is null or p_payload is null then
    raise exception 'actor_id, organization_id and payload are required';
  end if;
  if coalesce(auth.role(),'')<>'service_role'
     and (auth.uid() is null or auth.uid()<>p_actor_id) then
    raise exception 'actor identity mismatch';
  end if;

  select p.role::text into v_role
  from public.profiles p
  where p.id=p_actor_id
    and p.status::text='active';

  if v_role<>'client' then
    raise exception 'only active clients can submit onboarding';
  end if;

  v_organization:=p_organization_id;

  if not exists(
    select 1
    from public.clients c
    join public.organization_members om
      on om.organization_id=c.organization_id
     and om.user_id=c.user_id
     and om.status='active'::public.organization_member_status
     and om.role='client'::public.organization_member_role
    where c.organization_id=v_organization
      and c.user_id=p_actor_id
      and c.status<>'archived'::public.client_status
  ) then
    raise exception 'client is not active in organization';
  end if;

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
  on conflict(organization_id,client_id) do update set
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
        on conflict(organization_id,client_id,question_key) do update set
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
      on conflict(organization_id,client_id) do update set
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
  v_organization uuid;
begin
  v_organization:=private.resolve_legacy_client_organization_v1(
    p_actor_id,null
  );
  return public.submit_onboarding_in_org_backend(
    p_actor_id,v_organization,p_payload
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.set_client_training_focus_in_org_backend(p_actor_id uuid, p_organization_id uuid, p_client_id uuid, p_muscle_focus text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  if p_actor_id is null or p_organization_id is null or p_client_id is null then
    raise exception 'actor_id, organization_id and client_id are required';
  end if;

  if v_request_role<>'service_role'
     and (v_request_user is null or v_request_user<>p_actor_id) then
    raise exception 'actor identity mismatch';
  end if;

  v_organization:=p_organization_id;

  if not (
    v_request_role='service_role'
    or private.is_org_admin(v_organization)
    or private.actor_can_manage_client_in_org_v1(
      p_actor_id,v_organization,p_client_id
    )
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
  on conflict(organization_id,client_id) do update set
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
  v_organization uuid;
begin
  v_organization:=private.resolve_legacy_professional_organization_v1(
    p_actor_id,p_client_id
  );
  return public.set_client_training_focus_in_org_backend(
    p_actor_id,v_organization,p_client_id,p_muscle_focus
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.set_client_training_schedule_in_org_backend(p_actor_id uuid, p_organization_id uuid, p_client_id uuid, p_training_days_per_week integer, p_session_minutes integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_request_role text:=coalesce(auth.role(),'');
  v_request_user uuid:=auth.uid();
  v_row public.client_training_schedule_preferences%rowtype;
  v_organization uuid;
begin
  if p_actor_id is null or p_organization_id is null or p_client_id is null then
    raise exception 'actor_id, organization_id and client_id are required';
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

  v_organization:=p_organization_id;

  if not (
    v_request_role='service_role'
    or private.is_org_admin(v_organization)
    or private.actor_can_manage_client_in_org_v1(
      p_actor_id,v_organization,p_client_id
    )
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
  on conflict(organization_id,client_id) do update set
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
  v_organization uuid;
begin
  v_organization:=private.resolve_legacy_professional_organization_v1(
    p_actor_id,p_client_id
  );
  return public.set_client_training_schedule_in_org_backend(
    p_actor_id,v_organization,p_client_id,
    p_training_days_per_week,p_session_minutes
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.provision_client_records_in_org_backend(p_actor_id uuid, p_organization_id uuid, p_client_id uuid, p_email text, p_first_name text, p_last_name text DEFAULT NULL::text, p_phone text DEFAULT NULL::text, p_created_user boolean DEFAULT false, p_client_url text DEFAULT 'https://cv-coach-roan.vercel.app'::text, p_record_invite boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare
  v_request_role text:=coalesce(auth.role(),'');
  v_request_user uuid:=auth.uid();
  v_actor_role public.app_role;
  v_actor_status public.profile_status;
  v_existing_role public.app_role;
  v_email text:=lower(trim(coalesce(p_email,'')));
  v_first_name text:=trim(coalesce(p_first_name,''));
  v_last_name text:=nullif(trim(coalesce(p_last_name,'')),'');
  v_phone text:=nullif(trim(coalesce(p_phone,'')),'');
  v_organization uuid;
  v_member public.organization_members%rowtype;
  v_client_entity uuid;
  v_coach_entity uuid;
  v_assignment_role public.client_coach_assignment_role;
begin
  if v_request_role<>'service_role'
     and (v_request_user is null or v_request_user<>p_actor_id) then
    raise exception 'Authenticated actor mismatch';
  end if;

  select role,status into v_actor_role,v_actor_status
  from public.profiles
  where id=p_actor_id;

  if not found
     or v_actor_status<>'active'::public.profile_status
     or v_actor_role not in ('admin'::public.app_role,'coach'::public.app_role) then
    raise exception 'Forbidden' using errcode='42501';
  end if;

  if p_client_id is null or p_actor_id=p_client_id then
    return jsonb_build_object('ok',false,'code','invalid_client');
  end if;
  if v_email='' or v_first_name='' then
    return jsonb_build_object('ok',false,'code','invalid_input');
  end if;
  if p_client_url<>'https://cv-coach-roan.vercel.app' then
    return jsonb_build_object('ok',false,'code','invalid_client_url');
  end if;

  if p_organization_id is null then
    raise exception 'organization_id is required';
  end if;
  v_organization:=p_organization_id;

  if not (
    v_request_role='service_role'
    or private.is_org_admin(v_organization)
    or private.actor_can_manage_client_in_org_v1(p_actor_id,v_organization,p_client_id)
  ) then
    raise exception 'Forbidden for organization' using errcode='42501';
  end if;

  select role into v_existing_role
  from public.profiles
  where id=p_client_id;

  if found and v_existing_role<>'client'::public.app_role then
    return jsonb_build_object('ok',false,'code','internal_account');
  end if;

  insert into public.profiles(id,role,status,first_name,last_name,phone)
  values(
    p_client_id,'client','active',
    left(v_first_name,80),left(v_last_name,80),left(v_phone,40)
  )
  on conflict(id) do update set
    first_name=excluded.first_name,last_name=excluded.last_name,
    phone=excluded.phone,status='active',updated_at=now();

  select * into v_member
  from public.organization_members om
  where om.organization_id=v_organization and om.user_id=p_client_id
  for update;

  if not found then
    insert into public.organization_members(organization_id,user_id,role,status,joined_at)
    values(
      v_organization,p_client_id,
      'client'::public.organization_member_role,
      'active'::public.organization_member_status,now()
    );
  else
    if v_member.role<>'client'::public.organization_member_role then
      raise exception 'client user already has a non-client role in organization';
    end if;
    if v_member.status<>'active'::public.organization_member_status then
      raise exception 'client organization membership is not active';
    end if;
  end if;

  insert into public.clients(
    organization_id,user_id,status,display_name,contact_metadata,onboarding_state,created_by
  )
  values(
    v_organization,p_client_id,'active'::public.client_status,
    left(btrim(v_first_name||coalesce(' '||v_last_name,'')),160),
    jsonb_strip_nulls(jsonb_build_object(
      'email',v_email,'phone',v_phone,'source','provision_client_records_backend'
    )),
    jsonb_build_object('status','pending'),p_actor_id
  )
  on conflict(organization_id,user_id) do update set
    status='active'::public.client_status,
    display_name=excluded.display_name,
    contact_metadata=public.clients.contact_metadata||excluded.contact_metadata,
    updated_at=now()
  returning id into v_client_entity;

  insert into public.client_profiles(
    organization_id,client_id,onboarding_status,timezone
  )
  values(
    v_organization,p_client_id,'pending'::public.onboarding_status,'America/Santiago'
  )
  on conflict(organization_id,client_id) do update set
    updated_at=now();

  select cp.id into v_coach_entity
  from public.coach_profiles cp
  where cp.organization_id=v_organization
    and cp.user_id=p_actor_id
    and cp.status='active'::public.coach_profile_status
  limit 1;

  if v_coach_entity is not null
     and not exists(
       select 1 from public.client_coach_assignments a
       where a.organization_id=v_organization
         and a.client_id=v_client_entity
         and a.coach_id=v_coach_entity
         and a.status='active'::public.client_coach_assignment_status
     ) then
    v_assignment_role:=case
      when exists(
        select 1 from public.client_coach_assignments a
        where a.organization_id=v_organization
          and a.client_id=v_client_entity
          and a.assignment_role='primary'::public.client_coach_assignment_role
          and a.status='active'::public.client_coach_assignment_status
      )
      then 'secondary'::public.client_coach_assignment_role
      else 'primary'::public.client_coach_assignment_role
    end;

    insert into public.client_coach_assignments(
      organization_id,client_id,coach_id,assignment_role,status,assigned_at,assigned_by
    )
    values(
      v_organization,v_client_entity,v_coach_entity,v_assignment_role,
      'active'::public.client_coach_assignment_status,now(),p_actor_id
    );
  end if;

  if not exists(
    select 1 from public.coach_clients
    where organization_id=v_organization
      and coach_id=p_actor_id
      and client_id=p_client_id
      and status='active'::public.coach_client_status
  ) then
    insert into public.coach_clients(
      organization_id,coach_id,client_id,status
    )
    values(
      v_organization,p_actor_id,p_client_id,'active'::public.coach_client_status
    );
  end if;

  if p_record_invite then
    insert into public.client_invites(
      organization_id,coach_id,client_id,email,status,metadata
    )
    values(
      v_organization,p_actor_id,p_client_id,v_email,'generated',
      jsonb_build_object(
        'organization_id',v_organization,
        'created_user',coalesce(p_created_user,false),
        'client_url',p_client_url
      )
    );
  end if;

  return jsonb_build_object(
    'ok',true,'organization_id',v_organization,
    'client_id',p_client_id,'client_entity_id',v_client_entity,
    'invite_recorded',p_record_invite
  );
end;
$function$;

create or replace function public.provision_client_records_backend(
  p_actor_id uuid,
  p_client_id uuid,
  p_email text,
  p_first_name text,
  p_last_name text default null::text,
  p_phone text default null::text,
  p_created_user boolean default false,
  p_client_url text default 'https://cv-coach-roan.vercel.app'::text,
  p_record_invite boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','private'
as $function$
declare
  v_organization uuid;
begin
  v_organization:=private.resolve_legacy_professional_organization_v1(
    p_actor_id,p_client_id
  );
  return public.provision_client_records_in_org_backend(
    p_actor_id,v_organization,p_client_id,p_email,p_first_name,p_last_name,
    p_phone,p_created_user,p_client_url,p_record_invite
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.review_onboarding_in_org_backend(p_actor_id uuid, p_organization_id uuid, p_client_id uuid, p_decision text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  if p_actor_id is null or p_organization_id is null or p_client_id is null then
    raise exception 'actor_id, organization_id and client_id are required';
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

  v_organization:=p_organization_id;

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
  v_organization uuid;
begin
  v_organization:=private.resolve_legacy_professional_organization_v1(
    p_actor_id,p_client_id
  );
  return public.review_onboarding_in_org_backend(
    p_actor_id,v_organization,p_client_id,p_decision,p_note
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_push_center_v101(p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid:=auth.uid();
  v_role text:=coalesce(auth.role(),'');
  v_public_key text;
  v_pref public.push_preferences_v101%rowtype;
  v_active integer:=0;
  v_total integer:=0;
  v_recent jsonb:='[]'::jsonb;
begin
  if p_actor_id is null then raise exception 'actor_id is required'; end if;
  if v_role<>'service_role' and (v_uid is null or v_uid<>p_actor_id) then raise exception 'actor identity mismatch'; end if;
  if not exists(select 1 from public.profiles p where p.id=p_actor_id and p.status::text='active') then raise exception 'active profile required'; end if;

  select decrypted_secret into v_public_key from vault.decrypted_secrets where name='cv_push_vapid_public_v101' order by created_at desc limit 1;
  select * into v_pref from public.push_preferences_v101 where user_id=p_actor_id;
  select count(*)::int,count(*) filter(where enabled)::int into v_total,v_active from public.push_subscriptions_v101 where user_id=p_actor_id;
  select coalesce(jsonb_agg(x order by x.created_at desc),'[]'::jsonb) into v_recent
  from (
    select q.notification_id,q.category,q.status,q.attempts,q.sent_at,q.skipped_reason,q.last_error,q.created_at
    from private.push_dispatch_queue_v101 q
    where q.user_id=p_actor_id
    order by q.created_at desc
    limit 10
  ) x;

  return jsonb_build_object(
    'version','PUSH_NOTIFICATIONS_OS_V101',
    'configured',coalesce(v_public_key,'')<>'',
    'vapid_public_key',v_public_key,
    'subscriptions',jsonb_build_object('total',v_total,'active',v_active),
    'preferences',jsonb_build_object(
      'enabled',coalesce(v_pref.enabled,true),
      'training_reminders',coalesce(v_pref.training_reminders,true),
      'program_updates',coalesce(v_pref.program_updates,true),
      'progress_updates',coalesce(v_pref.progress_updates,true),
      'coach_updates',coalesce(v_pref.coach_updates,true),
      'system_updates',coalesce(v_pref.system_updates,true),
      'quiet_hours_start',coalesce(v_pref.quiet_hours_start,time '21:00'),
      'quiet_hours_end',coalesce(v_pref.quiet_hours_end,time '08:00'),
      'timezone',coalesce(nullif(v_pref.timezone,''),(select case
          when count(distinct nullif(cp.timezone,''))=1 then max(nullif(cp.timezone,''))
          else 'America/Santiago'
        end
        from public.client_profiles cp
        where cp.client_id=p_actor_id),'America/Santiago'),
      'workout_reminder_time',v_pref.workout_reminder_time
    ),
    'recent_delivery',v_recent,
    'guardrails',jsonb_build_object('permission_requires_user_gesture',true,'quiet_hours_respected',true,'multi_device',true,'in_app_notification_is_source_of_truth',true,'auto_subscribe',false)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.register_push_subscription_v101(p_actor_id uuid, p_endpoint text, p_p256dh text, p_auth_secret text, p_expiration_time bigint DEFAULT NULL::bigint, p_user_agent text DEFAULT NULL::text, p_device_label text DEFAULT NULL::text, p_platform text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid:=auth.uid(); v_role text:=coalesce(auth.role(),''); v_id uuid; v_timezone text;
begin
  if p_actor_id is null then raise exception 'actor_id is required'; end if;
  if v_role<>'service_role' and (v_uid is null or v_uid<>p_actor_id) then raise exception 'actor identity mismatch'; end if;
  if not exists(select 1 from public.profiles p where p.id=p_actor_id and p.status::text='active') then raise exception 'active profile required'; end if;
  if char_length(btrim(coalesce(p_endpoint,''))) not between 20 and 4096 then raise exception 'invalid endpoint'; end if;
  if char_length(btrim(coalesce(p_p256dh,''))) not between 40 and 512 then raise exception 'invalid p256dh'; end if;
  if char_length(btrim(coalesce(p_auth_secret,''))) not between 8 and 256 then raise exception 'invalid auth secret'; end if;

  insert into public.push_subscriptions_v101(user_id,endpoint,p256dh,auth_secret,expiration_time,user_agent,device_label,platform,enabled,last_seen_at,disabled_at,updated_at)
  values(p_actor_id,btrim(p_endpoint),btrim(p_p256dh),btrim(p_auth_secret),p_expiration_time,left(p_user_agent,1000),left(p_device_label,160),left(p_platform,120),true,now(),null,now())
  on conflict(endpoint) do update set user_id=excluded.user_id,p256dh=excluded.p256dh,auth_secret=excluded.auth_secret,expiration_time=excluded.expiration_time,user_agent=excluded.user_agent,device_label=excluded.device_label,platform=excluded.platform,enabled=true,last_seen_at=now(),disabled_at=null,updated_at=now()
  returning id into v_id;

  select case
           when count(distinct nullif(cp.timezone,''))=1 then max(nullif(cp.timezone,''))
           else 'America/Santiago'
         end
    into v_timezone
  from public.client_profiles cp
  where cp.client_id=p_actor_id;
  insert into public.push_preferences_v101(user_id,enabled,timezone,updated_at)
  values(p_actor_id,true,coalesce(v_timezone,'America/Santiago'),now())
  on conflict(user_id) do update set enabled=true,updated_at=now();

  return jsonb_build_object('subscription_id',v_id,'registered',true,'enabled',true,'auto_send',true);
end;
$function$;

revoke all on function public.submit_onboarding_in_org_backend(uuid,uuid,jsonb) from public,anon;
grant execute on function public.submit_onboarding_in_org_backend(uuid,uuid,jsonb) to authenticated,service_role;

revoke all on function public.set_client_training_focus_in_org_backend(uuid,uuid,uuid,text[]) from public,anon;
grant execute on function public.set_client_training_focus_in_org_backend(uuid,uuid,uuid,text[]) to authenticated,service_role;

revoke all on function public.set_client_training_schedule_in_org_backend(uuid,uuid,uuid,integer,integer) from public,anon;
grant execute on function public.set_client_training_schedule_in_org_backend(uuid,uuid,uuid,integer,integer) to authenticated,service_role;

revoke all on function public.provision_client_records_in_org_backend(uuid,uuid,uuid,text,text,text,text,boolean,text,boolean) from public,anon;
grant execute on function public.provision_client_records_in_org_backend(uuid,uuid,uuid,text,text,text,text,boolean,text,boolean) to authenticated,service_role;

revoke all on function public.review_onboarding_in_org_backend(uuid,uuid,uuid,text,text) from public,anon;
grant execute on function public.review_onboarding_in_org_backend(uuid,uuid,uuid,text,text) to authenticated,service_role;

comment on table public.client_profiles is
  'F1.M1.S5 C3C: client profile identity is Organization + Client.';
comment on table public.client_training_preferences is
  'F1.M1.S5 C3C: training preference identity is Organization + Client.';
comment on table public.client_training_schedule_preferences is
  'F1.M1.S5 C3C: training schedule identity is Organization + Client.';
comment on constraint onboarding_responses_org_client_question_key_key on public.onboarding_responses is
  'F1.M1.S5 C3C: onboarding answer identity is Organization + Client + Question.';
