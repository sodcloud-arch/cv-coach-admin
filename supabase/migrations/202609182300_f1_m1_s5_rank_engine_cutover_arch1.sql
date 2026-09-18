-- ARCH-1.0 · F1.M1.S5 Wave F2A — Competitive Rank engine tenant cutover
-- Makes Rank state/calculation/tutorial/transitions Organization-aware and
-- changes the dangerous client-global identities in the same atomic migration.

-- ---------------------------------------------------------------------------
-- 1) Tenant-scoped identities
-- ---------------------------------------------------------------------------

alter table public.client_competitive_rank_v61
  drop constraint if exists client_competitive_rank_v61_pkey;
alter table public.client_competitive_rank_v61
  add constraint client_competitive_rank_v61_pkey
  primary key (organization_id,client_id);

alter table public.client_rank_history
  drop constraint if exists client_rank_history_client_id_class_id_key;
alter table public.client_rank_history
  add constraint client_rank_history_org_client_class_key
  unique (organization_id,client_id,class_id);

alter table public.cv_rank_rating_ledger_v61
  drop constraint if exists cv_rank_rating_ledger_v61_client_id_event_key_key;
alter table public.cv_rank_rating_ledger_v61
  add constraint cv_rank_rating_ledger_v61_org_client_event_key
  unique (organization_id,client_id,event_key);

alter table public.cv_rank_weekly_snapshots_v61
  drop constraint if exists cv_rank_weekly_snapshots_v61_client_id_week_start_key;
alter table public.cv_rank_weekly_snapshots_v61
  add constraint cv_rank_weekly_snapshots_v61_org_client_week_start_key
  unique (organization_id,client_id,week_start);

alter table public.cv_rank_tutorial_ack_v61
  drop constraint if exists cv_rank_tutorial_ack_v61_pkey;
alter table public.cv_rank_tutorial_ack_v61
  add constraint cv_rank_tutorial_ack_v61_pkey
  primary key (organization_id,client_id,step_key);

alter table public.cv_trophies_v61
  drop constraint if exists cv_trophies_v61_client_id_trophy_key_key;
alter table public.cv_trophies_v61
  add constraint cv_trophies_v61_org_client_trophy_key
  unique (organization_id,client_id,trophy_key);

-- ---------------------------------------------------------------------------
-- 2) Canonical authorization
-- ---------------------------------------------------------------------------

create or replace function private.cv_rank_authorized_client_in_org_v61(
  p_organization uuid,
  p_actor uuid,
  p_client uuid
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
      join public.profiles p on p.id=p_actor and p.status::text='active'
      where c.organization_id=p_organization
        and c.user_id=p_client
        and c.status<>'archived'::public.client_status
        and (
          p_actor=p_client
          or private.actor_can_manage_client_in_org_v1(
            p_actor,p_organization,p_client
          )
        )
    ),
    false
  )
$function$;

create or replace function private.cv_rank_authorized_client_v61(
  p_actor uuid,
  p_client uuid
)
returns boolean
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_org uuid;
begin
  if p_actor=p_client then
    v_org:=private.resolve_legacy_client_organization_v1(p_client,null);
  else
    v_org:=private.resolve_legacy_professional_organization_v1(
      p_actor,p_client
    );
  end if;

  return private.cv_rank_authorized_client_in_org_v61(
    v_org,p_actor,p_client
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 3) Discipline calculation
-- ---------------------------------------------------------------------------

