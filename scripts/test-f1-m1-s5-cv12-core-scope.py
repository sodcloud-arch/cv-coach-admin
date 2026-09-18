from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
M = ROOT / "supabase/migrations/202609182000_f1_m1_s5_cv12_core_scope_arch1.sql"
sql = M.read_text(encoding="utf-8").lower()

required = [
    "alter table public.client_cv_state\n  add column if not exists organization_id uuid",
    "alter table public.xp_ledger\n  add column if not exists organization_id uuid",
    "alter table public.credit_ledger\n  add column if not exists organization_id uuid",
    "alter table public.client_missions\n  add column if not exists organization_id uuid",
    "alter table public.client_achievements\n  add column if not exists organization_id uuid",
    "alter table public.cv_score_snapshots\n  add column if not exists organization_id uuid",
    "alter table public.reward_redemptions\n  add column if not exists organization_id uuid",
    "client_cv_state_client_same_org",
    "xp_ledger_client_same_org",
    "credit_ledger_client_same_org",
    "client_missions_client_same_org",
    "client_achievements_client_same_org",
    "cv_score_snapshots_client_same_org",
    "reward_redemptions_client_same_org",
    "client_missions_assigned_by_member_same_org",
    "guard_legacy_client_scoped_row_v1",
    "can_view_client_in_org(organization_id,client_id)",
    "can_manage_client_in_org(organization_id,client_id)",
    "revoke truncate,trigger,references",
]

missing=[token for token in required if token not in sql]
if missing:
    raise SystemExit("Missing E1 contracts: "+", ".join(missing))

for forbidden in (
    "drop constraint if exists client_cv_state_pkey",
    "primary key (organization_id,client_id)",
    "drop index if exists public.uq_xp_source_once",
    "drop index if exists public.uq_credit_source_once",
    "drop constraint if exists client_achievements_client_id_achievement_id_key",
):
    if forbidden in sql:
        raise SystemExit("E1 prematurely changed compatibility identity: "+forbidden)

for legacy in (
    "private.can_view_client(client_cv_state.client_id)",
    "private.can_view_client(xp_ledger.client_id)",
    "private.can_view_client(credit_ledger.client_id)",
    "private.can_manage_client(client_missions.client_id)",
):
    if legacy in sql:
        raise SystemExit("Legacy global CV12 RLS reintroduced: "+legacy)

print("F1.M1.S5 E1 CV12 core scope: PASS")
print("- explicit Organization scope on CV12 core: PASS")
print("- same-tenant Client boundaries: PASS")
print("- tenant-aware RLS: PASS")
print("- compatibility PK/UNIQUE preserved for E2: PASS")
print("- browser DDL-adjacent privileges removed: PASS")
