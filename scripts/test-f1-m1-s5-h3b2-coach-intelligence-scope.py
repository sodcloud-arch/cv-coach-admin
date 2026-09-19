from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
M=ROOT/"supabase/migrations/202609190100_f1_m1_s5_h3b2_coach_intelligence_scope_arch1.sql"
sql=M.read_text(encoding="utf-8").lower()

required=[
  "alter table private.coach_action_workspace_v95",
  "organization_id",
  "uq_coach_action_workspace_v95_org_actor_recommendation",
  "coach_action_outcome_events_v96_workspace_same_org",
  "get_coach_attention_queue_tenant_v1",
  "get_coach_intelligence_dashboard_v86",
  "actor_can_manage_client_in_org_v1",
  "get_coach_ai_command_center_v94",
  "a.organization_id=l.organization_id",
  "current_coach_actions_v95",
  "'v95:'||a.organization_id::text",
  "decide_coach_action_v95",
  "on conflict(organization_id,actor_id,recommendation_key)",
  "get_coach_action_workspace_v95",
  "start_coach_action_v95",
  "complete_coach_action_v95",
  "reconcile_due_coach_action_outcomes_v96",
]
missing=[x for x in required if x not in sql]
if missing:
    raise SystemExit("Missing H3B2 contracts: "+", ".join(missing))

for forbidden in [
  "from public.coach_clients cc where cc.coach_id=p_actor_id",
  "or exists(select 1 from public.coach_clients",
  "on w.actor_id=p_actor_id and w.recommendation_key=c.recommendation_key",
]:
    if forbidden in sql:
        raise SystemExit("Unsafe cross-tenant pattern remains: "+forbidden)

print("F1.M1.S5 H3B2 base contracts: PASS")
print("- coach intelligence aggregates keyed by organization: PASS")
print("- workspace/outcome storage organization scoped: PASS")
print("- action mutation authorization canonical: PASS")
