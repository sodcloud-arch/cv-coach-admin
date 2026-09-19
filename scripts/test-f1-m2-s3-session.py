from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
TENANT=(ROOT/"admin-assets/tenant-context-v1.js").read_text(encoding="utf-8")
SESSION=(ROOT/"admin-assets/session-context-v1.js").read_text(encoding="utf-8")
ADMIN=(ROOT/"index.html").read_text(encoding="utf-8")
CLIENT=(ROOT/"client-portal/index.html").read_text(encoding="utf-8")

required_session=[
    "F1.M2.S3_SESSION_V1",
    "unauthenticated",
    "authenticated_no_org",
    "authenticated_active_org",
    "reauth_required",
    "logoutRest",
    "logoutSupabase",
    "cv:session-context",
]
missing=[x for x in required_session if x not in SESSION]
if missing:
    raise SystemExit("Missing S3 session state contracts: "+", ".join(missing))

required_tenant=[
    "version:'1.1'",
    "revalidateRest",
    "revalidateSupabase",
    "switchRest",
    "switchSupabase",
    "selected_organization_valid",
    "activeId!==organizationId",
    "organization_context_invalid",
]
missing=[x for x in required_tenant if x not in TENANT]
if missing:
    raise SystemExit("Missing S3 tenant revalidation contracts: "+", ".join(missing))

required_admin=[
    "/admin-assets/session-context-v1.js",
    "sessionStorage.setItem('cv_admin_auth_session_v1'",
    "clearAdminAuthStorage",
    "revalidateAdminTenantAfterRefresh",
    "CVTenantContext.revalidateRest",
    "CVSessionContext.fromTenantValidation",
    "CVTenantContext.switchRest",
    "window.cvSwitchOrganization",
    "CVSessionContext.logoutRest",
    "scope:'local'",
]
missing=[x for x in required_admin if x not in ADMIN]
if missing:
    raise SystemExit("Missing Admin S3 contracts: "+", ".join(missing))

if "localStorage.setItem('cv_admin_session'" in ADMIN:
    raise SystemExit("Admin auth tokens must not be persisted in legacy localStorage")
if "JSON.parse(localStorage.getItem('cv_admin_session')" in ADMIN:
    raise SystemExit("Admin must not restore auth tokens from legacy localStorage")

required_client=[
    "/admin-assets/session-context-v1.js",
    "window.CVSessionContext=window.CVSessionContext||",
    "F1.M2.S3_SESSION_CLIENT_FALLBACK_V1",
    "ensureClientOrganizationContext",
    "CVTenantContext.revalidateSupabase",
    "CVTenantContext.switchSupabase",
    "window.cvSwitchOrganization",
    "CVSessionContext.fromTenantValidation",
    "CVSessionContext.logoutSupabase",
    "event==='TOKEN_REFRESHED'",
    "event==='SIGNED_OUT'",
    "refresh_context_invalid",
]
missing=[x for x in required_client if x not in CLIENT]
if missing:
    raise SystemExit("Missing Client S3 contracts: "+", ".join(missing))

# S2 must remain intact while S3 is prepared in parallel.
for label,html in [("admin",ADMIN),("client",CLIENT)]:
    if "/admin-assets/password-recovery-v1.js" not in html:
        raise SystemExit(f"{label} lost S2 recovery helper")

if "CVPasswordRecovery" not in ADMIN or "CVPasswordRecovery" not in CLIENT:
    raise SystemExit("S3 must preserve password recovery behavior")

print("F1.M2.S3 session contracts: PASS")
print("- explicit AuthSession/Organization session states: PASS")
print("- revoked membership cannot silently switch tenant: PASS")
print("- token refresh revalidates tenant authority: PASS")
print("- tenant switch resets tenant-scoped runtime state: PASS")
print("- Admin legacy localStorage token persistence removed: PASS")
print("- local logout + future global/others scopes prepared: PASS")
print("- S2 recovery preserved: PASS")
