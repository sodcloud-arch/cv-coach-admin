from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
M=ROOT/"supabase/migrations/202609182130_f1_m1_s5_cvscore_state_cutover_arch1.sql"
sql=M.read_text(encoding="utf-8").lower()

required=[
    "primary key (organization_id,client_id)",
    "calculate_cv_score_core_in_org",
    "where cp.organization_id=p_organization_id",
    "where p.organization_id=p_organization_id",
    "where ws.organization_id=p_organization_id",
    "where nt.organization_id=p_organization_id",
    "where nd.organization_id=p_organization_id",
    "where ch.organization_id=p_organization_id",
    "where m.organization_id=p_organization_id",
    "where pp.organization_id=p_organization_id",
    "where rp.organization_id=p_organization_id",
    "insert into public.cv_score_snapshots(\n    organization_id,client_id",
    "where s.organization_id=p_organization_id",
    "on conflict(organization_id,client_id) do nothing",
    "recalculate_cv_score_trigger",
    "private.calculate_cv_score_core_in_org(",
    "private.award_cv12_action_in_org(",
    "private.process_event_missions_in_org(",
    "private.process_generic_achievements_in_org(",
    "private.refresh_client_cv_state_in_org(",
    "from public.client_cv_state s where s.organization_id=v_organization and s.client_id=v_client",
    "private.actor_can_manage_client_in_org_v1(",
    "create or replace function private.process_cv_score_automation()",
    "private.set_coach_alert_in_org(",
    "cm.organization_id=new.organization_id",
    "p.organization_id=new.organization_id",
    "nt.organization_id=new.organization_id",
    "ch.organization_id=new.organization_id",
]

missing=[x for x in required if x not in sql]
if missing:
    raise SystemExit("Missing E2B contracts: "+", ".join(missing))

for forbidden in (
    "on conflict(client_id) do nothing",
    "from public.client_cv_state s where s.client_id=v_client;",
    "perform private.calculate_cv_score_core(v_client",
    "from private.award_cv12_action(",
    "private.process_event_missions(\n",
    "private.process_generic_achievements(\n",
    "private.refresh_client_cv_state(v_client",
):
    if forbidden in sql:
        raise SystemExit("Legacy global CV12 state/score contract reintroduced: "+forbidden)

print("F1.M1.S5 E2B CV Score/state cutover: PASS")
print("- client_cv_state PK is Organization + Client: PASS")
print("- CV Score inputs are tenant-scoped: PASS")
print("- score/state triggers preserve Organization: PASS")
print("- habit/nutrition reward paths are explicit-tenant: PASS")
print("- workout wrapper reads state by Organization: PASS")
print("- rank readers scope state/XP and require canonical assignment: PASS")
