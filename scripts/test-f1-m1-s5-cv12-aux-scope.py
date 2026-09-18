from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
M=ROOT/"supabase/migrations/202609182020_f1_m1_s5_cv12_aux_scope_arch1.sql"
sql=M.read_text(encoding="utf-8").lower()

required=[
    "alter table private.cv12_reward_processing\n  add column if not exists organization_id uuid",
    "alter table public.client_level_history\n  add column if not exists organization_id uuid",
    "cv12_reward_processing_client_same_org",
    "client_level_history_client_same_org",
    "guard_legacy_client_scoped_row_v1",
    "can_view_client_in_org(organization_id,client_id)",
    "ix_cv12_reward_processing_org_client_event_date",
    "ix_client_level_history_org_client_date",
]

missing=[x for x in required if x not in sql]
if missing:
    raise SystemExit("Missing E1B contracts: "+", ".join(missing))

for forbidden in (
    "drop constraint if exists client_level_history_client_id_level_number_key",
    "drop constraint if exists cv12_reward_processing_client_id_event_key_source_id_key",
):
    if forbidden in sql:
        raise SystemExit("E1B prematurely changed compatibility identity: "+forbidden)

if "private.can_view_client(client_level_history.client_id)" in sql:
    raise SystemExit("Legacy level-history RLS reintroduced")

print("F1.M1.S5 E1B CV12 auxiliary scope: PASS")
print("- reward-processing tenant scope: PASS")
print("- level-history tenant scope: PASS")
print("- compatibility UNIQUE preserved for E2A: PASS")
print("- tenant-aware level-history RLS: PASS")
