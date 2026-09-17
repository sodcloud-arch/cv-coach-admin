from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "supabase/migrations/202609171800_f1_m1_s2_coach_profiles_arch1.sql"
HARDENING = ROOT / "supabase/migrations/202609171805_f1_m1_s2_coach_profile_hardening_arch1.sql"
sql = BASE.read_text(encoding="utf-8").lower()
hardening = HARDENING.read_text(encoding="utf-8").lower()

required = {
    "coach profiles": "create table if not exists public.coach_profiles",
    "disciplines": "create table if not exists public.coach_profile_disciplines",
    "credentials": "create table if not exists public.coach_credentials",
    "discipline enum": "create type public.professional_discipline",
    "verification enum": "create type public.credential_verification_status",
    "tenant unique": "unique (organization_id,user_id)",
    "profile rls": "alter table public.coach_profiles enable row level security",
    "discipline rls": "alter table public.coach_profile_disciplines enable row level security",
    "credential rls": "alter table public.coach_credentials enable row level security",
    "professional helper": "function private.is_org_professional(",
    "backend creator": "function public.create_coach_profile(",
    "backend only guard": "coach profile creation is backend-only",
    "immutable identity": "coach profile organization and user are immutable",
    "terminal archive": "archived coach profile is terminal",
    "service grant": "to service_role",
}
missing = [name for name, token in required.items() if token not in sql]
if missing:
    raise SystemExit("Missing F1.M1.S2 contracts: " + ", ".join(missing))

hardening_required = {
    "membership join": "join public.organization_members om",
    "active membership": "om.status='active'::public.organization_member_status",
    "optimized auth uid": "cp.user_id=(select auth.uid())",
}
missing_hardening = [name for name, token in hardening_required.items() if token not in hardening]
if missing_hardening:
    raise SystemExit("Missing F1.M1.S2 hardening: " + ", ".join(missing_hardening))

legacy_tables = (
    "profiles", "coach_clients", "client_profiles", "programs", "program_days",
    "program_exercises", "workout_sessions", "session_exercises", "set_logs", "exercises"
)
for table in legacy_tables:
    token = f"alter table public.{table}"
    if token in sql or token in hardening:
        raise SystemExit(f"F1.M1.S2 must stay additive; legacy mutation found: {token}")

for forbidden in (
    "grant insert on table public.coach_profiles to authenticated",
    "grant update on table public.coach_profiles to authenticated",
    "grant delete on table public.coach_profiles to authenticated",
    "grant insert on table public.coach_credentials to authenticated",
    "grant execute on function public.create_coach_profile(uuid,uuid,text,public.professional_discipline,public.professional_discipline[],text,integer,jsonb,jsonb,jsonb) to authenticated",
):
    if forbidden in sql or forbidden in hardening:
        raise SystemExit(f"Unsafe authenticated privilege found: {forbidden}")

print("F1.M1.S2 Coaches / Professionals contract: PASS")
print("- tenant-scoped professional identity: PASS")
print("- discipline separated from authorization: PASS")
print("- credentials verification model: PASS")
print("- active membership gate: PASS")
print("- additive legacy compatibility: PASS")
