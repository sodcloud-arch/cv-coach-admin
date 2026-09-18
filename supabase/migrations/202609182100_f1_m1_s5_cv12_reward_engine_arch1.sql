-- ARCH-1.0 · F1.M1.S5 Wave E2A — CV12 Reward Engine tenant hardening
-- Converts the reward/state helper layer to explicit Organization context.
-- client_cv_state keeps its legacy PK(client_id) until E2B migrates CV Score.

-- ---------------------------------------------------------------------------
-- 1) Tenant-scoped idempotency / uniqueness controlled by E2A writers
-- ---------------------------------------------------------------------------

alter table private.cv12_reward_processing
  drop constraint if exists cv12_reward_processing_client_id_event_key_source_id_key;

drop index if exists private.cv12_reward_processing_client_id_event_key_source_id_key;

create unique index if not exists uq_cv12_reward_processing_org_event_source
  on private.cv12_reward_processing(
    organization_id,client_id,event_key,source_id
  );

alter table public.client_level_history
  drop constraint if exists client_level_history_client_id_level_number_key;

drop index if exists public.client_level_history_client_id_level_number_key;

create unique index if not exists uq_client_level_history_org_level
  on public.client_level_history(
    organization_id,client_id,level_number
  );

alter table public.client_achievements
  drop constraint if exists client_achievements_client_id_achievement_id_key;

drop index if exists public.client_achievements_client_id_achievement_id_key;

create unique index if not exists uq_client_achievements_org_achievement
  on public.client_achievements(
    organization_id,client_id,achievement_id
  );

drop index if exists public.uq_xp_source_once;
create unique index uq_xp_source_once_org
  on public.xp_ledger(
    organization_id,client_id,source_type,source_id
  )
  where source_id is not null
    and reversed_at is null;

drop index if exists public.uq_credit_source_once;
create unique index uq_credit_source_once_org
  on public.credit_ledger(
    organization_id,client_id,source_type,source_id,transaction_type
  )
  where source_id is not null;

-- Future E2B PK cutover support.
create unique index if not exists ux_client_cv_state_org_client
  on public.client_cv_state(organization_id,client_id);

-- ---------------------------------------------------------------------------
-- 2) Level requirements — explicit tenant variant + legacy wrapper
-- ---------------------------------------------------------------------------

