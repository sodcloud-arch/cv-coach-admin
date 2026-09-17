from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "supabase/migrations/202609171700_f1_m1_s1_organization_arch1.sql"
HARDENING = ROOT / "supabase/migrations/202609171710_f1_m1_s1_organization_hardening_arch1.sql"
sql = BASE.read_text(encoding="utf-8").lower()
hardening = HARDENING.read_text(encoding="utf-8").lower()

required = {
    "organizations table": "create table if not exists public.organizations",
    "members table": "create table if not exists public.organization_members",
    "tenant status": "create type public.organization_status",
    "member role": "create type public.organization_member_role",
    "member status": "create type public.organization_member_status",
    "org rls": "alter table public.organizations enable row level security",
    "member rls": "alter table public.organization_members enable row level security",
    "platform admin helper": "function private.is_platform_admin()",
    "org member helper": "function private.is_org_member(target_organization uuid)",
    "org admin helper": "function private.is_org_admin(target_organization uuid)",
    "visibility helper": "function private.can_view_organization(target_organization uuid)",
    "atomic creator": "function public.create_organization(",
    "slug guard": "organization slug is immutable",
    "archive terminal": "archived organization is terminal",
    "owner membership": "'owner'::public.organization_member_role",
    "restricted direct org grant": "grant select,update on table public.organizations to authenticated",
}

missing = [name for name, token in required.items() if token not in sql]
if missing:
    raise SystemExit("Missing F1.M1.S1 contracts: " + ", ".join(missing))

hardening_required = {
    "owner FK index": "create index if not exists idx_organizations_owner_user_id",
    "authenticated RPC revoke": "from authenticated",
    "backend RPC grant": "to service_role",
}
missing_hardening = [name for name, token in hardening_required.items() if token not in hardening]
if missing_hardening:
    raise SystemExit("Missing F1.M1.S1 hardening: " + ", ".join(missing_hardening))

legacy_tables = (
    "profiles", "coach_clients", "client_profiles", "programs", "program_days",
    "program_exercises", "workout_sessions", "session_exercises", "set_logs", "exercises"
)
for table in legacy_tables:
    token = f"alter table public.{table}"
    if token in sql or token in hardening:
        raise SystemExit(f"F1.M1.S1 must stay additive; legacy mutation found: {token}")

for forbidden in (
    "grant insert on table public.organizations to authenticated",
    "grant delete on table public.organizations to authenticated",
    "grant insert on table public.organization_members to authenticated",
    "grant delete on table public.organization_members to authenticated",
):
    if forbidden in sql or forbidden in hardening:
        raise SystemExit(f"Unsafe direct privilege found: {forbidden}")

print("F1.M1.S1 Organization contract: PASS")
print("- additive legacy compatibility: PASS")
print("- tenant root + membership bridge: PASS")
print("- RLS helpers + lifecycle guards: PASS")
print("- service-only tenant creation + owner FK index: PASS")
