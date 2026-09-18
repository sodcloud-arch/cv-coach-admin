from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UNIQUE = ROOT / "supabase/migrations/202609181600_f1_m1_s5_tenant_uniqueness_hardening_arch1.sql"
DERIVED = ROOT / "supabase/migrations/202609181620_f1_m1_s5_derived_records_isolation_arch1.sql"

for path in (UNIQUE, DERIVED):
    if not path.exists():
        raise SystemExit(f"Missing S5 Wave B migration: {path.name}")

unique = UNIQUE.read_text(encoding="utf-8").lower()
derived = DERIVED.read_text(encoding="utf-8").lower()

required_unique = [
    "uq_programs_org_client_version",
    "uq_programs_one_active_per_org_client",
    "uq_programs_one_draft_per_org_client",
    "workout_sessions_one_active_per_org_client_idx",
    "uq_weekly_checkins_org_client_week",
    "uq_nutrition_daily_org_client_date",
    "uq_client_subscriptions_open_per_org_client",
    "ux_coach_alerts_weekly_program_review_active_org",
]
required_derived = [
    "alter table public.ai_program_generations\n  add column if not exists organization_id uuid",
    "alter table public.adaptive_program_drafts\n  add column if not exists organization_id uuid",
    "alter table public.subscription_billing_records\n  add column if not exists organization_id uuid",
    "alter table public.training_adaptation_reviews\n  add column if not exists organization_id uuid",
    "alter table public.weekly_program_reviews\n  add column if not exists organization_id uuid",
    "ai_program_generations_program_same_org_client",
    "ai_program_generations_coach_same_org",
    "adaptive_program_drafts_source_program_same_org_client",
    "adaptive_program_drafts_draft_program_same_org_client",
    "adaptive_program_drafts_review_same_org_client",
    "subscription_billing_records_subscription_same_org_client",
    "training_adaptation_reviews_program_same_org_client",
    "training_adaptation_reviews_session_same_org_client",
    "weekly_program_reviews_program_same_org_client",
    "weekly_program_reviews_checkin_same_org_client",
    "weekly_program_reviews_coach_same_org",
    "private.can_manage_client_in_org(organization_id,client_id)",
    "private.can_view_client_in_org(organization_id,client_id)",
    "revoke truncate,trigger,references",
]

for label, body, required in (
    ("tenant uniqueness", unique, required_unique),
    ("derived isolation", derived, required_derived),
):
    missing = [token for token in required if token not in body]
    if missing:
        raise SystemExit(f"Missing {label} contracts: " + ", ".join(missing))

legacy_unique = [
    "create unique index uq_programs_client_version",
    "create unique index uq_programs_one_active_per_client",
    "create unique index uq_programs_one_draft_per_client",
    "create unique index workout_sessions_one_active_per_client_idx",
]
for token in legacy_unique:
    if token in unique:
        raise SystemExit(f"Legacy global uniqueness recreated: {token}")

legacy_rls = [
    "using (( select private.can_manage_client(",
    "using (private.can_manage_client(client_id))",
    "using (( select private.can_view_client(",
]
for token in legacy_rls:
    if token in derived:
        raise SystemExit(f"Legacy global-user RLS recreated: {token}")

print("F1.M1.S5 Wave B isolation contract: PASS")
print("- tenant-scoped uniqueness: PASS")
print("- derived business records carry organization_id: PASS")
print("- same-tenant parent relations: PASS")
print("- legacy global-user RLS replaced: PASS")
print("- browser DDL-adjacent privileges removed: PASS")
