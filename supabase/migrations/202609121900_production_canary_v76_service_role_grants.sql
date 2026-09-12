-- CV Coach V76 hotfix — minimal internal privileges required by the production canary.
-- This does not grant anything to anon/authenticated; it restores only service_role
-- read/cleanup capabilities used by cv-canary-auth-v76.

grant select on table
  public.client_profiles,
  public.programs,
  public.session_exercises,
  public.set_logs
  to service_role;

grant select, delete on table
  public.xp_ledger,
  public.credit_ledger,
  public.client_achievements,
  public.cv_score_snapshots,
  public.client_level_history,
  public.notifications
  to service_role;

grant select, update on table
  public.client_cv_state
  to service_role;

grant select, update, delete on table
  public.client_missions,
  public.progression_suggestions
  to service_role;

grant select, delete on table
  public.workout_sessions
  to service_role;
