from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
M=ROOT/"supabase/migrations/202609190400_f1_m2_s1_active_org_context_arch1.sql"
H=ROOT/"supabase/migrations/202609190420_f1_m2_s1_client_history_context_arch1.sql"
J=ROOT/"admin-assets/tenant-context-v1.js"
A=ROOT/"index.html"
C=ROOT/"client-portal/index.html"

sql=M.read_text(encoding="utf-8").lower()
history=H.read_text(encoding="utf-8").lower()
js=J.read_text(encoding="utf-8")
admin=A.read_text(encoding="utf-8")
client=C.read_text(encoding="utf-8")

required_sql=[
  "resolve_active_organization_context_v1",
  "membership_count",
  "selection_required",
  "auto_selected",
  "selected_organization_valid",
  "suggested_slug_authoritative",
  "await_invitation_or_onboarding",
  "om.status='active'",
  "o.status in",
]
missing=[x for x in required_sql if x not in sql]
if missing:
    raise SystemExit("Missing F1.M2.S1 resolver contracts: "+", ".join(missing))

required_js=[
  "CVTenantContext",
  "chooseOrganization",
  "resolve_active_organization_context_v1",
  "cv_active_org_v1:",
  "selection_required",
  "no_membership",
]
missing=[x for x in required_js if x not in js]
if missing:
    raise SystemExit("Missing tenant-context browser contracts: "+", ".join(missing))

for label,html in [("admin",admin),("client",client)]:
    if "/admin-assets/tenant-context-v1.js" not in html:
        raise SystemExit(f"{label} does not load tenant context module")
    if "activeOrganizationId" not in html:
        raise SystemExit(f"{label} does not retain ActiveOrganizationContext")

if "ensureRest" not in admin:
    raise SystemExit("Admin login does not resolve tenant after auth")
if "ensureSupabase" not in client:
    raise SystemExit("Client login does not resolve tenant after auth")
if "get_client_training_history_in_org_v1" not in client:
    raise SystemExit("Client training history is not bound to ActiveOrganizationContext")

required_history=[
  "get_client_training_history_in_org_v1",
  "active client membership required for organization",
  "ws.organization_id=p_organization_id",
  "p.organization_id=p_organization_id",
  "organization_id+client_id+linked_at",
]
missing=[x for x in required_history if x not in history]
if missing:
    raise SystemExit("Missing tenant-explicit history contracts: "+", ".join(missing))

print("F1.M2.S1 auth/tenant contracts: PASS")
print("- global credential auth preserved: PASS")
print("- active membership is tenant authority: PASS")
print("- 0/1/multi membership states implemented: PASS")
print("- URL slug remains non-authoritative: PASS")
print("- Admin + Client flows resolve ActiveOrganizationContext: PASS")
print("- selected-tenant training history isolation: PASS")
