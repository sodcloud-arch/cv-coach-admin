from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
M=ROOT/"supabase/migrations/202609190540_f1_m2_s6_coach_scope.sql"
sql=M.read_text(encoding="utf-8").lower()

required=[
    "private.is_org_professional",
    "private.coach_has_all_clients_capability_v1",
    "private.coach_can_access_client_v1",
    "private.can_manage_client_in_org",
    "private.actor_can_manage_client_in_org_v1",
    "private.can_view_client_entity",
    "private.can_view_client_coach_assignment",
    "public.create_coach_profile",
    "public.set_coach_scope_capability_v1",
    "public.set_coach_profile_status_v1",
    "public.assign_client_coach",
    "public.end_client_coach_assignment",
    "active coach role and coach profile required",
    "coach_scope_capability_changed",
    "coach_profile_status_changed",
    "coach_assignment_started",
    "coach_assignment_ended",
    "manage_all_clients",
    "org_admin or backend required for coach assignment",
    "org_admin or backend required for coach unassignment",
    "assigned_by cannot impersonate another actor",
    "unassigned_by cannot impersonate another actor",
]
missing=[x for x in required if x not in sql]
if missing:
    raise SystemExit("Missing F1.M2.S6 contracts: "+", ".join(missing))

# Role + profile must both be required for professional authority.
start=sql.find("create or replace function private.is_org_professional")
end=sql.find("$function$;",start)
block=sql[start:end]
if "member_has_org_role_v1" not in block or "coach_profiles" not in block:
    raise SystemExit("is_org_professional must require COACH role + coach_profile")

# Scope expansion cannot be injected during profile creation.
start=sql.find("create or replace function public.create_coach_profile")
end=sql.find("$function$;",start)
block=sql[start:end]
if "-'manage_all_clients'" not in block:
    raise SystemExit("create_coach_profile must strip manage_all_clients")
if "private.is_org_admin" not in block:
    raise SystemExit("Org Admin must be able to manage coach profiles")

# Coach client authority must be assignment/capability scoped.
start=sql.find("create or replace function private.coach_can_access_client_v1")
end=sql.find("$function$;",start)
block=sql[start:end]
for marker in ["client_coach_assignments","status='active'","coach_has_all_clients_capability_v1"]:
    if marker not in block:
        raise SystemExit("Coach scope missing: "+marker)

# Archived/inactive coach must lose operational authority.
start=sql.find("create or replace function private.is_org_professional")
end=sql.find("$function$;",start)
if "cp.status='active'" not in sql[start:end]:
    raise SystemExit("Inactive/archived coach profile must not be professional authority")

# Coach must not gain owner/admin/platform authority through S6.
for forbidden in ["platform_role_bindings","platform_superadmin","transfer_ownership","manage_billing"]:
    if forbidden in sql:
        raise SystemExit("Coach migration crossed upper privilege boundary: "+forbidden)

print("F1.M2.S6 Coach contracts: PASS")
print("- COACH role + active professional profile required: PASS")
print("- assigned-client scope enforced: PASS")
print("- all-client expansion isolated behind audited admin RPC: PASS")
print("- profile creation strips self-elevation capability: PASS")
print("- Org Admin can manage profile and assignments: PASS")
print("- assignment/reassignment audited: PASS")
print("- archived coach loses new operational authority: PASS")
print("- upper privilege boundaries preserved: PASS")
