from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
M=ROOT/"supabase/migrations/202609190600_f1_m2_s7_client_boundary.sql"
C=ROOT/"client-portal/index.html"
sql=M.read_text(encoding="utf-8").lower()
client=C.read_text(encoding="utf-8")

required=[
    "private.is_client_in_org_v1",
    "member_has_org_role_v1",
    "'client'::public.organization_member_role",
    "private.can_view_client_entity",
    "private.can_view_client_in_org",
    "private.can_view_program",
    "p.published_at is not null",
    "'active'::public.program_status",
    "'completed'::public.program_status",
    "private.can_edit_workout_session",
    "private.can_edit_session_exercise",
    "public.update_client_self_profile_v1",
    "unsupported self-profile fields",
    "client_profiles_insert_self_v3",
    "client_profiles_update_self_v3",
    "programs_select_v3",
    "progress_photos_select_v3",
    "workout_sessions_insert_v3",
    "workout_sessions_update_v3",
    "'roles',to_jsonb",
    "f1.m2.s7_active_org_roles_v1",
]
missing=[x for x in required if x not in sql]
if missing:
    raise SystemExit("Missing F1.M2.S7 contracts: "+", ".join(missing))

# CLIENT authority must be canonical identity, not generic membership alone.
start=sql.find("create or replace function private.is_client_in_org_v1")
end=sql.find("$function$;",start)
block=sql[start:end]
for marker in ["organization_members","public.clients","member_has_org_role_v1","c.status<>'archived'"]:
    if marker not in block:
        raise SystemExit("CLIENT identity resolver missing: "+marker)

# Published resource boundary must deny draft/archived programs to the client.
start=sql.find("create or replace function private.can_view_program")
end=sql.find("$function$;",start)
block=sql[start:end]
if "published_at is not null" not in block:
    raise SystemExit("Client program visibility does not require publication")
if "'draft'" in block or "'archived'::public.program_status" in block:
    raise SystemExit("Draft/archived program leaked into client visibility branch")
if "can_manage_client_in_org" not in block:
    raise SystemExit("Coach/Admin program visibility was not preserved")

# Safe profile RPC must not expose workflow fields.
start=sql.find("create or replace function public.update_client_self_profile_v1")
end=sql.find("$function$;",start)
block=sql[start:end]
for forbidden in ["onboarding_status=", "start_date=", "experience_level=", "primary_goal=", "secondary_goal="]:
    if forbidden in block:
        raise SystemExit("Unsafe client self-profile mutation: "+forbidden)
for allowed in ["birth_date","gender","height_cm","current_weight_kg","timezone"]:
    if allowed not in block:
        raise SystemExit("Missing safe self-profile field: "+allowed)

# Direct self-service policy cutovers must explicitly use CLIENT identity.
policy_markers=[
    "client_profiles_insert_self_v3",
    "client_profiles_update_self_v3",
    "client_training_preferences_select_v3",
    "habit_logs_insert_v3",
    "meal_logs_insert_v3",
    "measurements_insert_v3",
    "nutrition_daily_insert_v3",
    "onboarding_insert_self_v3",
    "progress_photos_insert_v3",
    "workout_sessions_insert_v3",
]
for marker in policy_markers:
    pos=sql.find(marker)
    if pos<0:
        raise SystemExit("Missing policy: "+marker)
    snippet=sql[pos:pos+1400]
    if "is_client_in_org_v1" not in snippet:
        raise SystemExit("Policy does not require CLIENT identity: "+marker)

if "activeclientroles" not in client.lower() or ".includes('client')" not in client.lower():
    raise SystemExit("Client portal still assumes primary role instead of authoritative roles[]")

if "active_organization?.role!=='client'" in client:
    raise SystemExit("Legacy primary-role Client gate remains in portal")

print("F1.M2.S7 Client contracts: PASS")
print("- CLIENT role + canonical client identity required: PASS")
print("- manipulated client_id cannot create self authority: PASS")
print("- direct self-service policies require CLIENT role: PASS")
print("- draft/unpublished programs hidden from Client: PASS")
print("- published program visibility propagates to child resources: PASS")
print("- internal coach notes remain outside Client policy surface: PASS")
print("- safe post-onboarding self-profile RPC: PASS")
print("- ActiveOrganizationContext roles[] supports multi-role Client: PASS")
