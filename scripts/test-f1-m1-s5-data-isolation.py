from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
M1 = ROOT / "supabase/migrations/202609181000_f1_m1_s5_canonical_data_isolation_arch1.sql"
M2 = ROOT / "supabase/migrations/202609181020_f1_m1_s5_business_roots_isolation_arch1.sql"
M3 = ROOT / "supabase/migrations/202609181030_f1_m1_s5_business_roots_resolver_fix_arch1.sql"
M4 = ROOT / "supabase/migrations/202609181040_f1_m1_s5_training_graph_isolation_arch1.sql"

for path in (M1, M2, M3, M4):
    if not path.exists():
        raise SystemExit(f"Missing canonical S5 migration: {path.name}")

canonical = M1.read_text(encoding="utf-8").lower()
roots = M2.read_text(encoding="utf-8").lower()
resolver = M3.read_text(encoding="utf-8").lower()
training = M4.read_text(encoding="utf-8").lower()

required_canonical = [
    "coach_profile_disciplines_same_org",
    "coach_credentials_same_org",
    "coach_profiles_member_same_org",
    "clients_user_member_same_org",
    "client_coach_assignments_assigned_by_member_same_org",
    "grant update (",
]
required_roots = [
    "programs_client_same_org",
    "workout_sessions_program_same_org_client",
    "progression_suggestions_source_session_same_org_client",
    "function private.can_view_client_in_org(",
    "function private.can_manage_client_in_org(",
]
required_resolver = [
    "select count(*) into v_count",
    "legacy client belongs to multiple organizations; organization_id is required",
]
required_training = [
    "alter table public.program_days\n  add column if not exists organization_id uuid",
    "alter table public.program_exercises\n  add column if not exists organization_id uuid",
    "alter table public.session_exercises\n  add column if not exists organization_id uuid",
    "alter table public.set_logs\n  add column if not exists organization_id uuid",
    "program_days_program_same_org",
    "program_exercises_day_same_org",
    "workout_sessions_program_day_same_org",
    "session_exercises_workout_same_org",
    "session_exercises_program_exercise_same_org",
    "session_exercises_previous_session_same_org",
    "session_exercises_previous_exercise_same_org",
    "session_exercises_progression_same_org",
    "set_logs_session_exercise_same_org",
    "set_logs_reference_same_org",
    "sync_program_day_organization_v1",
    "sync_program_exercise_organization_v1",
    "sync_session_exercise_organization_v1",
    "sync_set_log_organization_v1",
    "private.can_view_client_in_org(p.organization_id,p.client_id)",
    "private.can_manage_client_in_org(p.organization_id,p.client_id)",
    "private.can_manage_session_exercise(session_exercise_id)",
]

for label, body, required in (
    ("canonical", canonical, required_canonical),
    ("roots", roots, required_roots),
    ("resolver", resolver, required_resolver),
    ("training", training, required_training),
):
    missing = [token for token in required if token not in body]
    if missing:
        raise SystemExit(f"Missing {label} S5 contracts: " + ", ".join(missing))

for forbidden in (
    "grant truncate",
    "grant trigger",
    "grant references",
    "grant all privileges on table public.programs to authenticated",
    "grant all privileges on table public.workout_sessions to authenticated",
):
    if forbidden in canonical or forbidden in roots or forbidden in training:
        raise SystemExit(f"Unsafe authenticated privilege in S5: {forbidden}")

if "min(c.organization_id)" in resolver:
    raise SystemExit("UUID resolver regression reintroduced")

if "private.can_manage_client(private.session_exercise_client_id" in training:
    raise SystemExit("Legacy global-user set-log authorization reintroduced")

print("F1.M1.S5 data isolation contract: PASS")
print("- canonical Organization/Coach/Client boundaries: PASS")
print("- business roots tenant-scoped: PASS")
print("- ambiguous legacy tenant resolution denied: PASS")
print("- training graph carries immutable organization_id: PASS")
print("- same-tenant composite FK chain: PASS")
print("- set-log mutation authorization is tenant-aware: PASS")
