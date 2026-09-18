from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
M=ROOT/"supabase/migrations/202609182100_f1_m1_s5_cv12_reward_engine_arch1.sql"
sql=M.read_text(encoding="utf-8").lower()

required=[
    "uq_cv12_reward_processing_org_event_source",
    "uq_client_level_history_org_level",
    "uq_client_achievements_org_achievement",
    "uq_xp_source_once_org",
    "uq_credit_source_once_org",
    "level_requirements_met_in_org",
    "award_cv12_action_in_org",
    "process_event_missions_in_org",
    "process_generic_achievements_in_org",
    "refresh_client_cv_state_in_org",
    "create or replace function private.cv_state_from_xp_ledger()",
    "create or replace function private.cv_state_from_credit_ledger()",
    "create or replace function private.cv_state_from_score()",
    "create or replace function private.cv_state_from_client_profile()",
    "organization_id,client_id,event_key,source_id",
    "organization_id,client_id,level_number",
    "organization_id,client_id,achievement_id",
    "x.organization_id=p_organization_id",
    "c.organization_id=p_organization_id",
    "cm.organization_id=p_organization_id",
    "ws.organization_id=p_organization_id",
    "cs.organization_id=p_organization_id",
]

missing=[x for x in required if x not in sql]
if missing:
    raise SystemExit("Missing E2A contracts: "+", ".join(missing))

for forbidden in (
    "on conflict (client_id,event_key,source_id)",
    "on conflict(client_id,level_number)",
    "create unique index uq_xp_source_once on public.xp_ledger",
    "create unique index uq_credit_source_once on public.credit_ledger",
):
    if forbidden in sql:
        raise SystemExit("Legacy global CV12 idempotency reintroduced: "+forbidden)

if "drop constraint if exists client_cv_state_pkey" in sql:
    raise SystemExit("E2A prematurely changed client_cv_state PK")

print("F1.M1.S5 E2A CV12 reward engine: PASS")
print("- reward processing is tenant-explicit: PASS")
print("- mission and achievement engines are tenant-explicit: PASS")
print("- XP/Credit/Achievement idempotency is tenant-scoped: PASS")
print("- level history is tenant-scoped: PASS")
print("- client_cv_state PK remains intentionally deferred to E2B: PASS")
