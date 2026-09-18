from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
M=ROOT/"supabase/migrations/202609182730_f1_m1_s5_intelligence_pilot_scope_arch1.sql"
sql=M.read_text(encoding="utf-8").lower()

required=[
    "add column if not exists organization_id uuid",
    "coach_intelligence_pilots_coach_same_org",
    "coach_intelligence_pilots_client_same_org",
    "uq_coach_intelligence_pilots_org_external",
    "guard_coach_intelligence_pilot_tenant_v1",
    "private.is_org_professional(organization_id,coach_id)",
    "cv12_cutover_audit_v90_pilot_same_org",
    "guard_cv12_cutover_audit_tenant_v1",
    "pilot not available in this organization",
    "actor_can_manage_client_in_org_v1(",
    "'organization_id',v_pilot.organization_id",
    "revoke all on function public.refresh_cv12_pilot_baseline_v87(uuid)",
]
missing=[x for x in required if x not in sql]
if missing:
    raise SystemExit("Missing H2 tenant contracts: "+", ".join(missing))

forbidden=[
    "coach_intelligence_pilots_external_uniq on public.coach_intelligence_pilots using btree (coach_id",
    "where id=p_pilot_id; if p.id is null",
]
bad=[x for x in forbidden if x in sql]
if bad:
    raise SystemExit("Legacy pilot contract reintroduced: "+", ".join(bad))

print("F1.M1.S5 H2 intelligence pilot tenant scope: PASS")
print("- Pilot root has canonical Organization identity: PASS")
print("- Coach/client pilot identities are same-tenant constrained: PASS")
print("- CV12 cutover audit inherits pilot Organization: PASS")
print("- Browser pilot link/unlink/plan/cutover paths are tenant-authorized: PASS")
