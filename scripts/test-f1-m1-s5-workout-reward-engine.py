from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
M=ROOT/"supabase/migrations/202609182200_f1_m1_s5_workout_reward_engine_arch1.sql"
sql=M.read_text(encoding="utf-8").lower()

required=[
    "actor_can_manage_client_in_org_v1(",
    "x.organization_id = v_session.organization_id",
    "se.organization_id = v_session.organization_id",
    "sl.organization_id=v_session.organization_id",
    "insert into public.xp_ledger(organization_id,client_id",
    "insert into public.credit_ledger(organization_id,client_id",
    "cm.organization_id = v_session.organization_id",
    "ca.organization_id=v_session.organization_id",
    "ws.organization_id=v_session.organization_id",
    "insert into public.client_achievements(\n          organization_id,client_id",
    "level_requirements_met_in_org(v_session.organization_id",
    "'organization_id',v_session.organization_id",
]

missing=[x for x in required if x not in sql]
if missing:
    raise SystemExit("Missing E2C contracts: "+", ".join(missing))

for forbidden in (
    "public.coach_clients",
    "insert into public.xp_ledger(client_id",
    "insert into public.credit_ledger(client_id",
    "private.level_requirements_met(v_session.client_id",
    "where cm.client_id = v_session.client_id\n      and cm.status",
    "where ca.client_id = v_session.client_id and ca.achievement_id",
):
    if forbidden in sql:
        raise SystemExit("Legacy global workout reward path reintroduced: "+forbidden)

print("F1.M1.S5 E2C workout reward engine: PASS")
print("- canonical actor authorization: PASS")
print("- XP/Credit reads+writes scoped by session Organization: PASS")
print("- Mission progress/rewards scoped by Organization: PASS")
print("- Achievement checks/rewards scoped by Organization: PASS")
print("- Level requirements scoped by Organization: PASS")
print("- result/notification metadata carries Organization: PASS")
