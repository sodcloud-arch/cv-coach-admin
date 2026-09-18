from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
M=ROOT/"supabase/migrations/202609182230_f1_m1_s5_competitive_scope_arch1.sql"
sql=M.read_text(encoding="utf-8").lower()

required=[
    "alter table public.client_competitive_rank_v61 add column if not exists organization_id uuid",
    "alter table public.cv_seasons_v61 add column if not exists organization_id uuid",
    "alter table public.cv_challenges_v61 add column if not exists organization_id uuid",
    "cv_season_weekly_points_v61_season_same_org",
    "cv_challenge_entries_v61_challenge_same_org",
    "cv_challenge_winners_v61_challenge_same_org",
    "cv_rank_transition_receipts_v66_transition_same_org_client",
    "guard_competitive_parent_tenant_v1",
    "guard_challenge_child_tenant_v1",
    "guard_season_points_tenant_v1",
    "guard_rank_transition_receipt_tenant_v1",
    "can_view_client_in_org(organization_id,client_id)",
    "private.is_org_member(organization_id)",
    "revoke truncate,trigger,references",
]
missing=[x for x in required if x not in sql]
if missing:
    raise SystemExit("Missing F1 contracts: "+", ".join(missing))

for forbidden in (
    "drop constraint if exists client_competitive_rank_v61_pkey",
    "drop constraint if exists client_rank_history_client_id_class_id_key",
    "drop constraint if exists cv_rank_rating_ledger_v61_client_id_event_key_key",
    "drop constraint if exists cv_rank_weekly_snapshots_v61_client_id_week_start_key",
    "drop constraint if exists cv_trophies_v61_client_id_trophy_key_key",
):
    if forbidden in sql:
        raise SystemExit("F1 prematurely changed compatibility identity: "+forbidden)

print("F1.M1.S5 F1 competitive scope: PASS")
print("- competitive tenant ownership: PASS")
print("- challenge/season same-tenant children: PASS")
print("- tenant-aware read policies: PASS")
print("- compatibility identities preserved for F2: PASS")
