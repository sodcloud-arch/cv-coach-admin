-- ARCH-1.0 · F1.M1.S5 Wave F2B — Competitive Seasons / Challenges tenant engine
-- Makes challenge/season creation, administration, progress, winners and ranking reads
-- Organization-local while preserving existing public RPC signatures.

-- ---------------------------------------------------------------------------
-- 1) Canonical professional authorization
-- ---------------------------------------------------------------------------

create or replace function private.cv_is_coach_admin_in_org_v62(
  p_organization uuid,
  p_actor uuid
)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select coalesce(
    exists(
      select 1
      from public.organization_members om
      join public.profiles p on p.id=om.user_id
      where om.organization_id=p_organization
        and om.user_id=p_actor
        and om.status='active'::public.organization_member_status
        and om.role in (
          'owner'::public.organization_member_role,
          'org_admin'::public.organization_member_role,
          'coach'::public.organization_member_role
        )
        and p.status::text='active'
        and p.role::text in ('admin','coach')
    ),
    false
  )
$function$;

create or replace function private.cv_is_coach_admin_v62(
  p_actor uuid
)
returns boolean
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_org uuid;
begin
  v_org:=private.resolve_legacy_professional_organization_v1(
    p_actor,null
  );
  return private.cv_is_coach_admin_in_org_v62(v_org,p_actor);
end;
$function$;

-- ---------------------------------------------------------------------------
-- 2) Tenant-explicit Challenge progress
-- ---------------------------------------------------------------------------

