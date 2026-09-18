from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
M = ROOT / "supabase/migrations/202609181930_f1_m1_s5_nutrition_habit_producers_arch1.sql"
sql = M.read_text(encoding="utf-8").lower()

required = [
    "private.can_view_client_in_org(ml.organization_id,ml.client_id)",
    "private.can_manage_client_in_org(",
    "ml.organization_id,ml.client_id",
    "private.can_manage_client_in_org(\n              pp.organization_id,pp.client_id",
    "resolve_legacy_professional_organization_v1(",
    "actor_can_manage_client_in_org_v1(",
    "where organization_id=v_organization",
    "insert into public.nutrition_targets(\n    organization_id,client_id",
    "select\n    ch.organization_id,\n    ch.client_id",
    "insert into public.habit_logs(\n    organization_id,client_habit_id,client_id",
    "perform private.resolve_legacy_client_organization_v1(v_client,null)",
    "where nt.organization_id=v_organization",
    "insert into public.nutrition_daily_logs(\n    organization_id,client_id",
    "on conflict(organization_id,client_id,log_date)",
]

missing=[token for token in required if token not in sql]
if missing:
    raise SystemExit("Missing D2 contracts: "+", ".join(missing))

for forbidden in (
    "on conflict (client_id,log_date)",
    "where client_id=p_client_id and active=true",
    "private.can_manage_client(ml.client_id)",
    "private.can_view_client(ml.client_id)",
):
    if forbidden in sql:
        raise SystemExit("Legacy global producer contract reintroduced: "+forbidden)

print("F1.M1.S5 D2 nutrition/habit producers: PASS")
print("- nutrition target writes are tenant-local: PASS")
print("- nutrition daily conflict key is tenant-scoped: PASS")
print("- habit writes derive Organization from client_habit: PASS")
print("- meal/photo helpers use tenant-aware authorization: PASS")
print("- ambiguous legacy CV12 reward context fails safely: PASS")
