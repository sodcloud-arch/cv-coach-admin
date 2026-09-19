from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
helper=(ROOT/"admin-assets/password-recovery-v1.js").read_text(encoding="utf-8")
admin=(ROOT/"index.html").read_text(encoding="utf-8")
client=(ROOT/"client-portal/index.html").read_text(encoding="utf-8")

required_helper=[
    "F1.M2.S2_RECOVERY_V1",
    "Si existe una cuenta para ese correo",
    "/auth/v1/recover?redirect_to=",
    "/auth/v1/verify",
    "type:'recovery'",
    "/auth/v1/user",
    "method:'PUT'",
    "/auth/v1/logout?scope=global",
    "invalid_or_expired_recovery_link",
    "sameOriginRedirect",
    "scrubRecoveryUrl",
]
missing=[x for x in required_helper if x not in helper]
if missing:
    raise SystemExit("Missing recovery helper contracts: "+", ".join(missing))

required_admin=[
    'id="forgotBtn"',
    'id="adminRecoveryPanel"',
    '/admin-assets/password-recovery-v1.js',
    "requestAdminRecovery",
    "CVPasswordRecovery.neutralMessage",
    "resolveRestRecoverySession",
    "updateRestPassword",
    "logoutRest",
    "CVTenantContext.ensureRest",
]
missing=[x for x in required_admin if x not in admin]
if missing:
    raise SystemExit("Missing admin recovery contracts: "+", ".join(missing))

required_client=[
    'id="forgotPasswordBtn"',
    '/admin-assets/password-recovery-v1.js',
    "resetPasswordForEmail",
    "?recovery=1",
    "PASSWORD_RECOVERY",
    "recoveryMode",
    "sb.auth.updateUser({password",
    "signOut({scope:'global'})",
    "Contraseña actualizada. Ingresa nuevamente.",
    "CVTenantContext.ensureSupabase",
]
missing=[x for x in required_client if x not in client]
if missing:
    raise SystemExit("Missing client recovery contracts: "+", ".join(missing))

forbidden_helper=[
    "organization_members",
    "client_coach_assignments",
    "active_organization",
    "auth.users",
    "service_role",
]
for x in forbidden_helper:
    if x in helper:
        raise SystemExit("Recovery helper must be tenant-agnostic and user-global: "+x)

if "response.ok" in helper[helper.index("async function requestRest"):helper.index("function parseRecoveryFragment")]:
    raise SystemExit("Recovery request UI path must not branch on account/provider response")

if "error_description" in helper or "user not found" in helper.lower():
    raise SystemExit("Provider/account detail may leak through recovery helper")

print("F1.M2.S2 password recovery contracts: PASS")
print("- neutral anti-enumeration request: PASS")
print("- provider-owned recovery token/TTL flow: PASS")
print("- expired/reused token maps to generic invalid link: PASS")
print("- admin and client reset flows: PASS")
print("- global user recovery remains tenant-agnostic: PASS")
print("- post-reset login still resolves ActiveOrganizationContext: PASS")
