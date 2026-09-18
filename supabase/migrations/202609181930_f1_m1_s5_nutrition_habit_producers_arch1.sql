-- ARCH-1.0 · F1.M1.S5 Wave D2 — Nutrition / Habit producer hardening
-- Repairs legacy producer RPCs after tenant-scoped uniqueness and ensures
-- every write uses a canonical Organization boundary.
-- CV12 reward state is still legacy-global, so legacy reward-producing RPCs
-- intentionally reject clients active in multiple Organizations until the CV12 wave.

create or replace function private.can_view_meal(target_meal uuid)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select coalesce(exists(
    select 1
    from public.meal_logs ml
    where ml.id=target_meal
      and private.can_view_client_in_org(ml.organization_id,ml.client_id)
  ),false)
$function$;

create or replace function private.can_edit_meal(target_meal uuid)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select coalesce(exists(
    select 1
    from public.meal_logs ml
    where ml.id=target_meal
      and (
        (
          ml.client_id=(select auth.uid())
          and private.is_org_member(ml.organization_id)
        )
        or private.can_manage_client_in_org(
          ml.organization_id,ml.client_id
        )
      )
  ),false)
$function$;

create or replace function private.can_view_progress_photo_path(object_name text)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select
    -- Keep the existing self-owned upload/storage path compatibility.
    (storage.foldername(object_name))[1]=(select auth.uid())::text
    or exists(
      select 1
      from public.progress_photos pp
      where pp.storage_path=object_name
        and (
          (
            pp.client_id=(select auth.uid())
            and private.is_org_member(pp.organization_id)
          )
          or (
            pp.visible_to_coach=true
            and private.can_manage_client_in_org(
              pp.organization_id,pp.client_id
            )
          )
          or private.is_org_admin(pp.organization_id)
        )
    )
$function$;

