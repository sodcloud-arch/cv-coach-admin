from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
M=ROOT/"supabase/migrations/202609190520_f1_m2_s5_org_admin_multirole.sql"
sql=M.read_text(encoding="utf-8").lower()

required=[
    "create table if not exists public.organization_member_roles",
    "create table if not exists public.organization_permission_audit",
    "organization_member_roles_one_active",
    "private.member_has_org_role_v1",
    "private.current_org_roles_v1",
    "private.current_org_role_v1",
    "private.is_org_owner_v1",
    "private.is_org_admin",
    "private.resolve_org_capabilities_v1",
    "public.get_organization_member_capabilities_v1",
    "public.set_organization_member_role_v1",
    "manage_members",
    "manage_coaches",
    "manage_clients",
    "manage_programs",
    "manage_configuration",
    "manage_billing",
    "transfer_ownership",
    "coach_clients",
    "role_granted",
    "role_revoked",
    "permission_change_audited",
    "only org_owner can grant or revoke org_admin",
    "owner role changes require the dedicated ownership transfer flow",
    "a membership must retain at least one active tenant role",
]
missing=[x for x in required if x not in sql]
if missing:
    raise SystemExit("Missing F1.M2.S5 contracts: "+", ".join(missing))

if "platform_superadmin" in sql or "platform_role_bindings" in sql:
    raise SystemExit("Tenant role mutation must not grant or modify platform roles")

if "insert into public.organization_members" in sql:
    raise SystemExit("Multi-role assignment must not duplicate membership identity")

if "before update or delete on public.organization_permission_audit" not in sql:
    raise SystemExit("Tenant permission audit must be immutable")

# The admin authority helper must derive authority from member_roles, not only legacy primary role.
start=sql.find("create or replace function private.is_org_admin")
end=sql.find("$function$;",start)
block=sql[start:end]
if "member_has_org_role_v1" not in block:
    raise SystemExit("is_org_admin must resolve authoritative multi-role assignments")
if "om.role in" in block:
    raise SystemExit("is_org_admin still depends on legacy single-role membership")

# Compatibility projection must be derived from multi-role precedence.
for role in ["owner","org_admin","coach","client"]:
    if role not in sql[sql.find("recompute_organization_member_primary_role_v1"):]:
        raise SystemExit("Missing compatibility precedence role: "+role)

print("F1.M2.S5 Org Admin contracts: PASS")
print("- tenant multi-role assignment source: PASS")
print("- ORG_ADMIN + COACH coexistence model: PASS")
print("- OWNER-only upper privilege boundary: PASS")
print("- platform roles structurally unreachable: PASS")
print("- primary legacy role is compatibility projection: PASS")
print("- tenant capability resolver: PASS")
print("- permission mutation audited: PASS")
print("- cross-tenant identity duplication prevented: PASS")
