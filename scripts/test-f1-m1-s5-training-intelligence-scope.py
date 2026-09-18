from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
M=ROOT/"supabase/migrations/202609182530_f1_m1_s5_training_intelligence_scope_arch1.sql"
sql=M.read_text(encoding="utf-8").lower()

required=[
    "latest_weekly_recovery_context_in_org(ws.organization_id",
    "wh.organization_id=ws.organization_id",
    "compute_training_adaptation_in_org_v83",
    "ws.organization_id=p_organization_id",
    "compute_mesocycle_intelligence_in_org_v85",
    "p.organization_id=p_organization_id",
    "ps.organization_id=p_organization_id",
    "actor_can_manage_client_in_org_v1(",
]
missing=[x for x in required if x not in sql]
if missing:
    raise SystemExit("Missing G1B3A contracts: "+", ".join(missing))

if "private.latest_weekly_recovery_context(ws.client_id" in sql:
    raise SystemExit("Legacy global recovery context reintroduced")

print("F1.M1.S5 G1B3A training intelligence scope: PASS")
print("- deterministic/progression history uses Session Organization: PASS")
print("- adaptation engine is tenant-explicit: PASS")
print("- mesocycle intelligence is tenant-explicit: PASS")
print("- legacy wrappers derive tenant from globally unique Program: PASS")
