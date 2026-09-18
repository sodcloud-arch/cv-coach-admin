from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/202609181000_f1_m1_s5_canonical_data_isolation_arch1.sql"
ROOTS = ROOT / "supabase/migrations/202609181020_f1_m1_s5_business_roots_isolation_arch1.sql"
sql = MIGRATION.read_text(encoding="utf-8").lower()
roots = ROOTS.read_text(encoding="utf-8").lower()

required = {
    "discipline organization column": "alter table public.coach_profile_disciplines\n  add column if not exists organization_id uuid",
    "credential organization column": "alter table public.coach_credentials\n  add column if not exists organization_id uuid",
    "discipline not null": "alter column organization_id set not null",
    "discipline composite tenant fk": "constraint coach_profile_disciplines_same_org",
    "credential composite tenant fk": "constraint coach_credentials_same_org",
    "coach membership boundary": "constraint coach_profiles_member_same_org",
    "client linked-user boundary": "constraint clients_user_member_same_org",
    "client creator boundary": "constraint clients_created_by_member_same_org",
    "credential verifier boundary": "constraint coach_credentials_verified_by_member_same_org",
    "assignment actor boundary": "constraint client_coach_assignments_assigned_by_member_same_org",
    "unassignment actor boundary": "constraint client_coach_assignments_unassigned_by_member_same_org",
    "discipline cross-tenant guard": "coach discipline cannot cross organization boundary",
    "credential cross-tenant guard": "coach credential cannot cross organization boundary",
    "discipline direct RLS": "using (private.can_view_organization(organization_id))",
    "credential tenant admin RLS": "private.is_org_admin(organization_id)",
    "revoke organizations": "revoke all privileges on table public.organizations",
    "revoke members": "revoke all privileges on table public.organization_members",
    "revoke clients": "revoke all privileges on table public.clients",
    "revoke assignments": "revoke all privileges on table public.client_coach_assignments",
    "safe organization update": "grant update (",
    "service mutation": "grant all privileges on table public.client_coach_assignments to service_role",
}
missing = [name for name, token in required.items() if token not in sql]
if missing:
    raise SystemExit("Missing F1.M1.S5 contracts: " + ", ".join(missing))

# Browser roles must not retain general table mutation or dangerous DDL-adjacent privileges.
for forbidden in (
    "grant all privileges on table public.organizations to authenticated",
    "grant all privileges on table public.organization_members to authenticated",
    "grant all privileges on table public.coach_profiles to authenticated",
    "grant all privileges on table public.coach_profile_disciplines to authenticated",
    "grant all privileges on table public.coach_credentials to authenticated",
    "grant all privileges on table public.clients to authenticated",
    "grant all privileges on table public.client_coach_assignments to authenticated",
    "grant truncate",
    "grant trigger",
    "grant references",
):
    if forbidden in sql:
        raise SystemExit(f"Unsafe browser privilege in S5 migration: {forbidden}")

# Organization self-service may change presentation/localization/settings only.
safe_update_block = """
grant update (
  display_name,
  legal_name,
  locale,
  timezone,
  currency,
  branding_config,
  settings
) on table public.organizations to authenticated;
""".strip()
if safe_update_block not in sql:
    raise SystemExit("Organization UPDATE whitelist does not match S5 contract")

for forbidden_column in ("slug", "owner_user_id", "status", "feature_flags", "plan_id", "billing_account_id"):
    update_block = sql[sql.index("grant update ("):sql.index(") on table public.organizations to authenticated;")]
    if forbidden_column in update_block:
        raise SystemExit(f"Sensitive organization column is browser-updatable: {forbidden_column}")

# No service-role credential/reference is allowed in browser-delivered client files.
client_root = ROOT / "client-portal"
client_hits = []
if client_root.exists():
    for path in client_root.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in {".js", ".mjs", ".cjs", ".html", ".json", ".ts", ".tsx", ".jsx"}:
            continue
        body = path.read_text(encoding="utf-8", errors="ignore").lower()
        if "supabase_service_role" in body or "service_role_key" in body:
            client_hits.append(str(path.relative_to(ROOT)))
