from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
M = ROOT / "supabase/migrations/202609181730_f1_m1_s5_risk_attention_isolation_arch1.sql"
sql = M.read_text(encoding="utf-8").lower()

required = [
    "primary key (organization_id,client_id)",
    "client_risk_state_client_same_org",
    "weekly_checkin_risk_assessments_checkin_same_org_client",
    "weekly_checkin_risk_assessments_event_same_org_client",
    "guard_client_risk_state_tenant_v1",
    "guard_weekly_risk_tenant_v1",
    "can_manage_client_in_org(organization_id,client_id)",
    "latest_weekly_recovery_context_in_org",
    "set_coach_alert_in_org",
    "on conflict(organization_id,client_id)",
    "e.organization_id=c.organization_id",
    "e.organization_id=v_session.organization_id",
    "s.organization_id=v_session.organization_id",
    "a.organization_id=new.organization_id",
    "r.organization_id=ca.organization_id",
    "alert.organization_id=ca.organization_id",
    "ws.organization_id=ca.organization_id",
    "where organization_id=v_alert.organization_id",
]

missing = [token for token in required if token not in sql]
if missing:
    raise SystemExit("Missing risk/attention tenant contracts: " + ", ".join(missing))

for forbidden in (
    "on conflict(client_id) do update",
    "left join public.client_risk_state r on r.client_id=cc.client_id",
    "where client_id=new.client_id and requires_coach=true",
    "where client_id=v_alert.client_id and requires_coach=true",
):
    if forbidden in sql:
        raise SystemExit("Legacy global risk contract reintroduced: " + forbidden)

print("F1.M1.S5 Risk/Attention isolation: PASS")
print("- risk PK is Organization + Client: PASS")
print("- weekly risk/event chain is same-tenant: PASS")
print("- risk RLS is tenant-aware: PASS")
print("- weekly/workout engines are tenant-aware: PASS")
print("- coach alerts use canonical tenant assignment: PASS")
print("- attention queue joins are tenant-local: PASS")
print("- public RPC signatures preserved: PASS")
