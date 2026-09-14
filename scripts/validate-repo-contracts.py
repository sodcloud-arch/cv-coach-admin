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
edge_program = read("supabase/functions/generate-ai-program/index.ts")
programmable_exercise_v81 = read("supabase/migrations/202609132330_programmable_exercise_contract_v81.sql")
adaptive_progression_v83 = read("supabase/migrations/202609140300_adaptive_progression_system_v83.sql")
progression_admin_v83 = read("admin-assets/cv-progression-admin-v83.js")
progression_patch_v83 = read("scripts/upgrade_admin_progression_v83.py")

require(admin, "client_url:'https://cv-coach-roan.vercel.app'", "public client URL")
require(admin, "'/functions/v1/publish-program'", "secure program publication")
require(admin, "'/functions/v1/provision-client'", "client provisioning")
require(admin, "openAiGenerationComparison", "AI generation before-after comparison")
require(admin, "VER CAMBIOS", "AI comparison reopen action")
require(admin, "Rutina anterior vs nueva rutina", "AI comparison summary modal")
require(admin, "AUDITOR DE VOLUMEN SEMANAL", "deterministic weekly volume audit UI")
require(admin, "aiVolumeAuditHtml", "volume audit renderer")
require(admin, "AUDITOR DE TIEMPO Y FRECUENCIA", "hard schedule audit UI")
require(admin, "Disponibilidad de entrenamiento", "current training availability UI")
require(admin, "Restricciones mecánicas", "structured mechanical constraint UI")
require(admin, "CONTROL DE CALIDAD CV COACH", "program quality audit UI")
require(admin, "PROGRAMACIÓN IA · PREFLIGHT", "AI preflight quality summary")
require(admin, "replace_client_training_constraints_backend", "constraint management RPC")
require(admin, "get_program_quality_audit_backend", "quality audit RPC")
require(admin, "set_client_training_schedule_backend", "current training availability RPC")
require(admin, "aiScheduleAuditHtml", "schedule audit renderer")
require(edge_program, "cv-volume-audit-v1", "volume audit contract version")
require(edge_program, "buildVolumeAudit", "deterministic volume audit builder")
require(edge_program, "cv-schedule-audit-v1", "hard schedule audit contract version")
require(edge_program, "buildScheduleAudit", "hard schedule audit builder")
require(edge_program, "schedule_preferences", "current schedule preference AI context")
require(edge_program, "training_constraints", "structured training constraints context")
require(edge_program, "mechanical_exposures", "exercise exposure safety metadata")
require(edge_program, "cv-safety-audit-v1", "deterministic safety audit")
require(edge_program, "time_learning", "client-specific time learning")
require(edge_program, "weekly_availability", "legacy onboarding frequency alias")
require(edge_program, "session_duration_minutes", "legacy onboarding duration alias")

# V81: exercise programming safety is enforced below every UI/AI caller.
require(programmable_exercise_v81, "alter column active set default false", "new exercises default to staging")
require(programmable_exercise_v81, "private.is_exercise_programmable", "canonical programmable exercise predicate")
require(programmable_exercise_v81, "e.active = true", "programmable active requirement")
require(programmable_exercise_v81, "r.qa_status = 'approved'", "programmable QA requirement")
require(programmable_exercise_v81, "trg_guard_exercise_active_state_v81", "exercise activation invariant trigger")
require(programmable_exercise_v81, "trg_guard_exercise_review_state_v81", "exercise QA invariant trigger")
require(programmable_exercise_v81, "trg_program_exercise_programmable_v81", "program assignment hard gate")
require(programmable_exercise_v81, "Exercise is used by an active or draft program; replace it there before deactivation", "in-use deactivation guard")
require(programmable_exercise_v81, "V81 invariant failed: draft/active program contains a non-programmable exercise", "migration drift assertion")

# V83: adaptive progression remains deterministic, bounded and coach-controlled.
for marker, label in (
    ("private.progression_recommendation_v83", "canonical reps/time progression engine"),
    ("'build_time'", "time progression action"),
    ("training_adaptation_reviews", "adaptive block review persistence"),
    ("deload_recommended", "deload recommendation state"),
    ("private.compute_training_adaptation_v83", "adaptive block-state engine"),
    ("trg_progression_suggestion_guard_v83", "review hard guard"),
    ("review_progression_suggestion_v83", "audited progression review RPC"),
    ("Modified load exceeds V83 safe ceiling", "coach load ceiling"),
    ("Modified duration exceeds V83 safe bounds", "coach duration ceiling"),
    ("trg_attach_time_progression_v83", "time progression session attachment"),
    ("trg_apply_time_progression_to_set_v83", "time suggestion application"),
    ("get_progression_center_v83", "coach progression center RPC"),
):
    require(adaptive_progression_v83, marker, label)
for marker, label in (
    ("CV_ADMIN_PROGRESSION_V83_READY", "V83 Admin module"),
    ("review_progression_suggestion_v83", "V83 Admin review flow"),
    ("DELOAD RECOMENDADO", "V83 Admin deload state"),
    ("AUMENTAR TIEMPO", "V83 Admin time progression"),
):
    require(progression_admin_v83, marker, label)
require(progression_patch_v83, 'data-v="progression"', "V83 Admin navigation patch")
require(admin_deploy, "upgrade_admin_progression_v83.py", "V83 Admin deploy build")
require(admin_deploy, "PUBLIC_ADMIN_V83_OK", "V83 public deploy verification")

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

# CV Coach client workout v32
require(client, "cv-client-workout-v32", "client workout semantic colors")
require(client, "cvRestVisualV32", "client visible rest timer")
require(client, "window.cvExercises=cvExercises", "client workout canonical exercise accessor")
require(client, "cv-client-semantic-v33", "client semantic palette v33")

require(client, "cv-client-semantic-v34", "client final semantic cleanup")
require(client, "cv-client-workout-v35", "large red rest countdown and execution CTA styles")
require(client, "cvExecutionBtnV35", "explicit client exercise execution button")
require(client, "VER EJECUCIÓN", "client execution CTA copy")
