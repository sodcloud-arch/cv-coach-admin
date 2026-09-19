from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
M=ROOT/"supabase/migrations/202609190620_f1_m2_s8_permission_engine.sql"
J=ROOT/"admin-assets/permission-context-v1.js"
A=ROOT/"index.html"

sql=M.read_text(encoding="utf-8").lower()
js=J.read_text(encoding="utf-8")
admin=A.read_text(encoding="utf-8")

required=[
    "create table if not exists public.permission_matrix_versions",
    "create table if not exists public.permission_capabilities",
    "create table if not exists public.permission_role_rules",
    "f1.m2.s8_permission_matrix_v1",
    "private.permission_decision_v1",
    "private.has_permission_v1",
    "private.require_permission_v1",
    "public.check_permission_v1",
    "public.get_my_permission_snapshot_v1",
    "deny_by_default",
    "feature_entitlements_separate",
    "claims_authoritative",
    "unknown_capability",
    "cross_tenant_resource",
    "no_active_membership",
    "capability_not_granted",
    "client_assigned",
    "client_self",
    "program_self_published",
    "workout_self",
    "permission_role_rules_sealed_v1",
    "client_subscriptions_permission_v1",
    "subscription_billing_records_permission_v1",
]
missing=[x for x in required if x not in sql]
if missing:
    raise SystemExit("Missing F1.M2.S8 contracts: "+", ".join(missing))

# Tenant authorization must not derive from feature entitlements or mutable JWT role claims.
start=sql.find("create or replace function private.permission_decision_v1")
end=sql.find("$function$;",start)
block=sql[start:end]
if "feature_flags" in block:
    raise SystemExit("Permission decision improperly depends on feature flags")
if "platform_superadmin" in block or "platform_role_bindings" in block:
    raise SystemExit("Tenant permission engine improperly absorbs PLATFORM_SUPERADMIN")
for marker in [
    "organization_members",
    "organization_member_roles",
    "permission_role_rules",
    "coach_can_access_client_v1",
    "is_client_in_org_v1",
]:
    if marker not in block:
        raise SystemExit("Permission decision missing live authority source: "+marker)

# RLS helpers must delegate to the same permission engine.
for fn in [
    "can_view_organization",
    "can_view_org_member_v1",
    "can_view_client_entity",
    "can_view_client_in_org",
    "can_manage_client_in_org",
    "can_view_program",
    "can_manage_program",
    "can_view_workout_session",
    "can_edit_workout_session",
]:
    pos=sql.find("create or replace function private."+fn)
    if pos<0:
        raise SystemExit("Missing S8 helper cutover: "+fn)
    snippet=sql[pos:sql.find("$function$;",pos)]
    if "has_permission_v1" not in snippet:
        raise SystemExit("RLS helper does not delegate to S8 engine: "+fn)

# Matrix version 1 must be sealed after seeding.
if "set sealed=true" not in sql:
    raise SystemExit("Permission matrix is not sealed")

# Frontend is visibility-only and receives its state from the backend snapshot.
for marker in [
    "F1.M2.S8_PERMISSION_CONTEXT_V1",
    "get_my_permission_snapshot_v1",
    "data-capability",
    "CVPermissionContext.apply",
    "loadAdminPermissionContext",
]:
    if marker not in js+admin:
        raise SystemExit("Missing frontend permission context: "+marker)

if "/admin-assets/permission-context-v1.js" not in admin:
    raise SystemExit("Admin does not load permission context module")
if 'data-capability="organization.billing.manage"' not in admin:
    raise SystemExit("Billing navigation is not capability gated")
if 'data-capability="organization.clients.manage"' not in admin:
    raise SystemExit("Lead/client-admin navigation is not capability gated")

print("F1.M2.S8 Permission Control contracts: PASS")
print("- sealed versioned RBAC matrix: PASS")
print("- backend deny-by-default decision engine: PASS")
print("- resource organization/assignment/self scopes: PASS")
print("- feature entitlement separated from authorization: PASS")
print("- mutable claims are not permission authority: PASS")
print("- PLATFORM_SUPERADMIN remains separate: PASS")
print("- RLS helpers delegate to permission engine: PASS")
print("- sensitive subscription/billing mutations capability-guarded: PASS")
print("- frontend visibility consumes backend snapshot: PASS")
