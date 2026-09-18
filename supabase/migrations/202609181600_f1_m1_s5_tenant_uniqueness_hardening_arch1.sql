-- ARCH-1.0 · F1.M1.S5 — tenant-scoped uniqueness hardening
-- Replaces legacy global-user uniqueness with Organization-scoped uniqueness
-- where the same user may legitimately exist in more than one tenant.

-- Programs: version lifecycle is per Organization + client.
drop index if exists public.uq_programs_client_version;
create unique index uq_programs_org_client_version
  on public.programs(organization_id,client_id,version);

drop index if exists public.uq_programs_one_active_per_client;
create unique index uq_programs_one_active_per_org_client
  on public.programs(organization_id,client_id)
  where status='active'::public.program_status;

drop index if exists public.uq_programs_one_draft_per_client;
create unique index uq_programs_one_draft_per_org_client
  on public.programs(organization_id,client_id)
  where status='draft'::public.program_status;

-- Workout runtime: a client may have one in-progress session in each tenant.
drop index if exists public.workout_sessions_one_active_per_client_idx;
create unique index workout_sessions_one_active_per_org_client_idx
  on public.workout_sessions(organization_id,client_id)
  where status='in_progress'::public.workout_session_status;

-- Weekly check-ins: same calendar week is independent per tenant.
alter table public.weekly_checkins
  drop constraint if exists weekly_checkins_client_id_week_start_key;
create unique index uq_weekly_checkins_org_client_week
  on public.weekly_checkins(organization_id,client_id,week_start);

-- Nutrition logs: same date is independent per tenant.
alter table public.nutrition_daily_logs
  drop constraint if exists nutrition_daily_logs_client_id_log_date_key;
create unique index uq_nutrition_daily_org_client_date
  on public.nutrition_daily_logs(organization_id,client_id,log_date);

-- Subscription lifecycle: a user may subscribe independently in different tenants.
drop index if exists public.uq_client_subscriptions_open_per_client;
create unique index uq_client_subscriptions_open_per_org_client
  on public.client_subscriptions(organization_id,client_id)
  where status = any (
    array[
      'pending'::public.subscription_status,
      'trialing'::public.subscription_status,
      'active'::public.subscription_status,
      'past_due'::public.subscription_status
    ]
  );

-- Coach alert dedupe must not collide between Organizations sharing the same users.
drop index if exists public.ux_coach_alerts_weekly_program_review_active;
create unique index ux_coach_alerts_weekly_program_review_active_org
  on public.coach_alerts(
    organization_id,
    coach_id,
    client_id,
    ((source_data ->> 'review_key'::text))
  )
  where (
    alert_type='weekly_program_review'::text
    and status = any(array['open'::public.alert_status,'acknowledged'::public.alert_status])
  );

comment on index public.uq_programs_one_active_per_org_client is
  'F1.M1.S5: active Program uniqueness is tenant-scoped, not global-user scoped.';
comment on index public.workout_sessions_one_active_per_org_client_idx is
  'F1.M1.S5: in-progress workout uniqueness is tenant-scoped, not global-user scoped.';