create or replace function private.cv_challenge_progress_in_org_v62(
  p_organization uuid,
  p_client uuid,
  p_challenge uuid
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  c public.cv_challenges_v61%rowtype;
  cr public.client_competitive_rank_v61%rowtype;
  v_current_week date:=
    date_trunc('week',now() at time zone 'America/Santiago')::date;
  v_calc jsonb;
  v_weeks integer:=0;
  v_perfect integer:=0;
  v_discipline numeric;
  v_training numeric;
  v_nutrition numeric;
  v_hydration numeric;
  v_movement numeric;
  v_recovery numeric;
  v_score numeric:=0;
  v_eligible boolean:=true;
  v_meets boolean:=false;
  v_status text:='participating';
  v_min_weeks integer:=1;
begin
  select * into c
  from public.cv_challenges_v61
  where id=p_challenge
    and organization_id=p_organization;

  if not found then
    raise exception 'challenge not found in organization';
  end if;

  select * into cr
  from public.client_competitive_rank_v61
  where organization_id=p_organization
    and client_id=p_client;

  if not found or not cr.tutorial_completed then
    return jsonb_build_object(
      'organization_id',p_organization,
      'eligible',false,
      'status','not_eligible',
      'reason','tutorial'
    );
  end if;

  if c.rules ? 'eligible_ranks'
     and jsonb_typeof(c.rules->'eligible_ranks')='array'
     and jsonb_array_length(c.rules->'eligible_ranks')>0 then
    v_eligible:=exists(
      select 1
      from jsonb_array_elements_text(c.rules->'eligible_ranks') x(value)
      where x.value=cr.current_rank_key
    );
  end if;

  if not v_eligible then
    return jsonb_build_object(
      'organization_id',p_organization,
      'eligible',false,
      'status','not_eligible',
      'reason','rank',
      'rank_key',cr.current_rank_key
    );
  end if;

  with closed as (
    select
      s.week_start,
      s.discipline_score,
      s.training_score,
      s.nutrition_score,
      s.hydration_score,
      s.movement_score,
      s.recovery_score,
      s.perfect_week
    from public.cv_rank_weekly_snapshots_v61 s
    where s.organization_id=p_organization
      and s.client_id=p_client
      and s.week_start between
        date_trunc('week',c.starts_on)::date
        and date_trunc(
          'week',
          least(c.ends_on,current_date)
        )::date
  )
  select
    count(*)::integer,
    count(*) filter(where perfect_week)::integer,
    round(avg(discipline_score),1),
    round(avg(training_score),1),
    round(avg(nutrition_score),1),
    round(avg(hydration_score),1),
    round(avg(movement_score),1),
    round(avg(recovery_score),1)
  into
    v_weeks,v_perfect,v_discipline,v_training,
    v_nutrition,v_hydration,v_movement,v_recovery
  from closed;

  if current_date between c.starts_on and c.ends_on
     and not exists(
       select 1
       from public.cv_rank_weekly_snapshots_v61 s
       where s.organization_id=p_organization
         and s.client_id=p_client
         and s.week_start=v_current_week
     ) then
    v_calc:=private.calculate_discipline_in_org_v61(
      p_organization,p_client,v_current_week
    );

    if greatest(c.starts_on,v_current_week)
       <=least(c.ends_on,v_current_week+6) then
      v_discipline:=round(
        (
          coalesce(v_discipline,0)*v_weeks+
          coalesce((v_calc->>'discipline_score')::numeric,0)
        )/greatest(1,v_weeks+1),
        1
      );

      if v_calc->>'training_score' is not null then
        v_training:=round(
          (
            coalesce(v_training,0)*v_weeks+
            coalesce((v_calc->>'training_score')::numeric,0)
          )/greatest(1,v_weeks+1),
          1
        );
      end if;

      if v_calc->>'nutrition_score' is not null then
        v_nutrition:=round(
          (
            coalesce(v_nutrition,0)*v_weeks+
            coalesce((v_calc->>'nutrition_score')::numeric,0)
          )/greatest(1,v_weeks+1),
          1
        );
      end if;

      if v_calc->>'hydration_score' is not null then
        v_hydration:=round(
          (
            coalesce(v_hydration,0)*v_weeks+
            coalesce((v_calc->>'hydration_score')::numeric,0)
          )/greatest(1,v_weeks+1),
          1
        );
      end if;

      if v_calc->>'movement_score' is not null then
        v_movement:=round(
          (
            coalesce(v_movement,0)*v_weeks+
            coalesce((v_calc->>'movement_score')::numeric,0)
          )/greatest(1,v_weeks+1),
          1
        );
      end if;

      if v_calc->>'recovery_score' is not null then
        v_recovery:=round(
          (
            coalesce(v_recovery,0)*v_weeks+
            coalesce((v_calc->>'recovery_score')::numeric,0)
          )/greatest(1,v_weeks+1),
          1
        );
      end if;

      v_weeks:=v_weeks+1;
    end if;
  end if;

  v_min_weeks:=greatest(
    1,
    coalesce(nullif(c.rules->>'min_weeks','')::integer,1)
  );

  v_meets:=
    v_weeks>=v_min_weeks
    and coalesce(v_discipline,100)>=
      coalesce(nullif(c.rules->>'discipline_pct','')::numeric,0)
    and coalesce(v_training,100)>=
      coalesce(nullif(c.rules->>'training_pct','')::numeric,0)
    and coalesce(v_nutrition,100)>=
      coalesce(nullif(c.rules->>'nutrition_pct','')::numeric,0)
    and coalesce(v_hydration,100)>=
      coalesce(nullif(c.rules->>'hydration_pct','')::numeric,0)
    and coalesce(v_movement,100)>=
      coalesce(nullif(c.rules->>'movement_pct','')::numeric,0)
    and coalesce(v_recovery,100)>=
      coalesce(nullif(c.rules->>'recovery_pct','')::numeric,0);

  v_score:=round(
    coalesce(v_discipline,0)+least(10,v_perfect*1.0),
    1
  );

  v_status:=case
    when c.status='closed' then
      case when v_meets then 'qualified' else 'not_qualified' end
    when v_meets then 'qualifying'
    else 'participating'
  end;

  return jsonb_build_object(
    'organization_id',p_organization,
    'eligible',true,
    'status',v_status,
    'meets_requirements',v_meets,
    'weeks_count',v_weeks,
    'min_weeks',v_min_weeks,
    'perfect_weeks',v_perfect,
    'score',v_score,
    'discipline_pct',v_discipline,
    'training_pct',v_training,
    'nutrition_pct',v_nutrition,
    'hydration_pct',v_hydration,
    'movement_pct',v_movement,
    'recovery_pct',v_recovery,
    'rank_key',cr.current_rank_key
  );
end;
$function$;

create or replace function private.cv_challenge_progress_v62(
  p_client uuid,
  p_challenge uuid
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_org uuid;
begin
  select organization_id into v_org
  from public.cv_challenges_v61
  where id=p_challenge;

  if v_org is null then
    raise exception 'challenge not found';
  end if;

  return private.cv_challenge_progress_in_org_v62(
    v_org,p_client,p_challenge
  );
end;
$function$;

create or replace function private.cv_refresh_challenge_entry_in_org_v62(
  p_organization uuid,
  p_client uuid,
  p_challenge uuid
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v jsonb;
begin
  v:=private.cv_challenge_progress_in_org_v62(
    p_organization,p_client,p_challenge
  );

  if coalesce((v->>'eligible')::boolean,false) then
    insert into public.cv_challenge_entries_v61(
      organization_id,challenge_id,client_id,status,score,progress
    )
    values(
      p_organization,
      p_challenge,
      p_client,
      coalesce(v->>'status','participating'),
      coalesce((v->>'score')::numeric,0),
      v
    )
    on conflict(challenge_id,client_id) do update set
      organization_id=excluded.organization_id,
      status=excluded.status,
      score=excluded.score,
      progress=excluded.progress,
      updated_at=now();
  else
    delete from public.cv_challenge_entries_v61
    where organization_id=p_organization
      and challenge_id=p_challenge
      and client_id=p_client;
  end if;

  return v;
end;
$function$;

create or replace function private.cv_refresh_challenge_entry_v62(
  p_client uuid,
  p_challenge uuid
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_org uuid;
begin
  select organization_id into v_org
  from public.cv_challenges_v61
  where id=p_challenge;

  if v_org is null then
    raise exception 'challenge not found';
  end if;

  return private.cv_refresh_challenge_entry_in_org_v62(
    v_org,p_client,p_challenge
  );
end;
$function$;

create or replace function private.cv_refresh_client_active_challenges_v62()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  r record;
begin
  for r in
    select id
    from public.cv_challenges_v61 c
    where c.organization_id=new.organization_id
      and c.status='active'
      and new.week_start<=c.ends_on
      and new.week_end>=c.starts_on
  loop
    perform private.cv_refresh_challenge_entry_in_org_v62(
      new.organization_id,new.client_id,r.id
    );
  end loop;

  return new;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 3) Challenge finalization
-- ---------------------------------------------------------------------------

create or replace function private.cv_finalize_challenge_in_org_v62(
  p_organization uuid,
  p_challenge uuid,
  p_actor uuid
)
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  c public.cv_challenges_v61%rowtype;
  r record;
  v integer:=0;
begin
  if not private.cv_is_coach_admin_in_org_v62(
    p_organization,p_actor
  ) then
    raise exception 'coach/admin required in challenge organization';
  end if;

  select * into c
  from public.cv_challenges_v61
  where id=p_challenge
    and organization_id=p_organization;

  if not found then
    raise exception 'challenge not found';
  end if;

  delete from public.cv_challenge_winners_v61
  where organization_id=p_organization
    and challenge_id=p_challenge
    and status='provisional';

  if c.challenge_mode='lottery' then
    for r in
      select
        client_id,
        row_number() over(order by random())::integer placement
      from public.cv_challenge_entries_v61
      where organization_id=p_organization
        and challenge_id=p_challenge
        and status='qualified'
      order by random()
      limit c.winner_count
    loop
      insert into public.cv_challenge_winners_v61(
        organization_id,challenge_id,client_id,placement,status,metadata
      )
      values(
        p_organization,p_challenge,r.client_id,r.placement,
        'provisional',
        jsonb_build_object(
          'organization_id',p_organization,
          'method','lottery',
          'v','62'
        )
      );
      v:=v+1;
    end loop;
  else
    for r in
      select
        client_id,
        row_number() over(
          order by score desc,updated_at asc
        )::integer placement
      from public.cv_challenge_entries_v61
      where organization_id=p_organization
        and challenge_id=p_challenge
        and status='qualified'
      order by score desc,updated_at asc
      limit c.winner_count
    loop
      insert into public.cv_challenge_winners_v61(
        organization_id,challenge_id,client_id,placement,status,metadata
      )
      values(
        p_organization,p_challenge,r.client_id,r.placement,
        'provisional',
        jsonb_build_object(
          'organization_id',p_organization,
          'method',c.challenge_mode,
          'v','62'
        )
      );
      v:=v+1;
    end loop;
  end if;

  return v;
end;
$function$;

create or replace function private.cv_finalize_challenge_v62(
  p_challenge uuid,
  p_actor uuid
)
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_org uuid;
begin
  select organization_id into v_org
  from public.cv_challenges_v61
  where id=p_challenge;

  if v_org is null then
    raise exception 'challenge not found';
  end if;

  return private.cv_finalize_challenge_in_org_v62(
    v_org,p_challenge,p_actor
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 4) Challenge / Season creation
-- ---------------------------------------------------------------------------

create or replace function private.create_cv_challenge_in_org_v62(
  p_organization uuid,
  p_actor_id uuid,
  p_name text,
  p_description text,
  p_starts_on date,
  p_ends_on date,
  p_mode text,
  p_rules jsonb,
  p_reward_title text,
  p_reward_type text,
  p_winner_count integer default 1
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_id uuid;
  v_bad text;
begin
  if not private.cv_is_coach_admin_in_org_v62(
    p_organization,p_actor_id
  ) then
    raise exception 'coach/admin required in organization';
  end if;

  if length(trim(coalesce(p_name,'')))<3 then
    raise exception 'challenge name required';
  end if;
  if p_starts_on is null
     or p_ends_on is null
     or p_ends_on<p_starts_on then
    raise exception 'invalid dates';
  end if;
  if p_mode not in('requirements','ranking','top_n','lottery') then
    raise exception 'invalid challenge mode';
  end if;
  if coalesce(p_reward_type,'digital')
     not in('digital','physical','service','discount') then
    raise exception 'invalid reward type';
  end if;

  select key into v_bad
  from jsonb_object_keys(coalesce(p_rules,'{}'::jsonb)) key
  where key not in(
    'training_pct',
    'nutrition_pct',
    'hydration_pct',
    'movement_pct',
    'recovery_pct',
    'discipline_pct',
    'min_weeks',
    'eligible_ranks'
  )
  limit 1;

  if v_bad is not null then
    raise exception 'unsupported rule: %',v_bad;
  end if;

  insert into public.cv_challenges_v61(
    organization_id,name,description,starts_on,ends_on,status,
    challenge_mode,rules,reward_title,reward_type,winner_count,created_by
  )
  values(
    p_organization,
    trim(p_name),
    nullif(trim(coalesce(p_description,'')),''),
    p_starts_on,
    p_ends_on,
    'draft',
    p_mode,
    coalesce(p_rules,'{}'::jsonb),
    nullif(trim(coalesce(p_reward_title,'')),''),
    coalesce(p_reward_type,'digital'),
    greatest(1,least(100,p_winner_count)),
    p_actor_id
  )
  returning id into v_id;

  return v_id;
end;
$function$;

create or replace function public.create_cv_challenge_v62(
  p_actor_id uuid,
  p_name text,
  p_description text,
  p_starts_on date,
  p_ends_on date,
  p_mode text,
  p_rules jsonb,
  p_reward_title text,
  p_reward_type text,
  p_winner_count integer default 1
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_org uuid;
begin
  if auth.uid() is not null and auth.uid()<>p_actor_id then
    raise exception 'actor mismatch';
  end if;

  v_org:=private.resolve_legacy_professional_organization_v1(
    p_actor_id,null
  );

  return private.create_cv_challenge_in_org_v62(
    v_org,p_actor_id,p_name,p_description,p_starts_on,p_ends_on,
    p_mode,p_rules,p_reward_title,p_reward_type,p_winner_count
  );
end;
$function$;

create or replace function public.create_cv_challenge_v61(
  p_actor_id uuid,
  p_name text,
  p_description text,
  p_starts_on date,
  p_ends_on date,
  p_mode text,
  p_rules jsonb,
  p_reward_title text,
  p_reward_type text,
  p_winner_count integer default 1
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
begin
  return public.create_cv_challenge_v62(
    p_actor_id,p_name,p_description,p_starts_on,p_ends_on,
    p_mode,p_rules,p_reward_title,p_reward_type,p_winner_count
  );
end;
$function$;

create or replace function private.create_cv_season_in_org_v62(
  p_organization uuid,
  p_actor_id uuid,
  p_name text,
  p_starts_on date,
  p_ends_on date
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_id uuid;
begin
  if not private.cv_is_coach_admin_in_org_v62(
    p_organization,p_actor_id
  ) then
    raise exception 'coach/admin required in organization';
  end if;

  if length(trim(coalesce(p_name,'')))<3 then
    raise exception 'season name required';
  end if;
  if p_starts_on is null
     or p_ends_on is null
     or p_ends_on<p_starts_on then
    raise exception 'invalid dates';
  end if;

  insert into public.cv_seasons_v61(
    organization_id,name,starts_on,ends_on,status,created_by
  )
  values(
    p_organization,trim(p_name),p_starts_on,p_ends_on,'draft',p_actor_id
  )
  returning id into v_id;

  return v_id;
end;
$function$;

create or replace function public.create_cv_season_v62(
  p_actor_id uuid,
  p_name text,
  p_starts_on date,
  p_ends_on date
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_org uuid;
begin
  if auth.uid() is not null and auth.uid()<>p_actor_id then
    raise exception 'actor mismatch';
  end if;

  v_org:=private.resolve_legacy_professional_organization_v1(
    p_actor_id,null
  );

  return private.create_cv_season_in_org_v62(
    v_org,p_actor_id,p_name,p_starts_on,p_ends_on
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 5) Administration
-- ---------------------------------------------------------------------------

create or replace function public.refresh_cv_challenge_v62(
  p_actor_id uuid,
  p_challenge_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  r record;
  v_count integer:=0;
  v_org uuid;
begin
  if auth.uid() is not null and auth.uid()<>p_actor_id then
    raise exception 'actor mismatch';
  end if;

  select organization_id into v_org
  from public.cv_challenges_v61
  where id=p_challenge_id;

  if v_org is null then
    raise exception 'challenge not found';
  end if;

  if not private.cv_is_coach_admin_in_org_v62(
    v_org,p_actor_id
  ) then
    raise exception 'coach/admin required in challenge organization';
  end if;

  for r in
    select client_id
    from public.client_competitive_rank_v61
    where organization_id=v_org
      and tutorial_completed=true
  loop
    perform private.cv_refresh_challenge_entry_in_org_v62(
      v_org,r.client_id,p_challenge_id
    );
    v_count:=v_count+1;
  end loop;

  return jsonb_build_object(
    'organization_id',v_org,
    'challenge_id',p_challenge_id,
    'clients_checked',v_count
  );
end;
$function$;

create or replace function public.set_cv_challenge_status_v62(
  p_actor_id uuid,
  p_challenge_id uuid,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_winners integer:=0;
  v_org uuid;
begin
  if auth.uid() is not null and auth.uid()<>p_actor_id then
    raise exception 'actor mismatch';
  end if;

  if p_status not in('draft','active','closed','cancelled') then
    raise exception 'invalid status';
  end if;

  select organization_id into v_org
  from public.cv_challenges_v61
  where id=p_challenge_id;

  if v_org is null then
    raise exception 'challenge not found';
  end if;

  if not private.cv_is_coach_admin_in_org_v62(
    v_org,p_actor_id
  ) then
    raise exception 'coach/admin required in challenge organization';
  end if;

  update public.cv_challenges_v61
  set status=p_status,
      updated_at=now()
  where id=p_challenge_id
    and organization_id=v_org;

  if p_status in('active','closed') then
    perform public.refresh_cv_challenge_v62(
      p_actor_id,p_challenge_id
    );
  end if;

  if p_status='closed' then
    v_winners:=private.cv_finalize_challenge_in_org_v62(
      v_org,p_challenge_id,p_actor_id
    );
  end if;

  return jsonb_build_object(
    'organization_id',v_org,
    'challenge_id',p_challenge_id,
    'status',p_status,
    'provisional_winners',v_winners
  );
end;
$function$;

create or replace function public.set_cv_challenge_status_v61(
  p_actor_id uuid,
  p_challenge_id uuid,
  p_status text
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
begin
  perform public.set_cv_challenge_status_v62(
    p_actor_id,p_challenge_id,p_status
  );
end;
$function$;

create or replace function public.set_cv_season_status_v62(
  p_actor_id uuid,
  p_season_id uuid,
  p_status text
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_org uuid;
begin
  if auth.uid() is not null and auth.uid()<>p_actor_id then
    raise exception 'actor mismatch';
  end if;

  if p_status not in('draft','active','closed','cancelled') then
    raise exception 'invalid status';
  end if;

  select organization_id into v_org
  from public.cv_seasons_v61
  where id=p_season_id;

  if v_org is null then
    raise exception 'season not found';
  end if;

  if not private.cv_is_coach_admin_in_org_v62(
    v_org,p_actor_id
  ) then
    raise exception 'coach/admin required in season organization';
  end if;

  if p_status='active'
     and exists(
       select 1
       from public.cv_seasons_v61 s
       where s.organization_id=v_org
         and s.status='active'
         and s.id<>p_season_id
     ) then
    raise exception 'another season is active in organization';
  end if;

  update public.cv_seasons_v61
  set status=p_status,
      updated_at=now()
  where id=p_season_id
    and organization_id=v_org;
end;
$function$;

create or replace function public.set_cv_challenge_winner_v62(
  p_actor_id uuid,
  p_winner_id uuid,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  w public.cv_challenge_winners_v61%rowtype;
  v_org uuid;
begin
  if auth.uid() is not null and auth.uid()<>p_actor_id then
    raise exception 'actor mismatch';
  end if;

  if p_status not in('approved','rejected','fulfilled') then
    raise exception 'invalid winner status';
  end if;

  select organization_id into v_org
  from public.cv_challenge_winners_v61
  where id=p_winner_id;

  if v_org is null then
    raise exception 'winner not found';
  end if;

  if not private.cv_is_coach_admin_in_org_v62(
    v_org,p_actor_id
  ) then
    raise exception 'coach/admin required in winner organization';
  end if;

  update public.cv_challenge_winners_v61
  set status=p_status,
      approved_by=case
        when p_status in('approved','fulfilled') then p_actor_id
        else approved_by
      end,
      approved_at=case
        when p_status in('approved','fulfilled')
          then coalesce(approved_at,now())
        else approved_at
      end,
      fulfilled_at=case
        when p_status='fulfilled' then now()
        else fulfilled_at
      end
  where id=p_winner_id
    and organization_id=v_org
  returning * into w;

  return to_jsonb(w);
end;
$function$;

-- ---------------------------------------------------------------------------
-- 6) Client / Coach reads
-- ---------------------------------------------------------------------------

create or replace function public.get_client_challenges_v61(
  p_actor_id uuid,
  p_client_id uuid default null::uuid
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_client uuid:=coalesce(p_client_id,p_actor_id);
  v_org uuid;
  v_rows jsonb;
  r record;
begin
  if auth.uid() is not null and auth.uid()<>p_actor_id then
    raise exception 'actor mismatch';
  end if;

  if p_actor_id=v_client then
    v_org:=private.resolve_legacy_client_organization_v1(
      v_client,null
    );
  else
    v_org:=private.resolve_legacy_professional_organization_v1(
      p_actor_id,v_client
    );
  end if;

  if not private.cv_rank_authorized_client_in_org_v61(
    v_org,p_actor_id,v_client
  ) then
    raise exception 'not authorized';
  end if;

  for r in
    select id
    from public.cv_challenges_v61
    where organization_id=v_org
      and status in('active','closed')
      and starts_on<=current_date+30
  loop
    perform private.cv_refresh_challenge_entry_in_org_v62(
      v_org,v_client,r.id
    );
  end loop;

  select coalesce(
    jsonb_agg(to_jsonb(x) order by x.starts_on desc),
    '[]'::jsonb
  )
  into v_rows
  from (
    select
      c.id,
      c.name,
      c.description,
      c.starts_on,
      c.ends_on,
      c.status,
      c.challenge_mode,
      c.rules,
      c.reward_title,
      c.reward_type,
      c.reward_image_path,
      c.winner_count,
      coalesce(e.status,'participating') participation_status,
      coalesce(e.score,0) score,
      coalesce(e.progress,'{}'::jsonb) progress
    from public.cv_challenges_v61 c
    left join public.cv_challenge_entries_v61 e
      on e.organization_id=c.organization_id
     and e.challenge_id=c.id
     and e.client_id=v_client
    where c.organization_id=v_org
      and c.status in('active','closed')
      and c.starts_on<=current_date+30
    order by c.starts_on desc
  ) x;

  return jsonb_build_object(
    'version','v62',
    'organization_id',v_org,
    'rows',v_rows
  );
end;
$function$;

create or replace function public.get_coach_challenges_v62(
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_rows jsonb;
  v_org uuid;
begin
  if auth.uid() is not null and auth.uid()<>p_actor_id then
    raise exception 'actor mismatch';
  end if;

  v_org:=private.resolve_legacy_professional_organization_v1(
    p_actor_id,null
  );

  if not private.cv_is_coach_admin_in_org_v62(
    v_org,p_actor_id
  ) then
    raise exception 'coach/admin required';
  end if;

  select coalesce(
    jsonb_agg(to_jsonb(x) order by x.starts_on desc),
    '[]'::jsonb
  )
  into v_rows
  from (
    select
      c.*,
      (
        select count(*)::integer
        from public.cv_challenge_entries_v61 e
        where e.organization_id=v_org
          and e.challenge_id=c.id
      ) participants,
      (
        select count(*)::integer
        from public.cv_challenge_entries_v61 e
        where e.organization_id=v_org
          and e.challenge_id=c.id
          and e.status in('qualifying','qualified')
      ) qualifying,
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id',w.id,
              'placement',w.placement,
              'status',w.status,
              'client_id',w.client_id,
              'alias',coalesce(
                cr.competitive_alias,
                private.cv_alias_v61(w.client_id)
              )
            )
            order by w.placement
          )
          from public.cv_challenge_winners_v61 w
          left join public.client_competitive_rank_v61 cr
            on cr.organization_id=w.organization_id
           and cr.client_id=w.client_id
          where w.organization_id=v_org
            and w.challenge_id=c.id
        ),
        '[]'::jsonb
      ) winners
    from public.cv_challenges_v61 c
    where c.organization_id=v_org
    order by c.starts_on desc
  ) x;

  return jsonb_build_object(
    'version','v62',
    'organization_id',v_org,
    'rows',v_rows
  );
end;
$function$;

create or replace function public.get_coach_seasons_v62(
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_rows jsonb;
  v_org uuid;
begin
  if auth.uid() is not null and auth.uid()<>p_actor_id then
    raise exception 'actor mismatch';
  end if;

  v_org:=private.resolve_legacy_professional_organization_v1(
    p_actor_id,null
  );

  if not private.cv_is_coach_admin_in_org_v62(
    v_org,p_actor_id
  ) then
    raise exception 'coach/admin required';
  end if;

  select coalesce(
    jsonb_agg(to_jsonb(x) order by x.starts_on desc),
    '[]'::jsonb
  )
  into v_rows
  from (
    select
      s.*,
      coalesce(
        (
          select count(distinct p.client_id)::integer
          from public.cv_season_weekly_points_v61 p
          where p.organization_id=v_org
            and p.season_id=s.id
        ),
        0
      ) participants,
      coalesce(
        (
          select jsonb_agg(
            to_jsonb(y)
            order by y.position
          )
          from (
            select
              row_number() over(
                order by sum(p.points) desc
              )::integer position,
              p.client_id,
              coalesce(
                cr.competitive_alias,
                private.cv_alias_v61(p.client_id)
              ) alias,
              round(sum(p.points),1) points
            from public.cv_season_weekly_points_v61 p
            left join public.client_competitive_rank_v61 cr
              on cr.organization_id=p.organization_id
             and cr.client_id=p.client_id
            where p.organization_id=v_org
              and p.season_id=s.id
            group by p.client_id,cr.competitive_alias
            order by points desc
            limit 3
          ) y
        ),
        '[]'::jsonb
      ) top3
    from public.cv_seasons_v61 s
    where s.organization_id=v_org
    order by s.starts_on desc
  ) x;

  return jsonb_build_object(
    'version','v62',
    'organization_id',v_org,
    'rows',v_rows
  );
end;
$function$;

create or replace function public.get_cv_ranking_v61(
  p_actor_id uuid,
  p_scope text default 'global'::text,
  p_limit integer default 50,
  p_offset integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_role text;
  v_org uuid;
  v_rank text;
  v_rows jsonb;
  v_season uuid;
begin
  if auth.uid() is not null and auth.uid()<>p_actor_id then
    raise exception 'actor mismatch';
  end if;

  select role::text into v_role
  from public.profiles
  where id=p_actor_id
    and status::text='active';

  if v_role is null then
    raise exception 'not authorized';
  end if;

  if v_role='client' then
    v_org:=private.resolve_legacy_client_organization_v1(
      p_actor_id,null
    );
  elsif v_role in('coach','admin') then
    v_org:=private.resolve_legacy_professional_organization_v1(
      p_actor_id,null
    );
    if not private.cv_is_coach_admin_in_org_v62(
      v_org,p_actor_id
    ) then
      raise exception 'not authorized in organization';
    end if;
  else
    raise exception 'not authorized';
  end if;

  if p_scope='league' then
    select current_rank_key into v_rank
    from public.client_competitive_rank_v61
    where organization_id=v_org
      and client_id=p_actor_id;
  end if;

  if p_scope='season' then
    select id into v_season
    from public.cv_seasons_v61
    where organization_id=v_org
      and status='active'
    order by starts_on desc
    limit 1;
  end if;

  if p_scope='season' and v_season is not null then
    select coalesce(
      jsonb_agg(to_jsonb(x) order by x.position),
      '[]'::jsonb
    )
    into v_rows
    from (
      select
        row_number() over(
          order by sum(sp.points) desc,cr.cv_rating desc
        )::integer position,
        case
          when v_role in('coach','admin')
               or cr.client_id=p_actor_id
            then cr.client_id
          else null
        end client_ref,
        (cr.client_id=p_actor_id) is_me,
        coalesce(
          cr.competitive_alias,
          private.cv_alias_v61(cr.client_id)
        ) alias,
        cr.current_level,
        cr.current_rank_key,
        round(sum(sp.points),1) score,
        rr.rank_name,
        rr.badge_path
      from public.cv_season_weekly_points_v61 sp
      join public.client_competitive_rank_v61 cr
        on cr.organization_id=sp.organization_id
       and cr.client_id=sp.client_id
      join public.cv_rank_rules_v61 rr
        on rr.rank_key=cr.current_rank_key
      where sp.organization_id=v_org
        and sp.season_id=v_season
        and cr.show_global=true
      group by
        cr.client_id,
        cr.competitive_alias,
        cr.current_level,
        cr.current_rank_key,
        cr.cv_rating,
        rr.rank_name,
        rr.badge_path
      order by score desc
      limit greatest(1,least(100,p_limit))
      offset greatest(0,p_offset)
    ) x;
  else
    select coalesce(
      jsonb_agg(to_jsonb(x) order by x.position),
      '[]'::jsonb
    )
    into v_rows
    from (
      select
        row_number() over(
          order by
            cr.cv_rating desc,
            cr.rolling_4_week_score desc nulls last,
            cr.rolling_12_week_score desc nulls last,
            cr.updated_at asc
        )::integer position,
        case
          when v_role in('coach','admin')
               or cr.client_id=p_actor_id
            then cr.client_id
          else null
        end client_ref,
        (cr.client_id=p_actor_id) is_me,
        coalesce(
          cr.competitive_alias,
          private.cv_alias_v61(cr.client_id)
        ) alias,
        cr.current_level,
        cr.current_rank_key,
        round(cr.cv_rating,0) score,
        rr.rank_name,
        rr.badge_path
      from public.client_competitive_rank_v61 cr
      join public.cv_rank_rules_v61 rr
        on rr.rank_key=cr.current_rank_key
      where cr.organization_id=v_org
        and cr.show_global=true
        and cr.tutorial_completed=true
        and (
          p_scope<>'league'
          or cr.current_rank_key=v_rank
        )
      order by
        cr.cv_rating desc,
        cr.rolling_4_week_score desc nulls last
      limit greatest(1,least(100,p_limit))
      offset greatest(0,p_offset)
    ) x;
  end if;

  return jsonb_build_object(
    'scope',p_scope,
    'organization_id',v_org,
    'season_id',v_season,
    'rows',coalesce(v_rows,'[]'::jsonb)
  );
end;
$function$;

comment on function private.cv_challenge_progress_in_org_v62(uuid,uuid,uuid) is
  'F1.M1.S5 F2B tenant-explicit challenge progress engine.';
comment on function private.create_cv_challenge_in_org_v62(uuid,uuid,text,text,date,date,text,jsonb,text,text,integer) is
  'F1.M1.S5 F2B explicit-tenant challenge creator; legacy public RPC resolves a single professional Organization.';
