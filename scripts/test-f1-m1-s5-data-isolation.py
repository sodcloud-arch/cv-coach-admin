from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/202609181000_f1_m1_s5_canonical_data_isolation_arch1.sql"
sql = MIGRATION.read_text(encoding="utf-8").lower()

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
