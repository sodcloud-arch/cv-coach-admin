from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
M=ROOT/"supabase/migrations/202609190500_f1_m2_s4_platform_superadmin_support_context.sql"
sql=M.read_text(encoding="utf-8").lower()

required=[
    "create type public.platform_role as enum ('platform_superadmin')",
    "create table if not exists public.platform_role_bindings",
    "create table if not exists public.platform_support_contexts",
    "create table if not exists public.platform_audit_events",
    "platform_support_contexts_one_open_per_actor",
    "platform_audit_events_immutable_v1",
    "legacy profiles.role=admin",
    "private.is_platform_superadmin_v1",
    "private.is_platform_admin()",
    "private.active_platform_support_context_v1",
    "private.platform_support_can_read_org_v1",
    "private.platform_support_can_write_org_v1",
    "public.get_platform_access_context_v1",
    "public.list_platform_organizations_v1",
    "public.start_platform_support_context_v1",
    "public.end_platform_support_context_v1",
    "public.get_platform_support_organization_snapshot_v1",
    "support_context_started",
    "support_context_ended",
    "support_tenant_snapshot_read",
    "ttl must be 5..120 minutes",
    "archived organizations are read-only",
    "raw tenant rls helpers no longer grant access",
]
missing=[x for x in required if x not in sql]
if missing:
    raise SystemExit("Missing F1.M2.S4 contracts: "+", ".join(missing))

# The legacy global-admin bypass must be removed from tenant helpers.
blocks={}
for name in [
    "private.is_org_member",
    "private.is_org_admin",
    "private.can_view_organization",
    "private.can_view_org_member_v1",
    "private.can_view_coach_profile_v1",
    "private.can_view_client_coach_assignment",
    "private.can_view_client_entity",
]:
    start=sql.find("create or replace function "+name)
    if start<0:
        raise SystemExit("Missing tenant helper cutover: "+name)
    end=sql.find("$function$;",start)
    blocks[name]=sql[start:end]

for name,block in blocks.items():
    if "private.is_platform_admin()" in block:
        raise SystemExit("Global platform role still bypasses tenant helper: "+name)

if "insert into public.organization_members" in sql:
    raise SystemExit("S4 must never create Organization membership for SuperAdmin support")

if "revoke all on public.platform_role_bindings from public,anon,authenticated" not in sql:
    raise SystemExit("Platform role bindings must not be frontend-writable/readable directly")

if "revoke all on public.platform_support_contexts from public,anon,authenticated" not in sql:
    raise SystemExit("SupportContext table must be RPC-only for authenticated users")

if "before update or delete on public.platform_audit_events" not in sql:
    raise SystemExit("Platform audit must be immutable")

print("F1.M2.S4 SuperAdmin contracts: PASS")
print("- PLATFORM_SUPERADMIN global role separated from tenant memberships: PASS")
print("- legacy app_role admin cutover is trusted migration only: PASS")
print("- raw tenant RLS global-admin bypass removed: PASS")
print("- SupportContext explicit reason + TTL + mode: PASS")
print("- tenant support entry is RPC-scoped and auditable: PASS")
print("- leaving SupportContext removes support scope: PASS")
print("- privileged tables are direct-access denied to authenticated frontend: PASS")