create or replace function private.level_requirements_met_in_org(
  p_organization_id uuid,
  p_client_id uuid,
  p_level integer
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  r record;
  v_metric numeric;
  v_ok boolean;
  v_since timestamptz;
begin
  if p_organization_id is null or p_client_id is null then
    return false;
  end if;

  if not exists(
    select 1
    from public.clients c
    where c.organization_id=p_organization_id
      and c.user_id=p_client_id
      and c.status<>'archived'::public.client_status
  ) then
    return false;
  end if;

  for r in
    select requirement_type,pillar,operator,target_value,window_days
    from public.level_requirements
    where level_number<=p_level
    order by level_number,id
  loop
    v_metric:=null;
    v_since:=case
      when r.window_days is null then null
      else now()-make_interval(days=>r.window_days)
    end;

    case r.requirement_type
      when 'cv_score' then
        select s.cv_score into v_metric
        from public.cv_score_snapshots s
        where s.organization_id=p_organization_id
          and s.client_id=p_client_id
          and (v_since is null or s.calculated_at>=v_since)
        order by s.calculated_at desc
        limit 1;
      when 'training_score' then
        select s.training_score into v_metric
        from public.cv_score_snapshots s
        where s.organization_id=p_organization_id
          and s.client_id=p_client_id
          and (v_since is null or s.calculated_at>=v_since)
        order by s.calculated_at desc
        limit 1;
      when 'nutrition_score' then
        select s.nutrition_score into v_metric
        from public.cv_score_snapshots s
        where s.organization_id=p_organization_id
          and s.client_id=p_client_id
          and (v_since is null or s.calculated_at>=v_since)
        order by s.calculated_at desc
        limit 1;
      when 'habit_score' then
        select s.habit_score into v_metric
        from public.cv_score_snapshots s
        where s.organization_id=p_organization_id
          and s.client_id=p_client_id
          and (v_since is null or s.calculated_at>=v_since)
        order by s.calculated_at desc
        limit 1;
      when 'progress_score' then
        select s.progress_score into v_metric
        from public.cv_score_snapshots s
        where s.organization_id=p_organization_id
          and s.client_id=p_client_id
          and (v_since is null or s.calculated_at>=v_since)
        order by s.calculated_at desc
        limit 1;
      when 'workout_count' then
        select count(*)::numeric into v_metric
        from public.workout_sessions ws
        where ws.organization_id=p_organization_id
          and ws.client_id=p_client_id
          and ws.status='completed'::public.workout_session_status
          and (v_since is null or ws.finished_at>=v_since);
      when 'completed_missions' then
        select count(*)::numeric into v_metric
        from public.client_missions cm
        where cm.organization_id=p_organization_id
          and cm.client_id=p_client_id
          and cm.status='completed'::public.client_mission_status
          and (v_since is null or cm.completed_at>=v_since);
      else
        return false;
    end case;

    if v_metric is null then
      return false;
    end if;

    v_ok:=case r.operator
      when '>=' then v_metric>=r.target_value
      when '>' then v_metric>r.target_value
      when '<=' then v_metric<=r.target_value
      when '<' then v_metric<r.target_value
      when '=' then v_metric=r.target_value
      else false
    end;

    if not v_ok then
      return false;
    end if;
  end loop;

  return true;
end;
$function$;

create or replace function private.level_requirements_met(
  p_client_id uuid,
  p_level integer
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_organization uuid;
begin
  v_organization:=private.resolve_legacy_client_organization_v1(
    p_client_id,null
  );
  return private.level_requirements_met_in_org(
    v_organization,p_client_id,p_level
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 3) Reward action engine — explicit tenant variant + legacy wrapper
-- ---------------------------------------------------------------------------

create or replace function private.award_cv12_action_in_org(
  p_organization_id uuid,
  p_client_id uuid,
  p_event_key text,
  p_source_id uuid,
  p_event_date date,
  p_description text,
  p_xp_override integer default null::integer
)
returns table(
  xp_awarded integer,
  credits_awarded integer,
  idempotent boolean,
  cap_reached boolean
)
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_reward private.cv12_action_rewards%rowtype;
  v_processing_id uuid;
  v_existing private.cv12_reward_processing%rowtype;
  v_daily integer:=0;
  v_weekly integer:=0;
  v_xp integer:=0;
  v_credits integer:=0;
  v_week_start date;
begin
  if p_organization_id is null
     or p_client_id is null
     or p_event_key is null
     or p_source_id is null
     or p_event_date is null then
    raise exception 'organization_id, client_id, event_key, source_id and event_date are required';
  end if;

  if not exists(
    select 1
    from public.clients c
    where c.organization_id=p_organization_id
      and c.user_id=p_client_id
      and c.status<>'archived'::public.client_status
  ) then
    raise exception 'client is not active in requested organization';
  end if;

  select * into v_reward
  from private.cv12_action_rewards r
  where r.event_key=p_event_key
    and r.active=true;

  if not found then
    raise exception 'unknown or inactive CV12 event: %',p_event_key;
  end if;

  insert into private.cv12_reward_processing(
    organization_id,client_id,event_key,source_id,event_date
  )
  values(
    p_organization_id,p_client_id,p_event_key,p_source_id,p_event_date
  )
  on conflict(
    organization_id,client_id,event_key,source_id
  ) do nothing
  returning id into v_processing_id;

  if v_processing_id is null then
    select * into v_existing
    from private.cv12_reward_processing
    where organization_id=p_organization_id
      and client_id=p_client_id
      and event_key=p_event_key
      and source_id=p_source_id;

    return query
    select
      0,
      0,
      true,
      (
        v_existing.xp_awarded=0
        and v_existing.credits_awarded=0
        and (
          v_reward.xp_reward>0
          or v_reward.credit_reward>0
        )
      );
    return;
  end if;

  select count(*)::integer into v_daily
  from private.cv12_reward_processing p
  where p.organization_id=p_organization_id
    and p.client_id=p_client_id
    and p.event_key=p_event_key
    and p.event_date=p_event_date
    and p.id<>v_processing_id;

  v_week_start:=date_trunc(
    'week',
    p_event_date::timestamp
  )::date;

  select count(*)::integer into v_weekly
  from private.cv12_reward_processing p
  where p.organization_id=p_organization_id
    and p.client_id=p_client_id
    and p.event_key=p_event_key
    and p.event_date between v_week_start and v_week_start+6
    and p.id<>v_processing_id;

  if (
    v_reward.daily_cap_count is not null
    and v_daily>=v_reward.daily_cap_count
  ) or (
    v_reward.weekly_cap_count is not null
    and v_weekly>=v_reward.weekly_cap_count
  ) then
    update private.cv12_reward_processing
    set xp_awarded=0,
        credits_awarded=0,
        processed_at=now()
    where id=v_processing_id
      and organization_id=p_organization_id;

    return query select 0,0,false,true;
    return;
  end if;

  v_xp:=greatest(
    0,
    coalesce(p_xp_override,v_reward.xp_reward)
  );
  v_credits:=greatest(0,v_reward.credit_reward);

  if v_xp>0 then
    insert into public.xp_ledger(
      organization_id,client_id,pillar,source_type,
      source_id,amount,description
    )
    values(
      p_organization_id,p_client_id,v_reward.pillar,
      p_event_key,p_source_id,v_xp,p_description
    )
    on conflict do nothing;
  end if;

  if v_credits>0 then
    insert into public.credit_ledger(
      organization_id,client_id,transaction_type,
      source_type,source_id,amount,description
    )
    values(
      p_organization_id,p_client_id,
      'earned'::public.credit_transaction_type,
      p_event_key,p_source_id,v_credits,p_description
    )
    on conflict do nothing;
  end if;

  update private.cv12_reward_processing
  set xp_awarded=v_xp,
      credits_awarded=v_credits,
      processed_at=now()
  where id=v_processing_id
    and organization_id=p_organization_id;

  return query
  select v_xp,v_credits,false,false;
end;
$function$;

create or replace function private.award_cv12_action(
  p_client_id uuid,
  p_event_key text,
  p_source_id uuid,
  p_event_date date,
  p_description text,
  p_xp_override integer default null::integer
)
returns table(
  xp_awarded integer,
  credits_awarded integer,
  idempotent boolean,
  cap_reached boolean
)
language plpgsql
security definer
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
  from private.award_cv12_action_in_org(
    v_organization,
    p_client_id,
    p_event_key,
    p_source_id,
    p_event_date,
    p_description,
    p_xp_override
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 4) Mission engine — explicit tenant variant + legacy wrapper
-- ---------------------------------------------------------------------------

create or replace function private.process_event_missions_in_org(
  p_organization_id uuid,
  p_client_id uuid,
  p_event_key text,
  p_habit_category text default null::text
)
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  m record;
  v_progress numeric;
  v_start date;
  v_end date;
  v_window integer;
  v_new integer:=0;
  v_inserted integer;
begin
  for m in
    select
      cm.id,cm.target,cm.start_at,cm.expires_at,
      cm.mission_name,cm.xp_reward_snapshot,
      cm.credit_reward_snapshot,mt.rule
    from public.client_missions cm
    join public.mission_templates mt
      on mt.id=cm.mission_template_id
    where cm.organization_id=p_organization_id
      and cm.client_id=p_client_id
      and cm.status='active'::public.client_mission_status
      and cm.start_at<=now()
      and (
        cm.expires_at is null
        or cm.expires_at>=now()
      )
      and coalesce(mt.rule->>'event','')=p_event_key
    for update of cm
  loop
    if (
      m.rule ? 'habit_category'
    ) and coalesce(
      m.rule->>'habit_category',''
    )<>coalesce(p_habit_category,'') then
      continue;
    end if;

    v_window:=greatest(
      1,
      coalesce(
        nullif(m.rule->>'window_days','')::integer,
        7
      )
    );

    v_end:=least(
      current_date,
      coalesce(m.expires_at::date,current_date)
    );
    v_start:=greatest(
      m.start_at::date,
      v_end-(v_window-1)
    );
    v_progress:=0;

    if p_event_key='nutrition_compliant' then
      select count(*)::numeric into v_progress
      from public.nutrition_daily_logs n
      where n.organization_id=p_organization_id
        and n.client_id=p_client_id
        and n.compliant=true
        and n.log_date between v_start and v_end;
    elsif p_event_key in (
      'habit_completed','cardio_completed'
    ) then
      select count(*)::numeric into v_progress
      from public.habit_logs hl
      join public.client_habits ch
        on ch.organization_id=hl.organization_id
       and ch.id=hl.client_habit_id
      join public.habit_definitions hd
        on hd.id=ch.habit_id
      where hl.organization_id=p_organization_id
        and hl.client_id=p_client_id
        and hl.completed=true
        and hl.log_date between v_start and v_end
        and (
          (
            p_event_key='cardio_completed'
            and hd.category='cardio'
          )
          or
          (
            p_event_key='habit_completed'
            and (
              not (m.rule ? 'habit_category')
              or hd.category=(m.rule->>'habit_category')
            )
          )
        );
    else
      continue;
    end if;

    update public.client_missions
    set progress=least(target,v_progress),
        status=case
          when v_progress>=target
            then 'completed'::public.client_mission_status
          else status
        end,
        completed_at=case
          when v_progress>=target
            then coalesce(completed_at,now())
          else completed_at
        end,
        updated_at=now()
    where organization_id=p_organization_id
      and id=m.id;

    if v_progress>=m.target then
      v_inserted:=0;

      if m.xp_reward_snapshot>0 then
        insert into public.xp_ledger(
          organization_id,client_id,pillar,source_type,
          source_id,amount,description
        )
        values(
          p_organization_id,
          p_client_id,
          coalesce(
            (
              select mt.pillar
              from public.mission_templates mt
              join public.client_missions cm2
                on cm2.mission_template_id=mt.id
              where cm2.organization_id=p_organization_id
                and cm2.id=m.id
            ),
            'habits'
          ),
          'mission_completed',
          m.id,
          m.xp_reward_snapshot,
          'Misión completada: '||m.mission_name
        )
        on conflict do nothing;
        get diagnostics v_inserted=row_count;
      else
        v_inserted:=1;
      end if;

      if m.credit_reward_snapshot>0 then
        insert into public.credit_ledger(
          organization_id,client_id,transaction_type,
          source_type,source_id,amount,description
        )
        values(
          p_organization_id,
          p_client_id,
          'earned'::public.credit_transaction_type,
          'mission_completed',
          m.id,
          m.credit_reward_snapshot,
          'Misión completada: '||m.mission_name
        )
        on conflict do nothing;
      end if;

      if v_inserted>0 then
        v_new:=v_new+1;

        insert into public.notifications(
          user_id,type,title,body,action_url,metadata
        )
        values(
          p_client_id,
          'mission_completed',
          'Misión completada',
          'Completaste '||m.mission_name,
          '/progress/missions',
          jsonb_build_object(
            'organization_id',p_organization_id,
            'mission_id',m.id
          )
        );
      end if;
    end if;
  end loop;

  return v_new;
end;
$function$;

create or replace function private.process_event_missions(
  p_client_id uuid,
  p_event_key text,
  p_habit_category text default null::text
)
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_organization uuid;
begin
  v_organization:=private.resolve_legacy_client_organization_v1(
    p_client_id,null
  );

  return private.process_event_missions_in_org(
    v_organization,
    p_client_id,
    p_event_key,
    p_habit_category
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 5) Achievement engine — explicit tenant variant + legacy wrapper
-- ---------------------------------------------------------------------------

create or replace function private.process_generic_achievements_in_org(
  p_organization_id uuid,
  p_client_id uuid,
  p_trigger_source text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  a record;
  v_metric numeric;
  v_target numeric;
  v_unlock boolean;
  v_new_id uuid;
  v_new_count integer;
  v_pass integer;
  v_result jsonb:='[]'::jsonb;
begin
  for v_pass in 1..5 loop
    v_new_count:=0;

    for a in
      select
        ach.id,ach.rarity,ach.xp_reward,ach.credit_reward,
        r.rule,r.unlocked_title,r.unlocked_description,
        r.unlocked_badge_path
      from public.achievements ach
      join private.achievement_rules r
        on r.achievement_id=ach.id
      where ach.active=true
        and not exists(
          select 1
          from public.client_achievements ca
          where ca.organization_id=p_organization_id
            and ca.client_id=p_client_id
            and ca.achievement_id=ach.id
        )
    loop
      v_metric:=null;
      v_target:=nullif(a.rule->>'target','')::numeric;

      if v_target is null then
        continue;
      end if;

      case a.rule->>'type'
        when 'workout_count' then
          if coalesce(
            (a.rule->>'include_partial')::boolean,
            false
          ) then
            select count(*)::numeric into v_metric
            from public.workout_sessions ws
            where ws.organization_id=p_organization_id
              and ws.client_id=p_client_id
              and ws.status in (
                'completed'::public.workout_session_status,
                'partial'::public.workout_session_status
              );
          else
            select count(*)::numeric into v_metric
            from public.workout_sessions ws
            where ws.organization_id=p_organization_id
              and ws.client_id=p_client_id
              and ws.status='completed'::public.workout_session_status;
          end if;
        when 'total_xp' then
          select coalesce(sum(x.amount),0)::numeric
          into v_metric
          from public.xp_ledger x
          where x.organization_id=p_organization_id
            and x.client_id=p_client_id
            and x.reversed_at is null;
        when 'completed_missions' then
          select count(*)::numeric into v_metric
          from public.client_missions cm
          where cm.organization_id=p_organization_id
            and cm.client_id=p_client_id
            and cm.status='completed'::public.client_mission_status;
        else
          v_metric:=null;
      end case;

      v_unlock:=
        v_metric is not null
        and v_metric>=v_target;

      if v_unlock then
        v_new_id:=null;

        insert into public.client_achievements(
          organization_id,client_id,achievement_id,
          title_snapshot,description_snapshot,rarity_snapshot,
          badge_path_snapshot,xp_reward_snapshot,
          credit_reward_snapshot,trigger_source
        )
        values(
          p_organization_id,p_client_id,a.id,
          a.unlocked_title,a.unlocked_description,a.rarity,
          a.unlocked_badge_path,a.xp_reward,
          a.credit_reward,p_trigger_source
        )
        on conflict do nothing
        returning id into v_new_id;

        if v_new_id is not null then
          v_new_count:=v_new_count+1;

          v_result:=v_result||jsonb_build_array(
            jsonb_build_object(
              'organization_id',p_organization_id,
              'achievement_id',a.id,
              'title',a.unlocked_title,
              'rarity',a.rarity::text
            )
          );

          if a.xp_reward>0 then
            insert into public.xp_ledger(
              organization_id,client_id,pillar,source_type,
              source_id,amount,description
            )
            values(
              p_organization_id,p_client_id,'progress',
              'achievement_unlocked',a.id,a.xp_reward,
              'Logro: '||a.unlocked_title
            )
            on conflict do nothing;
          end if;

          if a.credit_reward>0 then
            insert into public.credit_ledger(
              organization_id,client_id,transaction_type,
              source_type,source_id,amount,description
            )
            values(
              p_organization_id,p_client_id,
              'earned'::public.credit_transaction_type,
              'achievement_unlocked',a.id,a.credit_reward,
              'Logro: '||a.unlocked_title
            )
            on conflict do nothing;
          end if;

          insert into public.notifications(
            user_id,type,title,body,action_url,metadata
          )
          values(
            p_client_id,
            'achievement_unlocked',
            'Logro desbloqueado',
            a.unlocked_title,
            '/progress/achievements',
            jsonb_build_object(
              'organization_id',p_organization_id,
              'achievement_id',a.id,
              'rarity',a.rarity::text
            )
          );
        end if;
      end if;
    end loop;

    exit when v_new_count=0;
  end loop;

  return v_result;
end;
$function$;

create or replace function private.process_generic_achievements(
  p_client_id uuid,
  p_trigger_source text
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
    p_client_id,null
  );

  return private.process_generic_achievements_in_org(
    v_organization,
    p_client_id,
    p_trigger_source
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 6) Client CV state refresh — explicit tenant variant + legacy wrapper
-- ---------------------------------------------------------------------------

create or replace function private.refresh_client_cv_state_in_org(
  p_organization_id uuid,
  p_client_id uuid,
  p_trigger_source text default 'system'::text
)
returns table(
  previous_level integer,
  current_level integer,
  total_xp integer,
  credit_balance integer,
  new_levels integer
)
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_prev integer;
  v_new integer;
  v_eligible integer;
  v_xp integer;
  v_balance integer;
  v_hist uuid;
  v_level record;
  v_new_levels integer:=0;
begin
  if not exists(
    select 1
    from public.clients c
    join public.profiles p
      on p.id=c.user_id
    where c.organization_id=p_organization_id
      and c.user_id=p_client_id
      and c.status<>'archived'::public.client_status
      and p.role='client'::public.app_role
  ) then
    return;
  end if;

  insert into public.client_cv_state(
    organization_id,client_id,current_level,total_xp,credit_balance
  )
  values(
    p_organization_id,p_client_id,1,0,0
  )
  on conflict(client_id) do nothing;

  -- Until E2B changes client_cv_state PK, fail safely if another tenant already
  -- owns the legacy single-row identity.
  if not exists(
    select 1
    from public.client_cv_state s
    where s.organization_id=p_organization_id
      and s.client_id=p_client_id
  ) then
    raise exception 'CV12 state identity cutover pending for multi-organization client';
  end if;

  insert into public.client_level_history(
    organization_id,client_id,level_number,trigger_source
  )
  values(
    p_organization_id,p_client_id,1,'initial'
  )
  on conflict(
    organization_id,client_id,level_number
  ) do nothing;

  select s.current_level into v_prev
  from public.client_cv_state s
  where s.organization_id=p_organization_id
    and s.client_id=p_client_id
  for update;

  select greatest(
    0,
    coalesce(
      sum(x.amount) filter(
        where x.reversed_at is null
      ),
      0
    )::integer
  )
  into v_xp
  from public.xp_ledger x
  where x.organization_id=p_organization_id
    and x.client_id=p_client_id;

  select coalesce(
    sum(
      case c.transaction_type
        when 'earned'::public.credit_transaction_type
          then abs(c.amount)
        when 'spent'::public.credit_transaction_type
          then -abs(c.amount)
        when 'adjustment'::public.credit_transaction_type
          then c.amount
        when 'reversal'::public.credit_transaction_type
          then c.amount
        else 0
      end
    ),
    0
  )::integer
  into v_balance
  from public.credit_ledger c
  where c.organization_id=p_organization_id
    and c.client_id=p_client_id;

  select coalesce(max(l.level_number),1)
  into v_eligible
  from public.cv_levels l
  where l.xp_required_total<=v_xp
    and private.level_requirements_met_in_org(
      p_organization_id,p_client_id,l.level_number
    );

  v_new:=greatest(
    v_prev,
    coalesce(v_eligible,1)
  );

  if v_new>v_prev then
    for v_level in
      select l.level_number,l.reward_credits
      from public.cv_levels l
      where l.level_number>v_prev
        and l.level_number<=v_new
      order by l.level_number
    loop
      v_hist:=null;

      insert into public.client_level_history(
        organization_id,client_id,level_number,trigger_source
      )
      values(
        p_organization_id,p_client_id,
        v_level.level_number,p_trigger_source
      )
      on conflict(
        organization_id,client_id,level_number
      ) do nothing
      returning id into v_hist;

      if v_hist is not null then
        v_new_levels:=v_new_levels+1;

        if v_level.reward_credits>0 then
          insert into public.credit_ledger(
            organization_id,client_id,transaction_type,
            source_type,source_id,amount,description
          )
          values(
            p_organization_id,
            p_client_id,
            'earned'::public.credit_transaction_type,
            'level_up',
            v_hist,
            v_level.reward_credits,
            'Recompensa por alcanzar Nivel '||
              v_level.level_number
          )
          on conflict do nothing;
        end if;
      end if;
    end loop;

    select coalesce(
      sum(
        case c.transaction_type
          when 'earned'::public.credit_transaction_type
            then abs(c.amount)
          when 'spent'::public.credit_transaction_type
            then -abs(c.amount)
          when 'adjustment'::public.credit_transaction_type
            then c.amount
          when 'reversal'::public.credit_transaction_type
            then c.amount
          else 0
        end
      ),
      0
    )::integer
    into v_balance
    from public.credit_ledger c
    where c.organization_id=p_organization_id
      and c.client_id=p_client_id;
  end if;

  update public.client_cv_state s
  set current_level=v_new,
      total_xp=v_xp,
      credit_balance=v_balance,
      current_cv_score=(
        select cs.cv_score
        from public.cv_score_snapshots cs
        where cs.organization_id=p_organization_id
          and cs.client_id=p_client_id
        order by cs.calculated_at desc
        limit 1
      ),
      dynamic_state=coalesce(
        (
          select cs.dynamic_state
          from public.cv_score_snapshots cs
          where cs.organization_id=p_organization_id
            and cs.client_id=p_client_id
          order by cs.calculated_at desc
          limit 1
        ),
        s.dynamic_state
      ),
      updated_at=now()
  where s.organization_id=p_organization_id
    and s.client_id=p_client_id;

  return query
  select v_prev,v_new,v_xp,v_balance,v_new_levels;
end;
$function$;

create or replace function private.refresh_client_cv_state(
  p_client_id uuid,
  p_trigger_source text default 'system'::text
)
returns table(
  previous_level integer,
  current_level integer,
  total_xp integer,
  credit_balance integer,
  new_levels integer
)
language plpgsql
security definer
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
  from private.refresh_client_cv_state_in_org(
    v_organization,
    p_client_id,
    p_trigger_source
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 7) Automatic CV state refresh triggers — preserve tenant from row context
-- ---------------------------------------------------------------------------

create or replace function private.cv_state_from_xp_ledger()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_org uuid:=coalesce(new.organization_id,old.organization_id);
  v_client uuid:=coalesce(new.client_id,old.client_id);
begin
  perform private.refresh_client_cv_state_in_org(
    v_org,v_client,'xp_change'
  );
  return coalesce(new,old);
end;
$function$;

create or replace function private.cv_state_from_credit_ledger()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_org uuid:=coalesce(new.organization_id,old.organization_id);
  v_client uuid:=coalesce(new.client_id,old.client_id);
begin
  perform private.refresh_client_cv_state_in_org(
    v_org,v_client,'credit_change'
  );
  return coalesce(new,old);
end;
$function$;

create or replace function private.cv_state_from_score()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  perform private.refresh_client_cv_state_in_org(
    new.organization_id,new.client_id,'cv_score'
  );
  return new;
end;
$function$;

create or replace function private.cv_state_from_client_profile()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  perform private.refresh_client_cv_state_in_org(
    new.organization_id,new.client_id,'onboarding'
  );
  return new;
end;
$function$;

comment on function private.award_cv12_action_in_org(
  uuid,uuid,text,uuid,date,text,integer
) is
  'F1.M1.S5 E2A tenant-explicit CV12 reward processor.';

comment on function private.refresh_client_cv_state_in_org(
  uuid,uuid,text
) is
  'F1.M1.S5 E2A tenant-explicit CV12 state refresh. client_cv_state PK cutover follows in E2B.';
