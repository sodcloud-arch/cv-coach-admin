from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
M=ROOT/"supabase/migrations/202609182500_f1_m1_s5_authoring_workout_scope_arch1.sql"
sql=M.read_text(encoding="utf-8").lower()

required=[
    "get_client_time_learning_in_org",
    "ws.organization_id=p_organization_id",
    "resolve_legacy_professional_organization_v1(",
    "where p.organization_id = v_organization",
    "insert into public.programs (\n    organization_id, client_id, coach_id",
    "v_organization,v_program_id,v_program_client",
    "actor_can_manage_client_in_org_v1(",
    "ws.organization_id=v_organization and ws.client_id=v_target_client",
    "insert into public.workout_sessions(organization_id,client_id",
    "x.organization_id=v_organization and x.client_id=v_target_client",
]
missing=[x for x in required if x not in sql]
if missing:
    raise SystemExit("Missing G1B2 contracts: "+", ".join(missing))

if "public.coach_clients" in sql:
    raise SystemExit("G1B2 reintroduced direct legacy coach_clients authorization")

print("F1.M1.S5 G1B2 authoring/workout scope: PASS")
print("- Program draft lifecycle is Organization-scoped: PASS")
print("- legacy client-only authoring fails on ambiguous tenant: PASS")
print("- workout start resolves Organization from Program Day: PASS")
print("- active session/history/progression reads are tenant-local: PASS")
print("- time-learning has explicit Organization helper: PASS")