create or replace function private.calculate_discipline_in_org_v61(
  p_organization uuid,
  p_client uuid,
  p_week_start date
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_week date:=date_trunc('week',p_week_start)::date;
  v_end date:=v_week+6;
  v_program uuid;
  v_training_target numeric:=0;
  v_training_done numeric:=0;
  v_training numeric;
  v_nut_start date;
  v_nut_end date;
  v_nut_days numeric:=0;
  v_nut_sum numeric:=0;
  v_nutrition numeric;
  v_h_expected numeric:=0;
  v_h_done numeric:=0;
  v_hydration numeric;
  v_m_expected numeric:=0;
  v_m_done numeric:=0;
  v_movement numeric;
  v_s_expected numeric:=0;
  v_s_done numeric:=0;
  v_sleep numeric;
  v_check numeric;
  v_recovery numeric;
  v_weight numeric:=0;
  v_total numeric:=0;
begin
  if not exists(
    select 1 from public.clients c
    where c.organization_id=p_organization
      and c.user_id=p_client
      and c.status<>'archived'::public.client_status
  ) then
    raise exception 'rank discipline client is not active in organization';
  end if;

  select p.id into v_program
  from public.programs p
  where p.organization_id=p_organization
    and p.client_id=p_client
    and p.status::text='active'
    and p.start_date<=v_end
    and (p.end_date is null or p.end_date>=v_week)
  order by coalesce(p.published_at,p.updated_at) desc
  limit 1;

  if v_program is not null then
    select count(*) into v_training_target
    from public.program_days d
    where d.organization_id=p_organization
      and d.program_id=v_program;

    if v_training_target>0 then
      select coalesce(
        sum(
          least(
            1,
            greatest(
              0,
              coalesce(
                ws.completion_pct,
                case when ws.status::text='completed' then 100 else 0 end
              )/100.0
            )
          )
        ),
        0
      )
      into v_training_done
      from public.workout_sessions ws
      where ws.organization_id=p_organization
        and ws.client_id=p_client
        and ws.program_id=v_program
        and coalesce(
          (ws.finished_at at time zone 'America/Santiago')::date,
          (ws.started_at at time zone 'America/Santiago')::date
        ) between v_week and v_end
        and ws.status::text in('completed','partial');

      v_training:=least(100,100*v_training_done/v_training_target);
      v_weight:=v_weight+35;
      v_total:=v_total+v_training*35;
    end if;
  end if;

  select
    greatest(nt.start_date,v_week),
    least(coalesce(nt.end_date,v_end),v_end)
  into v_nut_start,v_nut_end
  from public.nutrition_targets nt
  where nt.organization_id=p_organization
    and nt.client_id=p_client
    and nt.active=true
    and nt.start_date<=v_end
    and (nt.end_date is null or nt.end_date>=v_week)
  order by nt.start_date desc
  limit 1;

  if v_nut_start is not null and v_nut_end>=v_nut_start then
    v_nut_days:=(v_nut_end-v_nut_start)+1;

    select coalesce(sum(least(100,greatest(0,n.adherence_pct))),0)
    into v_nut_sum
    from public.nutrition_daily_logs n
    where n.organization_id=p_organization
      and n.client_id=p_client
      and n.log_date between v_nut_start and v_nut_end;

    v_nutrition:=least(100,v_nut_sum/greatest(1,v_nut_days));
    v_weight:=v_weight+25;
    v_total:=v_total+v_nutrition*25;
  end if;

  select
    coalesce(
      sum(
        case
          when ch.frequency_type::text='daily' then 7
          else greatest(1,least(7,ch.frequency_target))
        end
      ),
      0
    ),
    coalesce(
      sum(
        (
          select count(*)
          from public.habit_logs hl
          where hl.organization_id=p_organization
            and hl.client_habit_id=ch.id
            and hl.client_id=p_client
            and hl.log_date between v_week and v_end
            and hl.completed=true
        )
      ),
      0
    )
  into v_h_expected,v_h_done
  from public.client_habits ch
  join public.habit_definitions hd on hd.id=ch.habit_id
  where ch.organization_id=p_organization
    and ch.client_id=p_client
    and ch.active=true
    and hd.category='hydration'
    and ch.start_date<=v_end
    and (ch.end_date is null or ch.end_date>=v_week);

  if v_h_expected>0 then
    v_hydration:=least(100,100*v_h_done/v_h_expected);
    v_weight:=v_weight+15;
    v_total:=v_total+v_hydration*15;
  end if;

  select
    coalesce(
      sum(
        case
          when ch.frequency_type::text='daily' then 7
          else greatest(1,least(7,ch.frequency_target))
        end
      ),
      0
    ),
    coalesce(
      sum(
        (
          select count(*)
          from public.habit_logs hl
          where hl.organization_id=p_organization
            and hl.client_habit_id=ch.id
            and hl.client_id=p_client
            and hl.log_date between v_week and v_end
            and hl.completed=true
        )
      ),
      0
    )
  into v_m_expected,v_m_done
  from public.client_habits ch
  join public.habit_definitions hd on hd.id=ch.habit_id
  where ch.organization_id=p_organization
    and ch.client_id=p_client
    and ch.active=true
    and hd.category in('cardio','steps')
    and ch.start_date<=v_end
    and (ch.end_date is null or ch.end_date>=v_week);

  if v_m_expected>0 then
    v_movement:=least(100,100*v_m_done/v_m_expected);
    v_weight:=v_weight+15;
    v_total:=v_total+v_movement*15;
  end if;

  select
    coalesce(
      sum(
        case
          when ch.frequency_type::text='daily' then 7
          else greatest(1,least(7,ch.frequency_target))
        end
      ),
      0
    ),
    coalesce(
      sum(
        (
          select count(*)
          from public.habit_logs hl
          where hl.organization_id=p_organization
            and hl.client_habit_id=ch.id
            and hl.client_id=p_client
            and hl.log_date between v_week and v_end
            and hl.completed=true
        )
      ),
      0
    )
  into v_s_expected,v_s_done
  from public.client_habits ch
  join public.habit_definitions hd on hd.id=ch.habit_id
  where ch.organization_id=p_organization
    and ch.client_id=p_client
    and ch.active=true
    and hd.category='sleep'
    and ch.start_date<=v_end
    and (ch.end_date is null or ch.end_date>=v_week);

  if v_s_expected>0 then
    v_sleep:=least(100,100*v_s_done/v_s_expected);
  end if;

  v_check:=case
    when exists(
      select 1
      from public.weekly_checkins w
      where w.organization_id=p_organization
        and w.client_id=p_client
        and w.week_start=v_week
        and w.submitted_at is not null
    ) then 100
    else 0
  end;

  v_recovery:=case
    when v_sleep is null then v_check
    else (v_sleep+v_check)/2
  end;

  v_weight:=v_weight+10;
  v_total:=v_total+v_recovery*10;

  return jsonb_build_object(
    'organization_id',p_organization,
    'week_start',v_week,
    'week_end',v_end,
    'training_score',v_training,
    'nutrition_score',v_nutrition,
    'hydration_score',v_hydration,
    'movement_score',v_movement,
    'recovery_score',v_recovery,
    'active_weight',v_weight,
    'discipline_score',round(
      case when v_weight=0 then 0 else v_total/v_weight end,
      1
    ),
    'training_target',v_training_target,
    'training_done',round(v_training_done,2),
    'nutrition_days',v_nut_days,
    'hydration_expected',v_h_expected,
    'hydration_done',v_h_done,
    'movement_expected',v_m_expected,
    'movement_done',v_m_done,
    'sleep_expected',v_s_expected,
    'sleep_done',v_s_done,
    'checkin_done',v_check=100
  );
end;
$function$;

create or replace function private.calculate_discipline_v61(
  p_client uuid,
  p_week_start date
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_org uuid;
begin
  v_org:=private.resolve_legacy_client_organization_v1(p_client,null);
  return private.calculate_discipline_in_org_v61(
    v_org,p_client,p_week_start
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 4) Rank rollups
-- ---------------------------------------------------------------------------

create or replace function private.refresh_rank_rollups_in_org_v61(
  p_organization uuid,
  p_client uuid
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v4 numeric;
  v12 numeric;
begin
  select round(avg(discipline_score),1)
  into v4
  from (
    select discipline_score
    from public.cv_rank_weekly_snapshots_v61
    where organization_id=p_organization
      and client_id=p_client
    order by week_start desc
    limit 4
  ) x;

  select round(avg(discipline_score),1)
  into v12
  from (
    select discipline_score
    from public.cv_rank_weekly_snapshots_v61
    where organization_id=p_organization
      and client_id=p_client
    order by week_start desc
    limit 12
  ) x;

  update public.client_competitive_rank_v61
  set rolling_4_week_score=v4,
      rolling_12_week_score=v12,
      updated_at=now()
  where organization_id=p_organization
    and client_id=p_client;
end;
$function$;

create or replace function private.refresh_rank_rollups_v61(
  p_client uuid
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_org uuid;
begin
  v_org:=private.resolve_legacy_client_organization_v1(p_client,null);
  perform private.refresh_rank_rollups_in_org_v61(v_org,p_client);
end;
$function$;

-- ---------------------------------------------------------------------------
-- 5) Tutorial
-- ---------------------------------------------------------------------------

create or replace function private.cv_tutorial_status_in_org_v61(
  p_organization uuid,
  p_client uuid
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_app boolean;
  v_plan boolean;
  v_nut boolean;
  v_log boolean;
begin
  v_app:=exists(
    select 1
    from public.cv_rank_tutorial_ack_v61
    where organization_id=p_organization
      and client_id=p_client
      and step_key='app_tour'
  );

  v_plan:=exists(
    select 1
    from public.programs p
    where p.organization_id=p_organization
      and p.client_id=p_client
      and p.status::text='active'
  );

  v_nut:=
    exists(
      select 1
      from public.nutrition_targets n
      where n.organization_id=p_organization
        and n.client_id=p_client
        and n.active=true
    )
    or exists(
      select 1
      from public.client_habits h
      where h.organization_id=p_organization
        and h.client_id=p_client
        and h.active=true
    );

  v_log:=
    exists(
      select 1
      from public.workout_sessions w
      where w.organization_id=p_organization
        and w.client_id=p_client
        and w.status::text in('completed','partial')
    )
    or exists(
      select 1
      from public.habit_logs h
      where h.organization_id=p_organization
        and h.client_id=p_client
    )
    or exists(
      select 1
      from public.nutrition_daily_logs n
      where n.organization_id=p_organization
        and n.client_id=p_client
    );

  return jsonb_build_object(
    'organization_id',p_organization,
    'completed',v_app and v_plan and v_nut and v_log,
    'steps',jsonb_build_object(
      'app_tour',v_app,
      'training_plan',v_plan,
      'nutrition_habits',v_nut,
      'first_log',v_log
    )
  );
end;
$function$;

create or replace function private.cv_tutorial_status_v61(
  p_client uuid
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_org uuid;
begin
  v_org:=private.resolve_legacy_client_organization_v1(p_client,null);
  return private.cv_tutorial_status_in_org_v61(v_org,p_client);
end;
$function$;

-- ---------------------------------------------------------------------------
-- 6) Rank bootstrap now follows canonical Client tenancy
-- ---------------------------------------------------------------------------

create or replace function private.bootstrap_competitive_rank_v61()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  r record;
begin
  if new.role::text='client' then
    for r in
      select c.organization_id
      from public.clients c
      where c.user_id=new.id
        and c.status<>'archived'::public.client_status
    loop
      insert into public.client_competitive_rank_v61(
        organization_id,client_id,competitive_alias
      )
      values(
        r.organization_id,
        new.id,
        trim(
          coalesce(new.first_name,'Cliente')
          ||case
              when nullif(new.last_name,'') is null then ''
              else ' '||left(new.last_name,1)||'.'
            end
        )
      )
      on conflict(organization_id,client_id) do nothing;
    end loop;
  end if;
  return new;
end;
$function$;

create or replace function private.bootstrap_competitive_rank_from_client_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if new.user_id is not null
     and new.status<>'archived'::public.client_status then
    insert into public.client_competitive_rank_v61(
      organization_id,client_id,competitive_alias
    )
    values(
      new.organization_id,
      new.user_id,
      private.cv_alias_v61(new.user_id)
    )
    on conflict(organization_id,client_id) do nothing;
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_bootstrap_competitive_rank_client_v1
  on public.clients;

create trigger trg_bootstrap_competitive_rank_client_v1
after insert or update of user_id,status
on public.clients
for each row execute function private.bootstrap_competitive_rank_from_client_v1();

-- Ensure existing canonical Clients have tenant-local rank state.
insert into public.client_competitive_rank_v61(
  organization_id,client_id,competitive_alias
)
select
  c.organization_id,
  c.user_id,
  private.cv_alias_v61(c.user_id)
from public.clients c
where c.user_id is not null
  and c.status<>'archived'::public.client_status
on conflict(organization_id,client_id) do nothing;

-- ---------------------------------------------------------------------------
-- 7) Level-history -> rank-history tracking
-- ---------------------------------------------------------------------------

create or replace function private.track_cv_rank_from_level_history()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_rank public.cv_classes%rowtype;
  v_rank_history_id uuid;
begin
  select * into v_rank
  from public.cv_classes c
  where c.rank_key is not null
    and c.min_level=new.level_number
  order by c.order_index
  limit 1;

  if not found then
    return new;
  end if;

  insert into public.client_rank_history(
    organization_id,client_id,class_id,rank_key,
    rank_name_snapshot,level_number,reached_at,trigger_source
  )
  values(
    new.organization_id,new.client_id,v_rank.id,v_rank.rank_key,
    v_rank.name,new.level_number,new.reached_at,new.trigger_source
  )
  on conflict(organization_id,client_id,class_id) do nothing
  returning id into v_rank_history_id;

  if v_rank_history_id is not null and v_rank.order_index>1 then
    insert into public.notifications(
      user_id,type,title,body,action_url,metadata
    )
    values(
      new.client_id,
      'rank_up',
      '¡Nuevo rango!',
      'Alcanzaste Rango '||v_rank.name||'.',
      '/',
      jsonb_build_object(
        'organization_id',new.organization_id,
        'rank_key',v_rank.rank_key,
        'rank_name',v_rank.name,
        'level_number',new.level_number,
        'rank_history_id',v_rank_history_id
      )
    );
  end if;

  return new;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 8) Weekly competitive engine
-- ---------------------------------------------------------------------------

create or replace function private.process_rank_week_in_org_v61(
  p_organization uuid,
  p_client uuid,
  p_week_start date
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_profile public.client_competitive_rank_v61%rowtype;
  v_calc jsonb;
  v_score numeric;
  v_rule public.cv_rank_rules_v61%rowtype;
  v_change numeric:=0;
  v_after numeric;
  v_level_target integer;
  v_level_after integer;
  v_rank_after text;
  v_rank_before text;
  v_pause boolean:=false;
  v_perfect boolean:=false;
  v_week date:=date_trunc('week',p_week_start)::date;
  v_event text;
  v_avg6 numeric;
  v_min6 numeric;
  v_perf6 integer;
  v_count6 integer;
  v_avg4 numeric;
  v_old_order integer;
  v_new_order integer;
begin
  select * into v_profile
  from public.client_competitive_rank_v61
  where organization_id=p_organization
    and client_id=p_client
  for update;

  if not found or not v_profile.tutorial_completed then
    return jsonb_build_object(
      'processed',false,
      'organization_id',p_organization,
      'reason','tutorial'
    );
  end if;

  v_event:=
    'weekly:'||p_organization::text||':'||
    p_client::text||':'||v_week::text;

  if exists(
    select 1
    from public.cv_rank_rating_ledger_v61
    where organization_id=p_organization
      and client_id=p_client
      and event_key=v_event
  ) then
    return jsonb_build_object(
      'processed',false,
      'organization_id',p_organization,
      'reason','idempotent'
    );
  end if;

  v_calc:=private.calculate_discipline_in_org_v61(
    p_organization,p_client,v_week
  );
  v_score:=(v_calc->>'discipline_score')::numeric;

  v_rank_before:=coalesce(
    v_profile.current_rank_key,
    private.cv_rank_key_for_level_v61(
      greatest(1,v_profile.current_level)
    )
  );

  select * into v_rule
  from public.cv_rank_rules_v61
  where rank_key=v_rank_before;

  v_pause:=exists(
    select 1
    from public.cv_rank_pause_periods_v61 pp
    where pp.organization_id=p_organization
      and pp.client_id=p_client
      and pp.starts_on<=v_week+6
      and pp.ends_on>=v_week
  );

  if v_pause then
    v_change:=0;
  elsif v_score<v_rule.maintenance_pct then
    v_change:=-least(
      v_rule.loss_cap,
      (v_rule.maintenance_pct-v_score)*v_rule.loss_factor
    );
  elsif v_score>=v_rule.progress_pct then
    v_change:=least(
      v_rule.gain_cap,
      v_rule.gain_base+
      (v_score-v_rule.progress_pct)*v_rule.gain_factor
    );
  else
    v_change:=0;
  end if;

  v_after:=greatest(0,v_profile.cv_rating+v_change);
  v_perfect:=
    v_score>=95
    and coalesce((v_calc->>'training_score')::numeric,100)>=90
    and coalesce((v_calc->>'nutrition_score')::numeric,100)>=90
    and coalesce((v_calc->>'hydration_score')::numeric,100)>=90
    and coalesce((v_calc->>'movement_score')::numeric,100)>=90
    and coalesce((v_calc->>'recovery_score')::numeric,100)>=90;

  insert into public.cv_rank_rating_ledger_v61(
    organization_id,client_id,event_key,event_type,amount,
    rating_before,rating_after,week_start,metadata
  )
  values(
    p_organization,p_client,v_event,'weekly_close',v_change,
    v_profile.cv_rating,v_after,v_week,
    jsonb_build_object(
      'organization_id',p_organization,
      'discipline_score',v_score,
      'pause',v_pause
    )
  );

  insert into public.cv_rank_weekly_snapshots_v61(
    organization_id,client_id,week_start,week_end,
    training_score,nutrition_score,hydration_score,movement_score,
    recovery_score,discipline_score,active_weight,rating_before,
    rating_change,rating_after,level_before,level_after,
    rank_before,rank_after,perfect_week,protected_pause,details
  )
  values(
    p_organization,p_client,v_week,v_week+6,
    (v_calc->>'training_score')::numeric,
    (v_calc->>'nutrition_score')::numeric,
    (v_calc->>'hydration_score')::numeric,
    (v_calc->>'movement_score')::numeric,
    (v_calc->>'recovery_score')::numeric,
    v_score,
    (v_calc->>'active_weight')::numeric,
    v_profile.cv_rating,v_change,v_after,
    v_profile.current_level,v_profile.current_level,
    v_rank_before,v_rank_before,v_perfect,v_pause,v_calc
  )
  on conflict(organization_id,client_id,week_start) do update set
    week_end=excluded.week_end,
    training_score=excluded.training_score,
    nutrition_score=excluded.nutrition_score,
    hydration_score=excluded.hydration_score,
    movement_score=excluded.movement_score,
    recovery_score=excluded.recovery_score,
    discipline_score=excluded.discipline_score,
    active_weight=excluded.active_weight,
    rating_before=excluded.rating_before,
    rating_change=excluded.rating_change,
    rating_after=excluded.rating_after,
    protected_pause=excluded.protected_pause,
    details=excluded.details,
    updated_at=now();

  select
    avg(discipline_score),
    min(discipline_score),
    count(*) filter(where perfect_week),
    count(*)
  into v_avg6,v_min6,v_perf6,v_count6
  from (
    select discipline_score,perfect_week
    from public.cv_rank_weekly_snapshots_v61
    where organization_id=p_organization
      and client_id=p_client
    order by week_start desc
    limit 6
  ) s;

  select avg(discipline_score)
  into v_avg4
  from (
    select discipline_score
    from public.cv_rank_weekly_snapshots_v61
    where organization_id=p_organization
      and client_id=p_client
    order by week_start desc
    limit 4
  ) s;

  v_level_target:=private.cv_level_for_rating_v61(v_after,25);

  if v_profile.current_level=26 then
    if v_after>=20500 and coalesce(v_avg4,0)>=93 then
      v_level_target:=26;
    else
      v_level_target:=25;
    end if;
  elsif v_after>=20500
        and v_count6>=6
        and v_avg6>=95
        and v_min6>=90
        and v_perf6>=4 then
    v_level_target:=26;
  end if;

  if v_level_target>v_profile.current_level then
    v_level_after:=least(v_profile.current_level+1,v_level_target);
  elsif v_level_target<v_profile.current_level then
    v_level_after:=greatest(v_profile.current_level-1,v_level_target);
  else
    v_level_after:=v_profile.current_level;
  end if;

  v_rank_after:=private.cv_rank_key_for_level_v61(v_level_after);

  select order_index into v_old_order
  from public.cv_rank_rules_v61
  where rank_key=v_rank_before;

  select order_index into v_new_order
  from public.cv_rank_rules_v61
  where rank_key=v_rank_after;

  if v_new_order<v_old_order
     and v_profile.rank_protected_until>now() then
    v_level_after:=v_profile.current_level;
    v_rank_after:=v_rank_before;
    v_new_order:=v_old_order;
  end if;

  update public.cv_rank_weekly_snapshots_v61
  set level_after=v_level_after,
      rank_after=v_rank_after
  where organization_id=p_organization
    and client_id=p_client
    and week_start=v_week;

  update public.client_competitive_rank_v61
  set cv_rating=v_after,
      rating_peak=greatest(rating_peak,v_after),
      current_level=v_level_after,
      current_rank_key=v_rank_after,
      highest_level=greatest(highest_level,v_level_after),
      highest_rank_key=case
        when v_level_after>=highest_level then v_rank_after
        else highest_rank_key
      end,
      last_discipline_score=v_score,
      last_week_closed=v_week,
      rank_protected_until=case
        when v_new_order>v_old_order then now()+interval '7 days'
        else rank_protected_until
      end,
      legend_since=case
        when v_level_after=26 and current_level<>26 then now()
        when v_level_after<>26 then null
        else legend_since
      end,
      updated_at=now()
  where organization_id=p_organization
    and client_id=p_client;

  if v_level_after<>v_profile.current_level then
    insert into public.cv_rank_transitions_v61(
      organization_id,client_id,direction,from_level,to_level,
      from_rank_key,to_rank_key,week_start,metadata
    )
    values(
      p_organization,
      p_client,
      case
        when v_level_after>v_profile.current_level then
          case
            when v_new_order>v_old_order then
              case
                when v_level_after=26 then 'legend_unlock'
                else 'rank_up'
              end
            else 'level_up'
          end
        else
          case
            when v_new_order<v_old_order then 'rank_down'
            else 'level_down'
          end
      end,
      v_profile.current_level,
      v_level_after,
      v_rank_before,
      v_rank_after,
      v_week,
      jsonb_build_object(
        'organization_id',p_organization,
        'rating_change',v_change,
        'discipline_score',v_score
      )
    );

    insert into public.notifications(
      user_id,type,title,body,action_url,metadata
    )
    values(
      p_client,
      case
        when v_level_after>v_profile.current_level then
          case
            when v_new_order>v_old_order then 'rank_up'
            else 'level_up'
          end
        else 'rank_down'
      end,
      case
        when v_level_after>v_profile.current_level then
          case
            when v_new_order>v_old_order then '¡Nuevo rango!'
            else '¡Subiste de nivel!'
          end
        else 'Actualización de rango'
      end,
      case
        when v_new_order>v_old_order then
          'Alcanzaste '||
          (select rank_name
           from public.cv_rank_rules_v61
           where rank_key=v_rank_after)||'.'
        when v_new_order<v_old_order then
          'Tu rango actual cambió. Revisa tu camino de recuperación.'
        else
          'Tu nivel competitivo ahora es '||v_level_after::text||'.'
      end,
      '/',
      jsonb_build_object(
        'organization_id',p_organization,
        'v','61',
        'from_level',v_profile.current_level,
        'to_level',v_level_after,
        'rank_key',v_rank_after
      )
    );
  end if;

  perform private.refresh_rank_rollups_in_org_v61(
    p_organization,p_client
  );

  insert into public.cv_season_weekly_points_v61(
    organization_id,season_id,client_id,week_start,
    discipline_score,bonus_points,points
  )
  select
    p_organization,
    s.id,
    p_client,
    v_week,
    v_score,
    case when v_perfect then 5 else 0 end,
    v_score+case when v_perfect then 5 else 0 end
  from public.cv_seasons_v61 s
  where s.organization_id=p_organization
    and s.status='active'
    and v_week between s.starts_on and s.ends_on
  on conflict(season_id,client_id,week_start) do update set
    organization_id=excluded.organization_id,
    discipline_score=excluded.discipline_score,
    bonus_points=excluded.bonus_points,
    points=excluded.points,
    updated_at=now();

  return jsonb_build_object(
    'processed',true,
    'organization_id',p_organization,
    'week_start',v_week,
    'discipline_score',v_score,
    'rating_change',v_change,
    'rating_after',v_after,
    'level_after',v_level_after,
    'rank_after',v_rank_after,
    'perfect_week',v_perfect
  );
end;
$function$;

create or replace function private.process_rank_week_v61(
  p_client uuid,
  p_week_start date
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_org uuid;
begin
  v_org:=private.resolve_legacy_client_organization_v1(p_client,null);
  return private.process_rank_week_in_org_v61(
    v_org,p_client,p_week_start
  );
end;
$function$;

create or replace function public.process_due_rank_weeks_v61()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  r record;
  v_week date:=(
    date_trunc('week',now() at time zone 'America/Santiago')::date-7
  );
  v_count integer:=0;
begin
  for r in
    select organization_id,client_id
    from public.client_competitive_rank_v61
    where tutorial_completed=true
  loop
    perform private.process_rank_week_in_org_v61(
      r.organization_id,r.client_id,v_week
    );
    v_count:=v_count+1;
  end loop;

  return jsonb_build_object(
    'week_start',v_week,
    'clients_checked',v_count
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 9) Public tutorial APIs
-- ---------------------------------------------------------------------------

create or replace function public.ack_rank_tutorial_v61(
  p_actor_id uuid,
  p_step_key text
)
returns jsonb
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
  if p_step_key<>'app_tour' then
    raise exception 'unsupported tutorial step';
  end if;

  v_org:=private.resolve_legacy_client_organization_v1(
    p_actor_id,null
  );

  if not private.cv_rank_authorized_client_in_org_v61(
    v_org,p_actor_id,p_actor_id
  ) then
    raise exception 'not authorized';
  end if;

  insert into public.cv_rank_tutorial_ack_v61(
    organization_id,client_id,step_key
  )
  values(v_org,p_actor_id,p_step_key)
  on conflict(organization_id,client_id,step_key) do nothing;

  return public.sync_rank_tutorial_v61(p_actor_id);
end;
$function$;

create or replace function public.sync_rank_tutorial_v61(
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_org uuid;
  v_profile public.client_competitive_rank_v61%rowtype;
  v_status jsonb;
  v_done boolean;
begin
  if auth.uid() is not null and auth.uid()<>p_actor_id then
    raise exception 'actor mismatch';
  end if;

  v_org:=private.resolve_legacy_client_organization_v1(
    p_actor_id,null
  );

  if not private.cv_rank_authorized_client_in_org_v61(
    v_org,p_actor_id,p_actor_id
  ) then
    raise exception 'not authorized';
  end if;

  insert into public.client_competitive_rank_v61(
    organization_id,client_id,competitive_alias
  )
  values(
    v_org,p_actor_id,private.cv_alias_v61(p_actor_id)
  )
  on conflict(organization_id,client_id) do nothing;

  select * into v_profile
  from public.client_competitive_rank_v61
  where organization_id=v_org
    and client_id=p_actor_id
  for update;

  v_status:=private.cv_tutorial_status_in_org_v61(
    v_org,p_actor_id
  );
  v_done:=(v_status->>'completed')::boolean;

  if v_done and not v_profile.tutorial_completed then
    update public.client_competitive_rank_v61
    set tutorial_completed=true,
        tutorial_completed_at=now(),
        current_level=1,
        current_rank_key='bronze',
        highest_level=greatest(highest_level,1),
        highest_rank_key='bronze',
        updated_at=now()
    where organization_id=v_org
      and client_id=p_actor_id;

    insert into public.cv_rank_transitions_v61(
      organization_id,client_id,direction,to_level,to_rank_key,metadata
    )
    values(
      v_org,p_actor_id,'tutorial_unlock',1,'bronze',
      jsonb_build_object(
        'organization_id',v_org,
        'source','tutorial_v61'
      )
    );

    insert into public.notifications(
      user_id,type,title,body,action_url,metadata
    )
    values(
      p_actor_id,
      'rank_up',
      'Insignia Bronce desbloqueada',
      'Completaste tu iniciación. Tu camino competitivo comienza ahora.',
      '/',
      jsonb_build_object(
        'organization_id',v_org,
        'rank_key','bronze',
        'level',1,
        'v','61'
      )
    );
  end if;

  return v_status;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 10) Rank dashboards and transition receipts
-- ---------------------------------------------------------------------------

create or replace function public.get_client_rank_dashboard_v61(
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
  v_organization uuid;
  v_profile public.client_competitive_rank_v61%rowtype;
  v_rule public.cv_rank_rules_v61%rowtype;
  v_next public.cv_rank_rules_v61%rowtype;
  v_floor numeric;
  v_next_floor numeric;
  v_preview jsonb;
  v_global integer;
  v_league integer;
  v_total integer;
  v_week date:=
    date_trunc('week',now() at time zone 'America/Santiago')::date;
begin
  if auth.uid() is not null and auth.uid()<>p_actor_id then
    raise exception 'actor mismatch';
  end if;

  if p_actor_id=v_client then
    v_organization:=private.resolve_legacy_client_organization_v1(
      v_client,null
    );
  else
    v_organization:=private.resolve_legacy_professional_organization_v1(
      p_actor_id,v_client
    );
  end if;

  if not private.cv_rank_authorized_client_in_org_v61(
    v_organization,p_actor_id,v_client
  ) then
    raise exception 'not authorized';
  end if;

  insert into public.client_competitive_rank_v61(
    organization_id,client_id,competitive_alias
  )
  values(
    v_organization,v_client,private.cv_alias_v61(v_client)
  )
  on conflict(organization_id,client_id) do nothing;

  select * into v_profile
  from public.client_competitive_rank_v61
  where organization_id=v_organization
    and client_id=v_client;

  if v_profile.tutorial_completed then
    select * into v_rule
    from public.cv_rank_rules_v61
    where rank_key=v_profile.current_rank_key;
  end if;

  if v_rule.rank_key is not null then
    select * into v_next
    from public.cv_rank_rules_v61
    where order_index=v_rule.order_index+1;
  end if;

  select rating_floor into v_floor
  from public.cv_rank_level_thresholds_v61
  where level_number=greatest(1,v_profile.current_level);

  select rating_floor into v_next_floor
  from public.cv_rank_level_thresholds_v61
  where level_number=least(
    26,greatest(2,v_profile.current_level+1)
  );

  v_preview:=private.calculate_discipline_in_org_v61(
    v_organization,v_client,v_week
  );

  if v_profile.show_global and v_profile.tutorial_completed then
    select pos,total into v_global,v_total
    from (
      select
        client_id,
        row_number() over(
          order by
            cv_rating desc,
            rolling_4_week_score desc nulls last,
            rolling_12_week_score desc nulls last,
            updated_at asc
        )::integer pos,
        count(*) over()::integer total
      from public.client_competitive_rank_v61
      where organization_id=v_organization
        and show_global=true
        and tutorial_completed=true
    ) x
    where client_id=v_client;

    select pos into v_league
    from (
      select
        client_id,
        row_number() over(
          order by
            cv_rating desc,
            rolling_4_week_score desc nulls last,
            updated_at asc
        )::integer pos
      from public.client_competitive_rank_v61
      where organization_id=v_organization
        and show_global=true
        and tutorial_completed=true
        and current_rank_key=v_profile.current_rank_key
    ) x
    where client_id=v_client;
  end if;

  return jsonb_build_object(
    'version','v61',
    'organization_id',v_organization,
    'client_id',v_client,
    'tutorial_completed',v_profile.tutorial_completed,
    'current_level',v_profile.current_level,
    'rank',case
      when v_rule.rank_key is null then null
      else to_jsonb(v_rule)
    end,
    'next_rank',case
      when v_next.rank_key is null then null
      else to_jsonb(v_next)
    end,
    'cv_rating',round(v_profile.cv_rating,0),
    'rating_peak',round(v_profile.rating_peak,0),
    'rating_floor',coalesce(v_floor,0),
    'next_level_rating',v_next_floor,
    'rating_to_next_level',case
      when v_profile.current_level>=26 then 0
      else greatest(0,coalesce(v_next_floor,0)-v_profile.cv_rating)
    end,
    'level_progress_pct',case
      when v_profile.current_level=0 then 0
      when v_profile.current_level>=26 then 100
      else round(
        100*
        greatest(0,v_profile.cv_rating-coalesce(v_floor,0))/
        greatest(
          1,
          coalesce(v_next_floor,1)-coalesce(v_floor,0)
        ),
        1
      )
    end,
    'lifetime_xp',coalesce(
      (
        select total_xp
        from public.client_cv_state
        where organization_id=v_organization
          and client_id=v_client
      ),
      0
    ),
    'discipline_preview',v_preview,
    'last_discipline_score',v_profile.last_discipline_score,
    'rolling_4_week_score',v_profile.rolling_4_week_score,
    'rolling_12_week_score',v_profile.rolling_12_week_score,
    'global_position',v_global,
    'global_total',v_total,
    'league_position',v_league,
    'alias',coalesce(
      v_profile.competitive_alias,
      private.cv_alias_v61(v_client)
    ),
    'rank_protected_until',v_profile.rank_protected_until,
    'legend_since',v_profile.legend_since,
    'tutorial',private.cv_tutorial_status_in_org_v61(
      v_organization,v_client
    )
  );
end;
$function$;

create or replace function public.get_pending_rank_transition_v66(
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_role text;
  v_status text;
  v_org uuid;
  v_t public.cv_rank_transitions_v61%rowtype;
  v_from public.cv_rank_rules_v61%rowtype;
  v_to public.cv_rank_rules_v61%rowtype;
begin
  if p_actor_id is null then
    raise exception 'actor_id is required';
  end if;
  if auth.uid() is not null and auth.uid()<>p_actor_id then
    raise exception 'actor mismatch';
  end if;

  select p.role::text,p.status::text
  into v_role,v_status
  from public.profiles p
  where p.id=p_actor_id;

  if v_role is distinct from 'client'
     or v_status is distinct from 'active' then
    raise exception 'active client required';
  end if;

  v_org:=private.resolve_legacy_client_organization_v1(
    p_actor_id,null
  );

  select t.* into v_t
  from public.cv_rank_transitions_v61 t
  where t.organization_id=v_org
    and t.client_id=p_actor_id
    and t.direction in ('level_up','rank_up','legend_unlock')
    and t.created_at>=now()-interval '90 days'
    and not exists(
      select 1
      from public.cv_rank_transition_receipts_v66 r
      where r.organization_id=v_org
        and r.transition_id=t.id
        and r.client_id=p_actor_id
    )
  order by t.created_at asc
  limit 1;

  if not found then
    return jsonb_build_object(
      'organization_id',v_org,
      'pending',false
    );
  end if;

  select * into v_from
  from public.cv_rank_rules_v61
  where rank_key=v_t.from_rank_key;

  select * into v_to
  from public.cv_rank_rules_v61
  where rank_key=v_t.to_rank_key;

  return jsonb_build_object(
    'organization_id',v_org,
    'pending',true,
    'transition_id',v_t.id,
    'direction',v_t.direction,
    'from_level',v_t.from_level,
    'to_level',v_t.to_level,
    'week_start',v_t.week_start,
    'created_at',v_t.created_at,
    'metadata',coalesce(v_t.metadata,'{}'::jsonb),
    'from_rank',case
      when v_from.rank_key is null then null
      else jsonb_build_object(
        'rank_key',v_from.rank_key,
        'rank_name',v_from.rank_name,
        'color_primary',v_from.color_primary,
        'color_secondary',v_from.color_secondary,
        'badge_path',v_from.badge_path,
        'tagline',v_from.tagline
      )
    end,
    'to_rank',case
      when v_to.rank_key is null then null
      else jsonb_build_object(
        'rank_key',v_to.rank_key,
        'rank_name',v_to.rank_name,
        'color_primary',v_to.color_primary,
        'color_secondary',v_to.color_secondary,
        'badge_path',v_to.badge_path,
        'tagline',v_to.tagline
      )
    end
  );
end;
$function$;

create or replace function public.ack_rank_transition_v66(
  p_actor_id uuid,
  p_transition_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_role text;
  v_status text;
  v_org uuid;
begin
  if p_actor_id is null or p_transition_id is null then
    raise exception 'actor_id and transition_id are required';
  end if;
  if auth.uid() is not null and auth.uid()<>p_actor_id then
    raise exception 'actor mismatch';
  end if;

  select p.role::text,p.status::text
  into v_role,v_status
  from public.profiles p
  where p.id=p_actor_id;

  if v_role is distinct from 'client'
     or v_status is distinct from 'active' then
    raise exception 'active client required';
  end if;

  select t.organization_id into v_org
  from public.cv_rank_transitions_v61 t
  where t.id=p_transition_id
    and t.client_id=p_actor_id;

  if v_org is null then
    raise exception 'transition not found for actor';
  end if;

  insert into public.cv_rank_transition_receipts_v66(
    organization_id,transition_id,client_id
  )
  values(v_org,p_transition_id,p_actor_id)
  on conflict(transition_id) do nothing;

  return jsonb_build_object(
    'ok',true,
    'organization_id',v_org,
    'transition_id',p_transition_id
  );
end;
$function$;

create or replace function public.get_client_rank_state_backend(
  p_actor_id uuid,
  p_client_id uuid default null::uuid
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
  v_state public.client_cv_state%rowtype;
  v_rank public.cv_classes%rowtype;
  v_next_rank public.cv_classes%rowtype;
  v_level public.cv_levels%rowtype;
  v_next_level public.cv_levels%rowtype;
  v_rank_start_xp integer:=0;
  v_next_rank_xp integer;
  v_level_progress numeric:=100;
  v_rank_progress numeric:=100;
  v_pillars jsonb:='{}'::jsonb;
begin
  if p_actor_id is null then
    raise exception 'actor_id is required';
  end if;
  if auth.uid() is not null and auth.uid()<>p_actor_id then
    raise exception 'actor mismatch';
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
      raise exception 'self rank state requires a client account or explicit client_id';
    end if;
    v_organization:=private.resolve_legacy_client_organization_v1(
      v_client,null
    );
  else
    v_organization:=private.resolve_legacy_professional_organization_v1(
      p_actor_id,v_client
    );
    if not private.actor_can_manage_client_in_org_v1(
      p_actor_id,v_organization,v_client
    ) then
      raise exception 'actor is not authorized for this client in organization';
    end if;
  end if;

  select * into v_state
  from public.client_cv_state s
  where s.organization_id=v_organization
    and s.client_id=v_client;

  if not found then
    return jsonb_build_object(
      'organization_id',v_organization,
      'client_id',v_client,
      'current_level',1,
      'total_xp',0,
      'rank',null
    );
  end if;

  select * into v_rank
  from public.cv_classes c
  where c.rank_key is not null
    and v_state.current_level between c.min_level and c.max_level
  order by c.order_index
  limit 1;

  select * into v_next_rank
  from public.cv_classes c
  where c.rank_key is not null
    and c.order_index>v_rank.order_index
  order by c.order_index
  limit 1;

  select * into v_level
  from public.cv_levels l
  where l.level_number=v_state.current_level;

  select * into v_next_level
  from public.cv_levels l
  where l.level_number=v_state.current_level+1;

  if v_next_level.level_number is not null then
    v_level_progress:=least(
      100,
      greatest(
        0,
        100.0*
        (v_state.total_xp-v_level.xp_required_total)::numeric/
        greatest(
          1,
          v_next_level.xp_required_total-v_level.xp_required_total
        )::numeric
      )
    );
  end if;

  select coalesce(l.xp_required_total,0)
  into v_rank_start_xp
  from public.cv_levels l
  where l.level_number=v_rank.min_level;

  if v_next_rank.id is not null then
    select l.xp_required_total
    into v_next_rank_xp
    from public.cv_levels l
    where l.level_number=v_next_rank.min_level;

    v_rank_progress:=least(
      100,
      greatest(
        0,
        100.0*
        (v_state.total_xp-v_rank_start_xp)::numeric/
        greatest(
          1,
          v_next_rank_xp-v_rank_start_xp
        )::numeric
      )
    );
  end if;

  select coalesce(
    jsonb_object_agg(x.pillar,x.amount),
    '{}'::jsonb
  )
  into v_pillars
  from (
    select
      coalesce(nullif(xl.pillar,''),'other') pillar,
      coalesce(
        sum(xl.amount) filter(where xl.reversed_at is null),
        0
      )::integer amount
    from public.xp_ledger xl
    where xl.organization_id=v_organization
      and xl.client_id=v_client
    group by coalesce(nullif(xl.pillar,''),'other')
  ) x;

  return jsonb_build_object(
    'organization_id',v_organization,
    'client_id',v_client,
    'current_level',v_state.current_level,
    'total_xp',v_state.total_xp,
    'credit_balance',v_state.credit_balance,
    'cv_score',v_state.current_cv_score,
    'dynamic_state',v_state.dynamic_state,
    'rank',jsonb_build_object(
      'key',v_rank.rank_key,
      'name',v_rank.name,
      'order',v_rank.order_index,
      'min_level',v_rank.min_level,
      'max_level',v_rank.max_level,
      'color_primary',v_rank.color_primary,
      'color_secondary',v_rank.color_secondary,
      'tagline',v_rank.tagline,
      'description',v_rank.description,
      'terminal',v_rank.is_terminal
    ),
    'next_rank',case
      when v_next_rank.id is null then null
      else jsonb_build_object(
        'key',v_next_rank.rank_key,
        'name',v_next_rank.name,
        'min_level',v_next_rank.min_level,
        'color_primary',v_next_rank.color_primary,
        'color_secondary',v_next_rank.color_secondary,
        'tagline',v_next_rank.tagline
      )
    end,
    'level_start_xp',coalesce(v_level.xp_required_total,0),
    'next_level_xp',v_next_level.xp_required_total,
    'xp_to_next_level',case
      when v_next_level.level_number is null then 0
      else greatest(
        0,
        v_next_level.xp_required_total-v_state.total_xp
      )
    end,
    'level_progress_pct',round(v_level_progress,1),
    'next_rank_xp',v_next_rank_xp,
    'xp_to_next_rank',case
      when v_next_rank.id is null then 0
      else greatest(0,v_next_rank_xp-v_state.total_xp)
    end,
    'levels_to_next_rank',case
      when v_next_rank.id is null then 0
      else greatest(
        0,
        v_next_rank.min_level-v_state.current_level
      )
    end,
    'rank_progress_pct',round(v_rank_progress,1),
    'pillar_xp',v_pillars,
    'rank_reached_at',(
      select rh.reached_at
      from public.client_rank_history rh
      where rh.organization_id=v_organization
        and rh.client_id=v_client
        and rh.class_id=v_rank.id
      limit 1
    )
  );
end;
$function$;

comment on function private.process_rank_week_in_org_v61(uuid,uuid,date) is
  'F1.M1.S5 F2A tenant-explicit weekly competitive engine.';
comment on function private.calculate_discipline_in_org_v61(uuid,uuid,date) is
  'F1.M1.S5 F2A tenant-explicit discipline calculator.';