if client_hits:
    raise SystemExit("Service-role secret reference found in client bundle: " + ", ".join(client_hits))

print("F1.M1.S5 canonical data isolation contract: PASS")
print("- tenant-owned professional child tables carry organization_id: PASS")
print("- composite same-tenant FK boundaries: PASS")
print("- membership-scoped identity/audit actors: PASS")
print("- authenticated table privileges reduced to least privilege: PASS")
print("- organization browser UPDATE uses explicit safe-column whitelist: PASS")
print("- service-role secret references absent from client portal: PASS")


root_required = {
    "legacy resolver": "function private.resolve_legacy_client_organization_v1(",
    "tenant view helper": "function private.can_view_client_in_org(",
    "tenant manage helper": "function private.can_manage_client_in_org(",
    "program tenant": "alter table public.programs add column if not exists organization_id uuid",
    "session tenant": "alter table public.workout_sessions add column if not exists organization_id uuid",
    "alerts tenant": "alter table public.coach_alerts add column if not exists organization_id uuid",
    "progression tenant": "alter table public.progression_suggestions add column if not exists organization_id uuid",
    "checkins tenant": "alter table public.weekly_checkins add column if not exists organization_id uuid",
    "nutrition tenant": "alter table public.nutrition_daily_logs add column if not exists organization_id uuid",
    "subscriptions tenant": "alter table public.client_subscriptions add column if not exists organization_id uuid",
    "program client boundary": "constraint programs_client_same_org",
    "program coach boundary": "constraint programs_coach_same_org",
    "session program/client boundary": "constraint workout_sessions_program_same_org_client",
    "alert client boundary": "constraint coach_alerts_client_same_org",
    "alert coach boundary": "constraint coach_alerts_coach_same_org",
    "progression session boundary": "constraint progression_suggestions_source_session_same_org_client",
    "ambiguous tenant deny": "legacy client belongs to multiple organizations; organization_id is required",
    "program rls v2": "create policy programs_select_v2",
    "session rls v2": "create policy workout_sessions_select_v2",
    "nutrition rls v2": "create policy nutrition_daily_select_v2",
    "subscription rls v2": "create policy subscriptions_select_v2",
}
missing_roots = [name for name, token in root_required.items() if token not in roots]
if missing_roots:
    raise SystemExit("Missing F1.M1.S5 wave-2 contracts: " + ", ".join(missing_roots))

for legacy_policy_token in (
    "create policy programs_select\non public.programs",
    "create policy workout_sessions_select\non public.workout_sessions",
    "create policy nutrition_daily_select\non public.nutrition_daily_logs",
):
    if legacy_policy_token in roots:
        raise SystemExit("Legacy tenant-agnostic policy was recreated: " + legacy_policy_token)

for forbidden in (
    "grant truncate",
    "grant trigger",
    "grant references",
    "grant all privileges on table public.programs to authenticated",
    "grant all privileges on table public.workout_sessions to authenticated",
    "grant all privileges on table public.coach_alerts to authenticated",
    "grant all privileges on table public.progression_suggestions to authenticated",
    "grant all privileges on table public.weekly_checkins to authenticated",
    "grant all privileges on table public.nutrition_daily_logs to authenticated",
    "grant all privileges on table public.client_subscriptions to authenticated",
):
    if forbidden in roots:
        raise SystemExit("Unsafe browser privilege in S5 wave 2: " + forbidden)

print("- business roots carry explicit organization_id: PASS")
print("- business-root policies use tenant-aware access helpers: PASS")
print("- ambiguous multi-tenant legacy writes require explicit organization_id: PASS")
print("- sessions/programs/alerts have same-tenant relational constraints: PASS")