create or replace function public.set_nutrition_target_backend(
  p_actor_id uuid,
  p_client_id uuid,
  p_calories numeric,
  p_protein_g numeric,
  p_carbs_g numeric,
  p_fat_g numeric,
  p_meal_target integer,
  p_start_date date,
  p_end_date date default null::date
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_role text;
  v_id uuid;
  v_organization uuid;
  v_request_role text:=coalesce(auth.role(),'');
  v_request_user uuid:=auth.uid();
begin
  if p_actor_id is null or p_client_id is null then
    raise exception 'actor_id and client_id are required';
  end if;

  if v_request_role<>'service_role'
     and (v_request_user is null or v_request_user<>p_actor_id) then
    raise exception 'actor identity mismatch';
  end if;

  select role::text into v_role
  from public.profiles
  where id=p_actor_id
    and status::text='active';

  if v_role not in ('admin','coach') then
    raise exception 'actor is not authorized to manage nutrition';
  end if;

  v_organization:=private.resolve_legacy_professional_organization_v1(
    p_actor_id,p_client_id
  );

  if not private.actor_can_manage_client_in_org_v1(
    p_actor_id,v_organization,p_client_id
  ) then
    raise exception 'actor is not assigned to this client in organization';
  end if;

  if not exists(
    select 1
    from public.clients c
    join public.profiles p on p.id=c.user_id
    where c.organization_id=v_organization
      and c.user_id=p_client_id
      and c.status<>'archived'::public.client_status
      and p.role::text='client'
      and p.status::text='active'
  ) then
    raise exception 'active client not found in organization';
  end if;

  if p_start_date is null then
    raise exception 'start_date is required';
  end if;
  if p_end_date is not null and p_end_date<p_start_date then
    raise exception 'end_date cannot be before start_date';
  end if;
  if p_calories is not null and p_calories<0 then
    raise exception 'calories must be >= 0';
  end if;
  if p_protein_g is not null and p_protein_g<0 then
    raise exception 'protein_g must be >= 0';
  end if;
  if p_carbs_g is not null and p_carbs_g<0 then
    raise exception 'carbs_g must be >= 0';
  end if;
  if p_fat_g is not null and p_fat_g<0 then
    raise exception 'fat_g must be >= 0';
  end if;
  if p_meal_target is not null and p_meal_target<=0 then
    raise exception 'meal_target must be > 0';
  end if;

  update public.nutrition_targets
  set active=false,
      updated_at=now()
  where organization_id=v_organization
    and client_id=p_client_id
    and active=true;

  insert into public.nutrition_targets(
    organization_id,client_id,calories,protein_g,carbs_g,fat_g,
    meal_target,start_date,end_date,active,created_by
  )
  values(
    v_organization,p_client_id,p_calories,p_protein_g,p_carbs_g,p_fat_g,
    p_meal_target,p_start_date,p_end_date,true,p_actor_id
  )
  returning id into v_id;

  return jsonb_build_object(
    'organization_id',v_organization,
    'nutrition_target_id',v_id,
    'client_id',p_client_id,
    'active',true,
    'start_date',p_start_date,
    'end_date',p_end_date
  );
end;
$function$;

create or replace function public.log_habit_backend(
  p_actor_id uuid,
  p_client_habit_id uuid,
  p_log_date date default current_date,
  p_value numeric default null::numeric,
  p_text_value text default null::text,
  p_completed boolean default null::boolean
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor_role text;
  v_client_id uuid;
  v_organization uuid;
  v_legacy_org uuid;
  v_habit_id uuid;
  v_category text;
  v_name text;
  v_input text;
  v_target numeric;
  v_min numeric;
  v_max numeric;
  v_custom_xp integer;
  v_default_xp integer;
  v_complete boolean:=false;
  v_source public.log_source;
  v_log_id uuid;
  v_event text;
  v_reward record;
  v_missions integer:=0;
  v_achievements jsonb:='[]'::jsonb;
  v_state record;
  v_level_before integer:=1;
  v_level_after integer:=1;
  v_request_role text:=coalesce(auth.role(),'');
  v_request_user uuid:=auth.uid();
begin
  if p_actor_id is null or p_client_habit_id is null then
    raise exception 'actor_id and client_habit_id are required';
  end if;
  if p_log_date is null or p_log_date>current_date then
    raise exception 'invalid log_date';
  end if;

  if v_request_role<>'service_role'
     and (v_request_user is null or v_request_user<>p_actor_id) then
    raise exception 'actor identity mismatch';
  end if;

  select p.role::text into v_actor_role
  from public.profiles p
  where p.id=p_actor_id
    and p.status::text='active';

  if v_actor_role is null then
    raise exception 'actor is not an active CV Coach user';
  end if;

  select
    ch.organization_id,
    ch.client_id,
    ch.habit_id,
    hd.category,
    hd.name,
    hd.input_type::text,
    ch.target_value,
    ch.minimum_value,
    ch.maximum_value,
    ch.xp_reward,
    hd.default_xp
  into
    v_organization,
    v_client_id,
    v_habit_id,
    v_category,
    v_name,
    v_input,
    v_target,
    v_min,
    v_max,
    v_custom_xp,
    v_default_xp
  from public.client_habits ch
  join public.habit_definitions hd
    on hd.id=ch.habit_id
  where ch.id=p_client_habit_id
    and ch.active=true
    and ch.start_date<=p_log_date
    and (ch.end_date is null or ch.end_date>=p_log_date)
    and hd.active=true;

  if v_client_id is null then
    raise exception 'active client habit not found for this date';
  end if;

  if p_actor_id=v_client_id then
    if v_actor_role<>'client'
       or not private.is_org_member(v_organization) then
      raise exception 'self logging requires client membership in habit organization';
    end if;
  else
    if v_actor_role not in ('admin','coach')
       or not private.actor_can_manage_client_in_org_v1(
         p_actor_id,v_organization,v_client_id
       ) then
      raise exception 'actor is not authorized for this client habit in organization';
    end if;
  end if;

  if v_actor_role='client' and p_log_date<current_date-7 then
    raise exception 'client manual logs can be backfilled up to 7 days';
  end if;

  -- CV12 reward/mission state is still client-global. Until the CV12 tenant
  -- wave lands, never let this legacy RPC produce rewards for an ambiguous user.
  v_legacy_org:=private.resolve_legacy_client_organization_v1(
    v_client_id,null
  );
  if v_legacy_org<>v_organization then
    raise exception 'legacy CV12 context does not match habit organization';
  end if;

  v_source:=case
    when p_actor_id=v_client_id then 'manual'::public.log_source
    else 'coach'::public.log_source
  end;

  select coalesce(s.current_level,1)
    into v_level_before
  from public.client_cv_state s
  where s.client_id=v_client_id;
  v_level_before:=coalesce(v_level_before,1);

  if v_input='boolean' then
    v_complete:=coalesce(p_completed,false);
  else
    if p_value is null then
      v_complete:=coalesce(p_completed,false);
    elsif v_min is not null and v_max is not null then
      v_complete:=p_value between v_min and v_max;
    elsif v_min is not null then
      v_complete:=p_value>=v_min;
    elsif v_max is not null then
      v_complete:=p_value<=v_max;
    elsif v_target is not null then
      v_complete:=p_value>=v_target;
    else
      v_complete:=coalesce(p_completed,false);
    end if;
  end if;

  insert into public.habit_logs(
    organization_id,client_habit_id,client_id,log_date,
    value,text_value,completed,source
  )
  values(
    v_organization,p_client_habit_id,v_client_id,p_log_date,
    p_value,p_text_value,v_complete,v_source
  )
  on conflict(client_habit_id,log_date) do update set
    organization_id=excluded.organization_id,
    value=excluded.value,
    text_value=excluded.text_value,
    completed=excluded.completed,
    source=excluded.source,
    updated_at=now()
  returning id into v_log_id;

  v_event:=case
    when v_category='cardio' then 'cardio_completed'
    else 'habit_completed'
  end;

  select
    0 as xp_awarded,
    0 as credits_awarded,
    false as idempotent,
    false as cap_reached
  into v_reward;

  if v_complete then
    select * into v_reward
    from private.award_cv12_action(
      v_client_id,
      v_event,
      v_log_id,
      p_log_date,
      case
        when v_category='cardio' then 'Cardio/caminata completado'
        else 'Hábito cumplido: '||v_name
      end,
      case
        when v_event='habit_completed'
          then coalesce(nullif(v_custom_xp,0),nullif(v_default_xp,0))
        else null
      end
    );

    v_missions:=private.process_event_missions(
      v_client_id,v_event,v_category
    );
    v_achievements:=private.process_generic_achievements(
      v_client_id,v_event
    );
  end if;

  select * into v_state
  from private.refresh_client_cv_state(v_client_id,v_event);

  v_level_after:=coalesce(
    v_state.current_level,
    v_level_before,
    1
  );

  return jsonb_build_object(
    'organization_id',v_organization,
    'client_id',v_client_id,
    'habit_log_id',v_log_id,
    'habit_name',v_name,
    'habit_category',v_category,
    'log_date',p_log_date,
    'completed',v_complete,
    'event',case when v_complete then v_event else null end,
    'xp_earned',coalesce(v_reward.xp_awarded,0),
    'credits_earned',coalesce(v_reward.credits_awarded,0),
    'reward_idempotent',coalesce(v_reward.idempotent,false),
    'reward_cap_reached',coalesce(v_reward.cap_reached,false),
    'missions_completed',v_missions,
    'achievements_unlocked',v_achievements,
    'previous_level',v_level_before,
    'current_level',v_level_after,
    'level_up',(v_level_after>v_level_before)
  );
end;
$function$;

create or replace function public.log_nutrition_day_backend(
  p_actor_id uuid,
  p_client_id uuid default null::uuid,
  p_log_date date default current_date,
  p_adherence_pct numeric default null::numeric,
  p_meals_completed integer default null::integer,
  p_compliant boolean default null::boolean,
  p_notes text default null::text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor_role text;
  v_client uuid;
  v_organization uuid;
  v_target public.nutrition_targets%rowtype;
  v_meal_target integer;
  v_compliant boolean:=false;
  v_source public.log_source;
  v_log_id uuid;
  v_reward record;
  v_missions integer:=0;
  v_achievements jsonb:='[]'::jsonb;
  v_state record;
  v_level_before integer:=1;
  v_level_after integer:=1;
  v_request_role text:=coalesce(auth.role(),'');
  v_request_user uuid:=auth.uid();
begin
  if p_actor_id is null then
    raise exception 'actor_id is required';
  end if;
  if p_log_date is null or p_log_date>current_date then
    raise exception 'invalid log_date';
  end if;
  if p_adherence_pct is not null
     and (p_adherence_pct<0 or p_adherence_pct>100) then
    raise exception 'adherence_pct must be between 0 and 100';
  end if;
  if p_meals_completed is not null and p_meals_completed<0 then
    raise exception 'meals_completed cannot be negative';
  end if;

  if v_request_role<>'service_role'
     and (v_request_user is null or v_request_user<>p_actor_id) then
    raise exception 'actor identity mismatch';
  end if;

  select p.role::text into v_actor_role
  from public.profiles p
  where p.id=p_actor_id
    and p.status::text='active';

  if v_actor_role is null then
    raise exception 'actor is not an active CV Coach user';
  end if;

  v_client:=coalesce(p_client_id,p_actor_id);

  if p_actor_id=v_client then
    if v_actor_role<>'client' then
      raise exception 'self nutrition logging requires a client account or an explicit client_id';
    end if;
    v_organization:=private.resolve_legacy_client_organization_v1(
      v_client,null
    );
    if not private.is_org_member(v_organization) then
      raise exception 'client is not active in resolved organization';
    end if;
  else
    if v_actor_role not in ('admin','coach') then
      raise exception 'actor is not authorized for this client';
    end if;
    v_organization:=private.resolve_legacy_professional_organization_v1(
      p_actor_id,v_client
    );
    if not private.actor_can_manage_client_in_org_v1(
      p_actor_id,v_organization,v_client
    ) then
      raise exception 'actor is not authorized for this client in organization';
    end if;
  end if;

  if v_actor_role='client' and p_log_date<current_date-7 then
    raise exception 'client manual logs can be backfilled up to 7 days';
  end if;

  -- Explicit safety gate while CV12 reward state remains client-global.
  perform private.resolve_legacy_client_organization_v1(v_client,null);

  v_source:=case
    when p_actor_id=v_client then 'manual'::public.log_source
    else 'coach'::public.log_source
  end;

  select coalesce(s.current_level,1)
    into v_level_before
  from public.client_cv_state s
  where s.client_id=v_client;
  v_level_before:=coalesce(v_level_before,1);

  select * into v_target
  from public.nutrition_targets nt
  where nt.organization_id=v_organization
    and nt.client_id=v_client
    and nt.active=true
    and nt.start_date<=p_log_date
    and (nt.end_date is null or nt.end_date>=p_log_date)
  order by nt.start_date desc,nt.created_at desc
  limit 1;

  v_meal_target:=case
    when found then v_target.meal_target
    else null
  end;

  if p_adherence_pct is not null then
    v_compliant:=p_adherence_pct>=80;
  elsif p_meals_completed is not null
        and v_meal_target is not null
        and v_meal_target>0 then
    v_compliant:=p_meals_completed>=v_meal_target;
  else
    v_compliant:=coalesce(p_compliant,false);
  end if;

  insert into public.nutrition_daily_logs(
    organization_id,client_id,log_date,adherence_pct,
    meals_completed,meal_target_snapshot,compliant,notes,source
  )
  values(
    v_organization,v_client,p_log_date,p_adherence_pct,
    p_meals_completed,v_meal_target,v_compliant,p_notes,v_source
  )
  on conflict(organization_id,client_id,log_date) do update set
    adherence_pct=excluded.adherence_pct,
    meals_completed=excluded.meals_completed,
    meal_target_snapshot=excluded.meal_target_snapshot,
    compliant=excluded.compliant,
    notes=excluded.notes,
    source=excluded.source,
    updated_at=now()
  returning id into v_log_id;

  select
    0 as xp_awarded,
    0 as credits_awarded,
    false as idempotent,
    false as cap_reached
  into v_reward;

  if v_compliant then
    select * into v_reward
    from private.award_cv12_action(
      v_client,
      'nutrition_compliant',
      v_log_id,
      p_log_date,
      'Día de nutrición cumplido',
      null
    );

    v_missions:=private.process_event_missions(
      v_client,'nutrition_compliant',null
    );
    v_achievements:=private.process_generic_achievements(
      v_client,'nutrition_compliant'
    );
  end if;

  select * into v_state
  from private.refresh_client_cv_state(
    v_client,'nutrition_compliant'
  );

  v_level_after:=coalesce(
    v_state.current_level,
    v_level_before,
    1
  );

  return jsonb_build_object(
    'organization_id',v_organization,
    'client_id',v_client,
    'nutrition_log_id',v_log_id,
    'log_date',p_log_date,
    'compliant',v_compliant,
    'adherence_pct',p_adherence_pct,
    'meals_completed',p_meals_completed,
    'meal_target',v_meal_target,
    'event',case
      when v_compliant then 'nutrition_compliant'
      else null
    end,
    'xp_earned',coalesce(v_reward.xp_awarded,0),
    'credits_earned',coalesce(v_reward.credits_awarded,0),
    'reward_idempotent',coalesce(v_reward.idempotent,false),
    'reward_cap_reached',coalesce(v_reward.cap_reached,false),
    'missions_completed',v_missions,
    'achievements_unlocked',v_achievements,
    'previous_level',v_level_before,
    'current_level',v_level_after,
    'level_up',(v_level_after>v_level_before)
  );
end;
$function$;

comment on function public.log_nutrition_day_backend(
  uuid,uuid,date,numeric,integer,boolean,text
) is
  'F1.M1.S5 D2 tenant-aware nutrition producer. Legacy signature preserved; multi-Organization reward calls fail safely until CV12 tenant migration.';
comment on function public.log_habit_backend(
  uuid,uuid,date,numeric,text,boolean
) is
  'F1.M1.S5 D2 tenant-aware habit producer. Organization derives from client_habit; multi-Organization reward calls fail safely until CV12 tenant migration.';
