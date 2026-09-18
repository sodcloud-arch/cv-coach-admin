-- ARCH-1.0 · F1.M1.S5 Wave E2C — Workout completion reward engine
-- Keeps workout completion semantics intact while binding every reward/read/write
-- to the canonical Organization of the Workout Session.

CREATE OR REPLACE FUNCTION public.complete_workout_backend_core(p_session_id uuid, p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_session public.workout_sessions%rowtype;
  v_actor_role text;
  v_existing jsonb;
  v_exercise_count integer := 0;
  v_target_sets integer := 0;
  v_completed_sets integer := 0;
  v_completion numeric(5,2) := 0;
  v_total_volume numeric := 0;
  v_event record;
  v_status public.workout_session_status;
  v_before_xp integer := 0;
  v_after_xp integer := 0;
  v_previous_level integer := 0;
  v_current_level integer := 0;
  v_awarded integer;
  v_xp_earned integer := 0;
  v_credits_earned integer := 0;
  v_missions_completed integer := 0;
  v_achievement record;
  v_mission record;
  v_increment numeric;
  v_new_progress numeric;
  v_metric numeric;
  v_target numeric;
  v_unlock boolean;
  v_new_achievement_id uuid;
  v_achievement_pass integer;
  v_new_unlocks integer;
  v_achievements jsonb := '[]'::jsonb;
  v_result jsonb;
begin
  if p_session_id is null or p_actor_id is null then
    raise exception 'session_id and actor_id are required';
  end if;

  select * into v_session
  from public.workout_sessions
  where id = p_session_id
  for update;

  if not found then
    raise exception 'workout session not found';
  end if;

  select wp.result into v_existing
  from private.workout_processing wp
  where wp.session_id = p_session_id;

  if found then
    return v_existing || jsonb_build_object('organization_id',v_session.organization_id,'idempotent', true);
  end if;

  select p.role::text into v_actor_role
  from public.profiles p
  where p.id = p_actor_id and p.status::text = 'active';

  if v_actor_role is null then
    raise exception 'actor is not an active CV Coach user';
  end if;

  if p_actor_id <> v_session.client_id then
    if v_actor_role in ('admin','coach')
       and private.actor_can_manage_client_in_org_v1(
         p_actor_id,
         v_session.organization_id,
         v_session.client_id
       ) then
      null;
    else
      raise exception 'actor is not authorized to complete this workout in organization';
    end if;
  elsif not exists(
    select 1
    from public.clients c
    where c.organization_id=v_session.organization_id
      and c.user_id=v_session.client_id
      and c.status<>'archived'::public.client_status
  ) then
    raise exception 'session client is not active in workout organization';
  end if;

  select coalesce(sum(x.amount),0)::integer into v_before_xp
  from public.xp_ledger x
  where x.organization_id = v_session.organization_id
    and x.client_id = v_session.client_id
    and x.reversed_at is null;

  with per_ex as (
    select se.id,
           se.status,
           coalesce(pe.target_sets, greatest(count(sl.id)::integer,1)) as target_sets,
           count(sl.id) filter (where sl.completed = true)::integer as completed_sets
    from public.session_exercises se
    left join public.program_exercises pe on pe.organization_id = se.organization_id and pe.id = se.program_exercise_id
    left join public.set_logs sl on sl.organization_id = se.organization_id and sl.session_exercise_id = se.id
    where se.organization_id = v_session.organization_id
      and se.workout_session_id = p_session_id
    group by se.id,se.status,pe.target_sets
  )
  select count(*)::integer,
         coalesce(sum(target_sets),0)::integer,
         coalesce(sum(least(completed_sets,target_sets)),0)::integer
  into v_exercise_count,v_target_sets,v_completed_sets
  from per_ex;

  if v_exercise_count = 0 or v_target_sets = 0 then
    raise exception 'workout has no executable exercise data';
  end if;

  v_completion := round((100.0 * v_completed_sets::numeric / v_target_sets::numeric),2);

  select coalesce(sum(coalesce(sl.weight_kg,0) * coalesce(sl.reps,0)) filter (where sl.completed = true),0)
  into v_total_volume
  from public.set_logs sl
  join public.session_exercises se on se.organization_id=sl.organization_id and se.id = sl.session_exercise_id
  where se.organization_id=v_session.organization_id
    and sl.organization_id=v_session.organization_id
    and se.workout_session_id = p_session_id;

  with per_ex as (
    select se.id,
           se.status,
           coalesce(pe.target_sets, greatest(count(sl.id)::integer,1)) as target_sets,
           count(sl.id) filter (where sl.completed = true)::integer as completed_sets
    from public.session_exercises se
    left join public.program_exercises pe on pe.organization_id = se.organization_id and pe.id = se.program_exercise_id
    left join public.set_logs sl on sl.organization_id = se.organization_id and sl.session_exercise_id = se.id
    where se.organization_id = v_session.organization_id
      and se.workout_session_id = p_session_id
    group by se.id,se.status,pe.target_sets
  )
  update public.session_exercises se
  set status = case
      when pe.status = 'skipped'::public.session_exercise_status then 'skipped'::public.session_exercise_status
      when pe.completed_sets >= pe.target_sets and pe.target_sets > 0 then 'completed'::public.session_exercise_status
      else 'pending'::public.session_exercise_status
    end,
    updated_at = now()
  from per_ex pe
  where se.organization_id=v_session.organization_id
    and se.id = pe.id;

  select event_key,pillar,min_completion_pct,xp_reward,credit_reward
  into v_event
  from private.cv_event_rewards
  where active = true and min_completion_pct <= v_completion
  order by min_completion_pct desc
  limit 1;

  if v_event.event_key = 'workout_completed' then
    v_status := 'completed'::public.workout_session_status;
  elsif v_event.event_key = 'workout_partial' then
    v_status := 'partial'::public.workout_session_status;
  else
    v_status := 'abandoned'::public.workout_session_status;
  end if;

  update public.workout_sessions
  set finished_at = now(),
      status = v_status,
      completion_pct = v_completion,
      duration_seconds = greatest(0, extract(epoch from (now() - started_at))::integer),
      total_volume = v_total_volume,
      updated_at = now()
  where organization_id=v_session.organization_id
    and id = p_session_id;

  if v_event.xp_reward > 0 then
    v_awarded := null;
    insert into public.xp_ledger(organization_id,client_id,pillar,source_type,source_id,amount,description)
    values(v_session.organization_id,v_session.client_id,v_event.pillar,v_event.event_key,p_session_id,v_event.xp_reward,'Recompensa por entrenamiento')
    on conflict do nothing
    returning amount into v_awarded;
    v_xp_earned := v_xp_earned + coalesce(v_awarded,0);
  end if;

  if v_event.credit_reward > 0 then
    v_awarded := null;
    insert into public.credit_ledger(organization_id,client_id,transaction_type,source_type,source_id,amount,description)
    values(v_session.organization_id,v_session.client_id,'earned'::public.credit_transaction_type,v_event.event_key,p_session_id,v_event.credit_reward,'Créditos por entrenamiento')
    on conflict do nothing
    returning amount into v_awarded;
    v_credits_earned := v_credits_earned + coalesce(v_awarded,0);
  end if;

  for v_mission in
    select cm.id,cm.progress,cm.target,cm.xp_reward_snapshot,cm.credit_reward_snapshot,mt.rule,cm.mission_name
    from public.client_missions cm
    join public.mission_templates mt on mt.id = cm.mission_template_id
    where cm.organization_id = v_session.organization_id
      and cm.client_id = v_session.client_id
      and cm.status = 'active'::public.client_mission_status
      and cm.start_at <= now()
      and (cm.expires_at is null or cm.expires_at >= now())
      and coalesce(mt.rule->>'event','') = v_event.event_key
    for update of cm
  loop
    v_increment := coalesce(nullif(v_mission.rule->>'increment','')::numeric,1);
    v_new_progress := least(v_mission.target, v_mission.progress + v_increment);

    update public.client_missions
    set progress = v_new_progress,
        status = case when v_new_progress >= v_mission.target then 'completed'::public.client_mission_status else status end,
        completed_at = case when v_new_progress >= v_mission.target then coalesce(completed_at,now()) else completed_at end,
        updated_at = now()
    where organization_id=v_session.organization_id
      and id = v_mission.id;

    if v_new_progress >= v_mission.target then
      v_missions_completed := v_missions_completed + 1;

      if v_mission.xp_reward_snapshot > 0 then
        v_awarded := null;
        insert into public.xp_ledger(organization_id,client_id,pillar,source_type,source_id,amount,description)
        values(v_session.organization_id,v_session.client_id,'training','mission_completed',v_mission.id,v_mission.xp_reward_snapshot,'Misión completada: '||v_mission.mission_name)
        on conflict do nothing returning amount into v_awarded;
        v_xp_earned := v_xp_earned + coalesce(v_awarded,0);
      end if;

      if v_mission.credit_reward_snapshot > 0 then
        v_awarded := null;
        insert into public.credit_ledger(organization_id,client_id,transaction_type,source_type,source_id,amount,description)
        values(v_session.organization_id,v_session.client_id,'earned'::public.credit_transaction_type,'mission_completed',v_mission.id,v_mission.credit_reward_snapshot,'Misión completada: '||v_mission.mission_name)
        on conflict do nothing returning amount into v_awarded;
        v_credits_earned := v_credits_earned + coalesce(v_awarded,0);
      end if;

      insert into public.notifications(user_id,type,title,body,action_url,metadata)
      values(v_session.client_id,'mission_completed','Misión completada','Completaste '||v_mission.mission_name,'/progress/missions',jsonb_build_object('organization_id',v_session.organization_id,'mission_id',v_mission.id));
    end if;
  end loop;

  for v_achievement_pass in 1..5 loop
    v_new_unlocks := 0;

    for v_achievement in
      select a.id,a.rarity,a.xp_reward,a.credit_reward,
             r.rule,r.unlocked_title,r.unlocked_description,r.unlocked_badge_path
      from public.achievements a
      join private.achievement_rules r on r.achievement_id = a.id
      where a.active = true
        and not exists (
          select 1 from public.client_achievements ca
          where ca.organization_id=v_session.organization_id
            and ca.client_id = v_session.client_id and ca.achievement_id = a.id
        )
    loop
      v_unlock := false;
      v_metric := null;
      v_target := nullif(v_achievement.rule->>'target','')::numeric;

      if v_target is not null then
        case v_achievement.rule->>'type'
          when 'workout_count' then
            if coalesce((v_achievement.rule->>'include_partial')::boolean,false) then
              select count(*)::numeric into v_metric
              from public.workout_sessions ws
              where ws.organization_id=v_session.organization_id
                and ws.client_id = v_session.client_id
                and ws.status in ('completed'::public.workout_session_status,'partial'::public.workout_session_status);
            else
              select count(*)::numeric into v_metric
              from public.workout_sessions ws
              where ws.organization_id=v_session.organization_id
                and ws.client_id = v_session.client_id
                and ws.status = 'completed'::public.workout_session_status;
            end if;
          when 'total_xp' then
            select coalesce(sum(x.amount),0)::numeric into v_metric
            from public.xp_ledger x
            where x.organization_id = v_session.organization_id
    and x.client_id = v_session.client_id
    and x.reversed_at is null;
          when 'completed_missions' then
            select count(*)::numeric into v_metric
            from public.client_missions cm
            where cm.organization_id=v_session.organization_id
              and cm.client_id = v_session.client_id
              and cm.status = 'completed'::public.client_mission_status;
          else
            v_metric := null;
        end case;

        v_unlock := v_metric is not null and v_metric >= v_target;
      end if;

      if v_unlock then
        v_new_achievement_id := null;
        insert into public.client_achievements(
          organization_id,client_id,achievement_id,title_snapshot,description_snapshot,rarity_snapshot,badge_path_snapshot,
          xp_reward_snapshot,credit_reward_snapshot,trigger_source
        ) values (
          v_session.organization_id,v_session.client_id,v_achievement.id,v_achievement.unlocked_title,v_achievement.unlocked_description,
          v_achievement.rarity,v_achievement.unlocked_badge_path,v_achievement.xp_reward,v_achievement.credit_reward,
          v_event.event_key
        )
        on conflict do nothing returning id into v_new_achievement_id;

        if v_new_achievement_id is not null then
          v_new_unlocks := v_new_unlocks + 1;
          v_achievements := v_achievements || jsonb_build_array(jsonb_build_object(
            'achievement_id',v_achievement.id,'title',v_achievement.unlocked_title,'rarity',v_achievement.rarity::text
          ));

          if v_achievement.xp_reward > 0 then
            v_awarded := null;
            insert into public.xp_ledger(organization_id,client_id,pillar,source_type,source_id,amount,description)
            values(v_session.organization_id,v_session.client_id,'progress','achievement_unlocked',v_achievement.id,v_achievement.xp_reward,'Logro: '||v_achievement.unlocked_title)
            on conflict do nothing returning amount into v_awarded;
            v_xp_earned := v_xp_earned + coalesce(v_awarded,0);
          end if;

          if v_achievement.credit_reward > 0 then
            v_awarded := null;
            insert into public.credit_ledger(organization_id,client_id,transaction_type,source_type,source_id,amount,description)
            values(v_session.organization_id,v_session.client_id,'earned'::public.credit_transaction_type,'achievement_unlocked',v_achievement.id,v_achievement.credit_reward,'Logro: '||v_achievement.unlocked_title)
            on conflict do nothing returning amount into v_awarded;
            v_credits_earned := v_credits_earned + coalesce(v_awarded,0);
          end if;

          insert into public.notifications(user_id,type,title,body,action_url,metadata)
          values(v_session.client_id,'achievement_unlocked','Logro desbloqueado',v_achievement.unlocked_title,'/progress/achievements',jsonb_build_object('organization_id',v_session.organization_id,'achievement_id',v_achievement.id,'rarity',v_achievement.rarity::text));
        end if;
      end if;
    end loop;

    exit when v_new_unlocks = 0;
  end loop;

  select coalesce(sum(x.amount),0)::integer into v_after_xp
  from public.xp_ledger x
  where x.organization_id = v_session.organization_id
    and x.client_id = v_session.client_id
    and x.reversed_at is null;

  select coalesce(max(l.level_number),0) into v_previous_level
  from public.cv_levels l
  where l.xp_required_total <= v_before_xp
    and private.level_requirements_met_in_org(v_session.organization_id,v_session.client_id,l.level_number);

  select coalesce(max(l.level_number),0) into v_current_level
  from public.cv_levels l
  where l.xp_required_total <= v_after_xp
    and private.level_requirements_met_in_org(v_session.organization_id,v_session.client_id,l.level_number);

  if v_current_level > v_previous_level then
    insert into public.notifications(user_id,type,title,body,action_url,metadata)
    values(v_session.client_id,'level_up','¡Subiste de nivel!','Ahora eres Nivel '||v_current_level,'/progress',jsonb_build_object('organization_id',v_session.organization_id,'previous_level',v_previous_level,'current_level',v_current_level));
  end if;

  v_result := jsonb_build_object(
    'organization_id',v_session.organization_id,
    'session_id',p_session_id,
    'client_id',v_session.client_id,
    'status',v_status::text,
    'event',v_event.event_key,
    'completion_pct',v_completion,
    'total_volume',v_total_volume,
    'xp_earned',v_xp_earned,
    'credits_earned',v_credits_earned,
    'missions_completed',v_missions_completed,
    'achievements_unlocked',v_achievements,
    'previous_level',v_previous_level,
    'current_level',v_current_level,
    'level_up',(v_current_level > v_previous_level),
    'idempotent',false
  );

  insert into private.workout_processing(session_id,event_key,result)
  values(p_session_id,v_event.event_key,v_result);

  return v_result;
end;
$function$;


comment on function public.complete_workout_backend_core(uuid,uuid) is
  'F1.M1.S5 E2C: workout completion rewards, missions, achievements and level checks are scoped by Workout Session Organization.';
