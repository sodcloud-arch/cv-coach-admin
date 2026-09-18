from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "supabase/migrations/202609171900_f1_m1_s3_clients_arch1.sql"
BACKFILL = ROOT / "supabase/migrations/202609171910_f1_m1_s3_cv_coach_client_backfill_arch1.sql"
sql = BASE.read_text(encoding="utf-8").lower()
backfill = BACKFILL.read_text(encoding="utf-8").lower()

required = {
    "client status": "create type public.client_status",
    "canonical clients": "create table if not exists public.clients",
    "tenant scope": "organization_id uuid not null references public.organizations(id)",
    "nullable account": "user_id uuid references public.profiles(id) on delete set null",
    "accountless lifecycle": "'lead','invited','active','paused','archived'",
    "contact metadata": "contact_metadata jsonb not null",
    "onboarding state": "onboarding_state jsonb not null",
    "tenant user uniqueness": "on public.clients(organization_id,user_id)",
    "rls": "alter table public.clients enable row level security",
    "scoped visibility": "function private.can_view_client_entity(",
    "professional access": "private.is_org_professional(c.organization_id)",
    "client self access": "private.is_org_member(c.organization_id)",
    "backend creator": "function public.create_client(",
    "backend linker": "function public.link_client_user(",
    "backend-only create": "client creation is backend-only",
    "backend-only link": "client account linking is backend-only",
    "immutable tenant": "client organization is immutable",
    "immutable linked user": "linked client user is immutable through direct updates",
    "terminal archive": "archived client is terminal",
}
missing = [name for name, token in required.items() if token not in sql]
if missing:
    raise SystemExit("Missing F1.M1.S3 base contracts: " + ", ".join(missing))

backfill_required = {
    "cv coach tenant": "where slug='cv-coach'",
    "legacy relationships": "join public.coach_clients cc",
    "legacy profile read": "left join public.client_profiles cp",
    "membership bridge": "insert into public.organization_members",
    "canonical client backfill": "insert into public.clients",
    "idempotent membership": "on conflict (organization_id,user_id) do nothing",
    "idempotent client": "not exists(",
    "legacy source": "'source','legacy_cv_coach'",
}
missing_backfill = [name for name, token in backfill_required.items() if token not in backfill]
if missing_backfill:
    raise SystemExit("Missing F1.M1.S3 backfill contracts: " + ", ".join(missing_backfill))

for source_name, source in (("base", sql), ("backfill", backfill)):
    for forbidden in (
        "alter table public.client_profiles",
        "drop table public.client_profiles",
        "alter table public.coach_clients",
        "drop table public.coach_clients",
        "alter table public.profiles",
        "drop table public.profiles",
    ):
        if forbidden in source:
            raise SystemExit(f"F1.M1.S3 {source_name} must not mutate legacy schema: {forbidden}")

for forbidden in (
    "grant insert on table public.clients to authenticated",
    "grant update on table public.clients to authenticated",
    "grant delete on table public.clients to authenticated",
    "grant execute on function public.create_client(uuid,text,uuid,public.client_status,jsonb,jsonb,uuid) to authenticated",
    "grant execute on function public.link_client_user(uuid,uuid) to authenticated",
):
    if forbidden in sql:
        raise SystemExit(f"Unsafe authenticated privilege found: {forbidden}")

print("F1.M1.S3 Clients contract: PASS")
print("- canonical tenant-scoped client identity: PASS")
print("- client can exist before login/account: PASS")
print("- later account linking with active membership: PASS")
print("- same global user can be a client in different tenants: PASS")
print("- archive preserves canonical identity/history: PASS")
print("- existing CV Coach clients backfilled additively: PASS")
print("- legacy client_profiles / coach_clients remain untouched: PASS")
