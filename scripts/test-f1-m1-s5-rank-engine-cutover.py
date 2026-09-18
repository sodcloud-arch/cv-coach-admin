from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
M=ROOT/"supabase/migrations/202609182300_f1_m1_s5_rank_engine_cutover_arch1.sql"
sql=M.read_text(encoding="utf-8").lower()

required=[
    "primary key (organization_id,client_id)",
    "client_rank_history_org_client_class_key",
    "cv_rank_rating_ledger_v61_org_client_event_key",
    "cv_rank_weekly_snapshots_v61_org_client_week_start_key",
    "primary key (organization_id,client_id,step_key)",
    "cv_trophies_v61_org_client_trophy_key",
    "cv_rank_authorized_client_in_org_v61",
    "calculate_discipline_in_org_v61",
    "refresh_rank_rollups_in_org_v61",
    "cv_tutorial_status_in_org_v61",
    "bootstrap_competitive_rank_from_client_v1",
    "track_cv_rank_from_level_history",
    "process_rank_week_in_org_v61",
    "organization_id=p_organization",
    "on conflict(organization_id,client_id,week_start)",
    "private.cv_tutorial_status_in_org_v61(",
    "where rh.organization_id=v_organization",
]
missing=[x for x in required if x not in sql]
if missing:
    raise SystemExit("Missing F2A contracts: "+", ".join(missing))

for forbidden in (
    "on conflict(client_id,class_id)",
    "where client_id=p_client for update",
    "where client_id=p_client and event_key=v_event",
    "on conflict(client_id,week_start)",
):
    if forbidden in sql:
        raise SystemExit("Legacy global rank contract reintroduced: "+forbidden)

print("F1.M1.S5 F2A Rank engine cutover: PASS")
print("- Organization + Client rank identity: PASS")
print("- tenant-explicit discipline and weekly engine: PASS")
print("- canonical Client bootstrap: PASS")
print("- tutorial/transitions/dashboard tenant-local: PASS")
