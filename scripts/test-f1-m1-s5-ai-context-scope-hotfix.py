from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
M = ROOT / "supabase/migrations/202609182700_f1_m1_s5_ai_context_scope_hotfix_arch1.sql"
sql = M.read_text(encoding="utf-8").lower()

required = [
    "r.organization_id=v_organization and r.client_id=p_client_id",
    "wc.organization_id=v_organization and wc.client_id=p_client_id",
    "tp.organization_id=v_organization and tp.client_id=p_client_id",
    "sp.organization_id=v_organization and sp.client_id=p_client_id",
    "g.organization_id=v_organization and g.idempotency_key=v_key",
    "get_client_time_learning_in_org(v_organization,p_client_id)",
    "compute_mesocycle_intelligence_in_org_v85(v_organization,p_client_id,v_program.id)",
    "actor_can_manage_client_in_org_v1(",
]
missing = [x for x in required if x not in sql]
if missing:
    raise SystemExit("Missing tenant hotfix contracts: " + ", ".join(missing))

forbidden = [
    "from public.onboarding_responses r where r.client_id=p_client_id",
    "from public.weekly_checkins wc where wc.client_id=p_client_id",
    "from public.client_training_preferences tp where tp.client_id=p_client_id",
    "from public.client_training_schedule_preferences sp where sp.client_id=p_client_id",
]
bad = [x for x in forbidden if x in sql]
if bad:
    raise SystemExit("Unscoped client context remains: " + ", ".join(bad))

print("F1.M1.S5 AI context tenant hotfix: PASS")
print("- onboarding context scoped by Organization: PASS")
print("- weekly check-in context scoped by Organization: PASS")
print("- training preferences scoped by Organization: PASS")
print("- schedule preferences scoped by Organization: PASS")
