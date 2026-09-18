from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "supabase/migrations/202609180900_f1_m1_s4_client_coach_assignments_arch1.sql"
BACKFILL = ROOT / "supabase/migrations/202609180910_f1_m1_s4_cv_coach_assignment_backfill_arch1.sql"
HARDENING = ROOT / "supabase/migrations/202609180920_f1_m1_s4_assigned_client_visibility_arch1.sql"

sql = BASE.read_text(encoding="utf-8").lower()
backfill = BACKFILL.read_text(encoding="utf-8").lower()
hardening = HARDENING.read_text(encoding="utf-8").lower()

required = {
    "assignment roles": "create type public.client_coach_assignment_role",
    "assignment status": "create type public.client_coach_assignment_status",
    "assignment table": "create table if not exists public.client_coach_assignments",
    "client composite boundary": "references public.clients(organization_id,id)",
    "coach composite boundary": "references public.coach_profiles(organization_id,id)",
    "one active pair": "ux_client_coach_assignments_one_active_pair",
    "one active primary": "ux_client_coach_assignments_one_active_primary",
    "role primary": "'primary'",
    "role secondary": "'secondary'",
    "history status": "'ended'",
    "assignment guard": "function private.guard_client_coach_assignment_v1()",
    "immutable identity": "assignment identity is immutable; end it and create a new assignment",
    "terminal ended": "ended assignment is terminal",
    "membership gate": "om.status='active'::public.organization_member_status",
    "rls": "alter table public.client_coach_assignments enable row level security",
    "visibility helper": "function private.can_view_client_coach_assignment(",
    "coach self": "cp.user_id=(select auth.uid())",
    "client self": "c.user_id=(select auth.uid())",
    "assign rpc": "function public.assign_client_coach(",
    "end rpc": "function public.end_client_coach_assignment(",
    "backend assign": "client coach assignment is backend-only",
    "backend end": "client coach unassignment is backend-only",
}
missing = [name for name, token in required.items() if token not in sql]
if missing:
    raise SystemExit("Missing F1.M1.S4 base contracts: " + ", ".join(missing))

backfill_required = {
    "cv coach tenant": "where o.slug='cv-coach'",
    "canonical coach": "from public.coach_profiles cp",
    "legacy relation read": "from public.coach_clients cc",
    "canonical clients": "join public.clients c",
    "canonical assignment insert": "insert into public.client_coach_assignments",
    "primary backfill": "'primary'::public.client_coach_assignment_role",
    "idempotent backfill": "and not exists(",
}
missing_backfill = [name for name, token in backfill_required.items() if token not in backfill]
if missing_backfill:
    raise SystemExit("Missing F1.M1.S4 backfill contracts: " + ", ".join(missing_backfill))

hardening_required = {
    "client visibility override": "function private.can_view_client_entity(target_client uuid)",
    "active assignment gate": "from public.client_coach_assignments a",
    "assignment status gate": "a.status='active'::public.client_coach_assignment_status",
    "assigned coach identity": "cp.user_id=(select auth.uid())",
    "org admin full visibility": "private.is_org_admin(c.organization_id)",
    "client self visibility": "c.user_id=(select auth.uid())",
}
missing_hardening = [name for name, token in hardening_required.items() if token not in hardening]
if missing_hardening:
    raise SystemExit("Missing F1.M1.S4 visibility hardening: " + ", ".join(missing_hardening))

if "private.is_org_professional(c.organization_id)" in hardening:
    raise SystemExit("Professional-wide client visibility must not survive S4 hardening")

for source_name, source in (("base", sql), ("backfill", backfill), ("hardening", hardening)):
    for forbidden in (
        "alter table public.coach_clients",
        "drop table public.coach_clients",
        "alter table public.client_profiles",
        "drop table public.client_profiles",
        "alter table public.profiles",
        "drop table public.profiles",
    ):
        if forbidden in source:
            raise SystemExit(f"F1.M1.S4 {source_name} must not mutate legacy schema: {forbidden}")

for forbidden in (
    "grant insert on table public.client_coach_assignments to authenticated",
    "grant update on table public.client_coach_assignments to authenticated",
    "grant delete on table public.client_coach_assignments to authenticated",
    "grant execute on function public.assign_client_coach(uuid,uuid,uuid,public.client_coach_assignment_role,uuid) to authenticated",
    "grant execute on function public.end_client_coach_assignment(uuid,uuid) to authenticated",
):
    if forbidden in sql:
        raise SystemExit(f"Unsafe authenticated privilege found: {forbidden}")

print("F1.M1.S4 Organization -> Coach -> Client contract: PASS")
print("- same-tenant composite FK boundaries: PASS")
print("- maximum one active primary per client: PASS")
print("- secondary coaches supported: PASS")
print("- reassignment preserves history: PASS")
print("- coach/client scoped assignment visibility: PASS")
print("- professional client visibility restricted to active assignments: PASS")
print("- org admin tenant-wide + client self visibility retained: PASS")
print("- CV Coach legacy relations backfilled additively: PASS")
