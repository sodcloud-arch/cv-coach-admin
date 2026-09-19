from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
M=ROOT/"supabase/migrations/202609190030_f1_m1_s5_h3b1_billing_lifecycle_system_scope_arch1.sql"
sql=M.read_text(encoding="utf-8").lower()

required=[
  "manage_client_subscription_backend",
  "manage_subscription_billing_backend",
  "organization_id,client_id,plan_id",
  "actor_can_manage_client_in_org_v1",
  "ensure_subscription_billing_records",
  "refresh_billing_alerts",
  "refresh_subscription_renewal_alerts",
  "sync_onboarding_review_alert",
  "set_coach_alert_in_org",
  "check_training_e2e_health",
  "get_client_lifecycle_center_v93",
  "x.organization_id=vc.organization_id",
  "pr.organization_id=vc.organization_id",
  "cs.organization_id=vc.organization_id",
  "resolve_cv12_native_client_v91",
  "provision_client_records_backend",
  "organization_id=v_organization",
  "pending composite identity cutover",
]
missing=[x for x in required if x not in sql]
if missing:
    raise SystemExit("Missing H3B1 contracts: "+", ".join(missing))

for forbidden in [
  "where cc.coach_id=p_actor_id and cc.client_id=v_subscription.client_id",
  "join public.coach_clients cc on cc.client_id=b.client_id",
  "where cc.client_id=new.client_id",
  "from public.coach_clients cc\n    join public.profiles p on p.id=cc.client_id",
]:
    if forbidden in sql:
        raise SystemExit("Unsafe legacy authorization pattern remains: "+forbidden)

print("F1.M1.S5 H3B1 contracts: PASS")
print("- billing mutations tenant-scoped: PASS")
print("- billing/renewal jobs canonical assignment scoped: PASS")
print("- onboarding/training system alerts tenant-scoped: PASS")
print("- lifecycle aggregate tenant-scoped: PASS")
print("- legacy CV12/provision wrappers fail-safe: PASS")
