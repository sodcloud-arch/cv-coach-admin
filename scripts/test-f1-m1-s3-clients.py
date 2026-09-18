from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/202609180800_f1_m1_s3_tenant_clients_arch1.sql"
sql = MIGRATION.read_text(encoding="utf-8").lower()

required = {
    "tenant client status": "create type public.tenant_client_status",
    "canonical client table": "create table if not exists public.tenant_client_profiles",
    "organization scope": "organization_id uuid not null references public.organizations(id)",
    "nullable account": "user_id uuid references public.profiles(id) on delete set null",
    "tenant user uniqueness": "unique (organization_id,user_id)",
    "tenant composite identity": "unique (organization_id,id)",
    "lifecycle lead": "'lead'",
    "lifecycle invited": "'invited'",
    "lifecycle active": "'active'",
    "lifecycle paused": "'paused'",
    "lifecycle archived": "'archived'",
    "onboarding state": "onboarding_state text not null",
    "rls": "alter table public.tenant_client_profiles enable row level security",
    "scoped visibility": "function private.can_view_tenant_client(",
    "professional access": "private.is_org_professional(target_organization)",
    "member self access": "private.is_org_member(target_organization)",
    "backend creator": "function public.create_tenant_client_profile(",
    "backend linker": "function public.link_tenant_client_user(",
    "backend-only create": "tenant client creation is backend-only",
    "backend-only link": "tenant client account linking is backend-only",
    "immutable tenant": "client profile organization is immutable",
    "immutable linked user": "linked client user is immutable",
    "terminal archive": "archived client profile is terminal",
    "legacy compatibility note": "legacy public.client_profiles remains operational until controlled cutover",
}
missing = [name for name, token in required.items() if token not in sql]
if missing:
    raise SystemExit("Missing F1.M1.S3 contracts: " + ", ".join(missing))

# S3 must remain additive while the live portal still reads the legacy client model.
for forbidden in (
    "alter table public.client_profiles",
    "drop table public.client_profiles",
    "alter table public.coach_clients",
    "drop table public.coach_clients",
    "alter table public.profiles",
    "drop table public.profiles",
):
    if forbidden in sql:
        raise SystemExit(f"F1.M1.S3 must not mutate legacy schema: {forbidden}")

for forbidden in (
    "grant insert on table public.tenant_client_profiles to authenticated",
    "grant update on table public.tenant_client_profiles to authenticated",
    "grant delete on table public.tenant_client_profiles to authenticated",
    "grant execute on function public.create_tenant_client_profile(uuid,text,uuid,public.tenant_client_status,text,text,jsonb,text) to authenticated",
    "grant execute on function public.link_tenant_client_user(uuid,uuid) to authenticated",
):
    if forbidden in sql:
        raise SystemExit(f"Unsafe authenticated privilege found: {forbidden}")

if "where user_id is not null" not in sql:
    raise SystemExit("Expected nullable-user index contract")

print("F1.M1.S3 Clients contract: PASS")
print("- tenant-scoped client identity: PASS")
print("- client without login/account: PASS")
print("- later account linking: PASS")
print("- same user may exist across different tenants: PASS")
print("- terminal archive preserves identity/history: PASS")
print("- additive legacy compatibility: PASS")
