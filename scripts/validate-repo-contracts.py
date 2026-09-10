from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    p = ROOT / path
    if not p.exists():
        raise SystemExit(f"required file missing: {path}")
    return p.read_text(encoding="utf-8")


def require(text: str, marker: str, label: str) -> None:
    if marker not in text:
        raise SystemExit(f"contract failed: {label}: missing {marker!r}")


def forbid(text: str, marker: str, label: str) -> None:
    if marker in text:
        raise SystemExit(f"contract failed: {label}: forbidden {marker!r}")


admin = read("index.html")
client = read("client-portal/index.html")
client_build = read("client-portal/stabilize.py")
admin_deploy = read(".github/workflows/deploy-cv-coach-admin-production.yml")
client_deploy = read(".github/workflows/deploy-cv-coach-client-production.yml")
vercel = read("vercel.json")

require(admin, "client_url:'https://cv-coach-roan.vercel.app'", "public client URL")
require(admin, "'/functions/v1/publish-program'", "secure program publication")
require(admin, "'/functions/v1/provision-client'", "client provisioning")
require(admin, "openAiGenerationComparison", "AI generation before-after comparison")
require(admin, "VER CAMBIOS", "AI comparison reopen action")
require(admin, "Rutina anterior vs nueva rutina", "AI comparison summary modal")
forbid(admin, "cv-coach-sodcloud-1237.vercel.app", "protected client domain")

for marker in (
    "sb.functions.invoke('start-workout'",
    "sb.functions.invoke('complete-workout'",
    "sb.functions.invoke('log-habit'",
    "sb.functions.invoke('log-nutrition-day'",
    "cvRestDock",
    "cvOpenTechnique",
    "client_cv_state",
):
    require(client, marker, f"client critical marker {marker}")

require(client_build, "America/Santiago", "Chile date stabilization")
require(admin_deploy, "VERCEL_CLI_VERSION: 59.13.1", "Admin pinned Vercel CLI")
require(client_deploy, "VERCEL_CLI_VERSION: 59.13.1", "client pinned Vercel CLI")
require(admin_deploy, "Verify public Admin alias", "Admin post-deploy verification")
require(client_deploy, "Verify public production alias", "client post-deploy verification")
require(vercel, "Content-Security-Policy", "Admin CSP")
require(client_deploy, "Content-Security-Policy", "client CSP")

obsolete = [
    ".github/workflows/autopilot-review-queue-patch-v2.yml",
    ".github/workflows/autopilot-review-queue-recovery-patch.yml",
    ".github/workflows/patch-admin-p0-stabilization.yml",
    ".github/workflows/pr41-physical-progress-fix.yml",
    ".github/workflows/recover-admin-source.yml",
    "scripts/patch-autopilot-review-queue.py",
    "scripts/patch-autopilot-readonly-sensitive.py",
    "scripts/patch-autopilot-deploy-after-merge.py",
]
for path in obsolete:
    if (ROOT / path).exists():
        raise SystemExit(f"obsolete repair artifact still present: {path}")

print("CV_COACH_REPO_CONTRACTS_OK")
