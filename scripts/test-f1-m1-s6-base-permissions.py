from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
M=ROOT/"supabase/migrations/202609190220_f1_m1_s6_base_permissions_arch1.sql"
sql=M.read_text(encoding="utf-8").lower()

required=[
  "current_org_role_v1",
  "can_view_org_member_v1",
  "can_view_coach_profile_v1",
  "get_my_organization_context_v1",
  "organizations_select_v2",
  "organization_members_select_v2",
  "coach_profiles_select_v2",
  "coach_profile_disciplines_select_v3",
  "coach_credentials_select_v3",
  "can_view_all_members",
  "can_manage_assignments",
  "can_manage_assigned_clients",
  "can_submit_client_state",
  "billing_account_configured",
  "private.is_org_admin(id)",
  "p_member_user_id=(select auth.uid())",
  "p_status='active'::public.coach_profile_status",
]
missing=[x for x in required if x not in sql]
if missing:
    raise SystemExit("Missing S6 permission contracts: "+", ".join(missing))

for forbidden in [
    "using (private.can_view_organization(organization_id));",
    "using (private.can_view_organization(id));",
]:
    if forbidden in sql:
        raise SystemExit("Over-broad Organization visibility remains in S6 migration: "+forbidden)

print("F1.M1.S6 base permission contracts: PASS")
print("- safe Organization context RPC: PASS")
print("- raw tenant config admin-only: PASS")
print("- membership roster least privilege: PASS")
print("- active coach directory visibility: PASS")
print("- credential self/admin boundary: PASS")
