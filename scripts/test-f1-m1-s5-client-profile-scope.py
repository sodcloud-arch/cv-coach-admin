from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
M = ROOT / "supabase/migrations/202609181800_f1_m1_s5_client_profile_scope_arch1.sql"
sql = M.read_text(encoding="utf-8").lower()

required = [
    "resolve_legacy_professional_organization_v1",
    "alter table public.client_profiles\n  add column if not exists organization_id uuid",
    "alter table public.client_training_constraints\n  add column if not exists organization_id uuid",
    "alter table public.client_training_preferences\n  add column if not exists organization_id uuid",
    "alter table public.client_training_schedule_preferences\n  add column if not exists organization_id uuid",
    "alter table public.onboarding_responses\n  add column if not exists organization_id uuid",
    "client_profiles_client_same_org",
    "client_training_constraints_client_same_org",
    "client_training_preferences_client_same_org",
    "client_training_schedule_preferences_client_same_org",
    "onboarding_responses_client_same_org",
    "guard_legacy_client_scoped_row_v1",
    "can_view_client_in_org(organization_id,client_id)",
    "can_manage_client_in_org(organization_id,client_id)",
    "private.is_org_member(organization_id)",
    "insert into public.clients(",
    "on conflict(organization_id,user_id)",
    "insert into public.client_coach_assignments(",
    "'organization_id',v_organization",
]

missing = [token for token in required if token not in sql]
if missing:
    raise SystemExit("Missing C3A contracts: " + ", ".join(missing))

# C3A intentionally preserves legacy PK/UNIQUE contracts until C3B.
for forbidden in (
    "primary key (organization_id,client_id)",
    "drop constraint if exists client_profiles_pkey",
    "drop constraint if exists client_training_preferences_pkey",
    "drop constraint if exists client_training_schedule_preferences_pkey",
):
    if forbidden in sql:
        raise SystemExit("C3A prematurely changed global compatibility identity: " + forbidden)

legacy_rls = [
    "private.can_view_client(client_profiles.client_id)",
    "private.can_manage_client(client_id)",
]
for token in legacy_rls:
    if token in sql:
        raise SystemExit("Legacy global-user RLS reintroduced: " + token)

print("F1.M1.S5 C3A client profile scope: PASS")
print("- explicit organization_id on profile/onboarding/preferences: PASS")
print("- same-tenant client FKs: PASS")
print("- reusable immutable legacy guard: PASS")
print("- tenant-aware RLS: PASS")
print("- legacy PK/UNIQUE compatibility intentionally preserved: PASS")
print("- provisioning canonicalizes Organization -> Client -> Assignment: PASS")
