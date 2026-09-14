-- CV Coach V93 — Client Lifecycle & Onboarding Control Center
-- Read-only lifecycle aggregation. Reuses existing mutation paths.

create or replace function public.get_client_lifecycle_center_v93(p_actor_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_role text;
  v_items jsonb;
begin
  if auth.uid() is null or p_actor_id is null or auth.uid() <> p_actor_id then
    raise exception 'Authenticated actor mismatch';
  end if;

  select p.role::text into v_role
  from public.profiles p
  where p.id = p_actor_id
    and p.status::text = 'active';

  if v_role not in ('admin','coach') then
    raise exception 'Coach/admin required';
  end if;

  with visible_clients as (
    select p.*
    from public.profiles p
    where p.role::text = 'client'
      and (
        v_role = 'admin'
        or exists (
          select 1
          from public.coach_clients ccx
          where ccx.client_id = p.id
            and ccx.coach_id = p_actor_id
            and ccx.status::text = 'active'
        )
      )
  ), lifecycle as (
    select
      p.id as client_id,
      nullif(trim(concat_ws(' ', p.first_name, p.last_name)), '') as client_name,
      p.first_name,
      p.last_name,
      p.phone,
      p.status::text as profile_status,
      cp.primary_goal,
      cp.onboarding_status::text as onboarding_status,
      coalesce(ob.response_count, 0) as onboarding_response_count,
      inv.email,
      inv.status as invite_status,
      inv.created_at as invite_created_at,
      inv.last_generated_at,
      inv.accepted_at,
      inv.revoked_at,
      rel.status as coach_relationship_status,
      rel.assigned_at,
      active_program.id as active_program_id,
      active_program.name as active_program_name,
      active_program.version as active_program_version,
      draft_program.id as draft_program_id,
      draft_program.name as draft_program_name,
      draft_program.version as draft_program_version,
      sub.id as subscription_id,
      sub.status as subscription_status,
      sub.renews_at as subscription_renews_at,
      sub.plan_name,
      case
        when cp.onboarding_status::text in ('in_progress','completed','approved') or coalesce(ob.response_count,0) > 0 then 'activity_detected'
        when inv.status = 'generated' and inv.revoked_at is null then 'setup_link_generated'
        when inv.revoked_at is not null or inv.status = 'revoked' then 'access_revoked'
        else 'no_access_link'
      end as access_state,
      case
        when p.status::text <> 'active' then 'account_blocked'
        when cp.client_id is null then 'profile_incomplete'
        when cp.onboarding_status::text in ('pending','in_progress') then 'onboarding_in_progress'
        when cp.onboarding_status::text = 'completed' then 'onboarding_review'
        when cp.onboarding_status::text = 'approved' and coalesce(rel.status,'') <> 'active' then 'coach_assignment'
        when cp.onboarding_status::text = 'approved' and draft_program.id is not null then 'program_draft'
        when cp.onboarding_status::text = 'approved' and active_program.id is null then 'program_needed'
        when cp.onboarding_status::text = 'approved' and active_program.id is not null then 'operational'
        else 'needs_review'
      end as lifecycle_stage,
      case
        when p.status::text <> 'active' then 'review_account_status'
        when cp.client_id is null then 'review_client_profile'
        when cp.onboarding_status::text = 'pending' and (inv.email is null or inv.revoked_at is not null) then 'generate_access_link'
        when cp.onboarding_status::text = 'pending' then 'wait_for_onboarding'
        when cp.onboarding_status::text = 'in_progress' then 'wait_for_onboarding_completion'
        when cp.onboarding_status::text = 'completed' then 'review_onboarding'
        when cp.onboarding_status::text = 'approved' and coalesce(rel.status,'') <> 'active' then 'review_coach_assignment'
        when cp.onboarding_status::text = 'approved' and draft_program.id is not null then 'finish_program_draft'
        when cp.onboarding_status::text = 'approved' and active_program.id is null then 'create_initial_program'
        when cp.onboarding_status::text = 'approved' and active_program.id is not null then 'monitor_client'
        else 'review_client'
      end as next_action
    from visible_clients p
    left join public.client_profiles cp on cp.client_id = p.id
    left join lateral (
      select count(*)::int as response_count
      from public.onboarding_responses x
      where x.client_id = p.id
    ) ob on true
    left join lateral (
      select i.email, i.status, i.created_at, i.last_generated_at, i.accepted_at, i.revoked_at
      from public.client_invites i
      where i.client_id = p.id
        and (v_role = 'admin' or i.coach_id = p_actor_id)
      order by coalesce(i.last_generated_at, i.created_at) desc nulls last, i.created_at desc
      limit 1
    ) inv on true
    left join lateral (
      select c.status::text as status, c.assigned_at
      from public.coach_clients c
      where c.client_id = p.id
        and (v_role = 'admin' or c.coach_id = p_actor_id)
      order by (c.status::text = 'active') desc, c.assigned_at desc nulls last
      limit 1
    ) rel on true
    left join lateral (
      select pr.id, pr.name, pr.version
      from public.programs pr
      where pr.client_id = p.id and pr.status::text = 'active'
      order by pr.version desc nulls last, pr.updated_at desc
      limit 1
    ) active_program on true
    left join lateral (
      select pr.id, pr.name, pr.version
      from public.programs pr
      where pr.client_id = p.id and pr.status::text = 'draft'
      order by pr.version desc nulls last, pr.updated_at desc
      limit 1
    ) draft_program on true
    left join lateral (
      select cs.id, cs.status::text as status, cs.renews_at, pl.name as plan_name
      from public.client_subscriptions cs
      left join public.plans pl on pl.id = cs.plan_id
      where cs.client_id = p.id
      order by (cs.status::text in ('active','trialing','past_due','pending')) desc, cs.updated_at desc
      limit 1
    ) sub on true
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'client_id', client_id,
      'client_name', coalesce(client_name,'Cliente sin nombre'),
      'first_name', first_name,
      'last_name', last_name,
      'phone', phone,
      'email', email,
      'profile_status', profile_status,
      'primary_goal', primary_goal,
      'access_state', access_state,
      'invite_status', invite_status,
      'invite_created_at', invite_created_at,
      'last_generated_at', last_generated_at,
      'accepted_at', accepted_at,
      'revoked_at', revoked_at,
      'onboarding_status', coalesce(onboarding_status,'pending'),
      'onboarding_response_count', onboarding_response_count,
      'coach_relationship_status', coach_relationship_status,
      'assigned_at', assigned_at,
      'active_program_id', active_program_id,
      'active_program_name', active_program_name,
      'active_program_version', active_program_version,
      'draft_program_id', draft_program_id,
      'draft_program_name', draft_program_name,
      'draft_program_version', draft_program_version,
      'subscription_id', subscription_id,
      'subscription_status', subscription_status,
      'subscription_renews_at', subscription_renews_at,
      'plan_name', plan_name,
      'lifecycle_stage', lifecycle_stage,
      'next_action', next_action,
      'guardrails', jsonb_build_object(
        'read_only_aggregate', true,
        'reuse_existing_provision_client', true,
        'reuse_existing_onboarding_review', true,
        'reuse_existing_programming', true,
        'no_auto_publish', true
      )
    ) order by
      case lifecycle_stage
        when 'account_blocked' then 1
        when 'profile_incomplete' then 2
        when 'onboarding_review' then 3
        when 'coach_assignment' then 4
        when 'program_draft' then 5
        when 'program_needed' then 6
        when 'onboarding_in_progress' then 7
        when 'needs_review' then 8
        else 9
      end,
      lower(coalesce(client_name,''))
  ), '[]'::jsonb) into v_items
  from lifecycle;

  return jsonb_build_object(
    'ok', true,
    'engine_version', 'CLIENT_LIFECYCLE_CONTROL_V93',
    'count', jsonb_array_length(v_items),
    'items', v_items,
    'guardrails', jsonb_build_object(
      'read_only_aggregate', true,
      'mutations_reuse_existing_backend', true,
      'no_auto_publish', true,
      'no_synthetic_identity', true
    )
  );
end;
$$;

revoke all on function public.get_client_lifecycle_center_v93(uuid) from public;
grant execute on function public.get_client_lifecycle_center_v93(uuid) to authenticated;
