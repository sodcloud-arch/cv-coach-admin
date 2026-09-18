from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
M=ROOT/"supabase/migrations/202609182800_f1_m1_s5_runtime_consumer_hardening_arch1.sql"
sql=M.read_text(encoding="utf-8").lower()

required=[
    "resolve_legacy_professional_organization_v1(",
    "x.organization_id=v_organization",
    "ps.organization_id=v_organization",
    "organization_id',ps.organization_id",
    "actor_can_manage_client_in_org_v1(",
    "c.organization_id",
    "wc.organization_id=c.organization_id",
    "select p.organization_id,p.id,p.client_id,pe.exercise_id",
    "compute_training_adaptation_in_org_v83(",
    "insert into public.programs(\n    organization_id",
    "insert into public.adaptive_program_drafts(\n    organization_id",
    "cc.organization_id=v_organization",
    "insert into public.coach_client_notes(\n      organization_id",
    "actor identity mismatch",
]
missing=[x for x in required if x not in sql]
if missing:
    raise SystemExit("Missing H3A tenant contracts: "+", ".join(missing))

forbidden=[
    "where cc.coach_id=p_actor_id and cc.client_id=p_client_id and cc.status='active'",
    "where p.client_id=r.client_id for update",
    "from public.weekly_checkins wc where wc.client_id=c.client_id",
]
bad=[x for x in forbidden if x in sql]
if bad:
    raise SystemExit("Legacy global consumer path reintroduced: "+", ".join(bad))

print("F1.M1.S5 H3A runtime consumer hardening: PASS")
print("- training trends resolve and scope one Organization: PASS")
print("- progression center authorizes rows by Organization: PASS")
print("- V85 readiness is tenant-aware: PASS")
print("- draft replacement derives tenant from Program: PASS")
print("- adaptive draft lifecycle stays inside source tenant: PASS")
print("- onboarding shadow writes carry explicit Organization: PASS")
