from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EDGE = ROOT / "supabase/functions/generate-ai-program/index.ts"
ADMIN = ROOT / "index.html"
CONTRACTS = ROOT / "scripts/validate-repo-contracts.py"

edge = EDGE.read_text(encoding="utf-8")
admin = ADMIN.read_text(encoding="utf-8")
contracts = CONTRACTS.read_text(encoding="utf-8")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 anchor, found {count}")
    return text.replace(old, new, 1)

# 1) Canonicalize onboarding aliases so old/new onboarding schemas both reach the model.
old_onboarding = '''  const onboarding = compactRecord(root.onboarding, [
    "training_days_per_week",
    "session_minutes",
    "equipment",
    "preferred_training_days",
    "pain_injuries",
    "limitations",
    "sleep_hours",
    "daily_steps_baseline",
  ]);'''
new_onboarding = '''  const onboardingSource = isObject(root.onboarding) ? root.onboarding : {};
  const onboarding = compactRecord(onboardingSource, [
    "training_days_per_week",
    "weekly_availability",
    "session_minutes",
    "session_duration_minutes",
    "equipment",
    "preferred_training_days",
    "pain_injuries",
    "limitations",
    "sleep_hours",
    "daily_steps_baseline",
  ]);
  if (onboarding.training_days_per_week === undefined && onboardingSource.weekly_availability !== undefined) {
    onboarding.training_days_per_week = onboardingSource.weekly_availability;
  }
  if (onboarding.session_minutes === undefined && onboardingSource.session_duration_minutes !== undefined) {
    onboarding.session_minutes = onboardingSource.session_duration_minutes;
  }'''
edge = replace_once(edge, old_onboarding, new_onboarding, "onboarding canonical aliases")

# 2) Deterministic schedule/time audit. This is independent from the model's own estimate.
schedule_helpers = r'''
function strictInteger(value: unknown): number | null {
  if (value === null || value === undefined || value === "") return null;
  const n = Number(value);
  return Number.isInteger(n) ? n : null;
}

function tempoSecondsPerRep(value: unknown): number {
  const text = cleanText(value, 40);
  if (!text) return 3;
  const compact = text.replace(/\s+/g, "");
  if (/^\d{4}$/.test(compact)) {
    const sum = compact.split("").reduce((acc, digit) => acc + Number(digit), 0);
    return Math.min(10, Math.max(1, sum || 3));
  }
  const parts = compact.match(/\d+(?:\.\d+)?/g)?.map(Number).filter(Number.isFinite) ?? [];
  if (!parts.length) return 3;
  const sum = parts.slice(0, 4).reduce((acc, n) => acc + n, 0);
  return Math.min(10, Math.max(1, sum || 3));
}

function estimateDayMinutes(day: unknown): number | null {
  if (!isObject(day) || !Array.isArray(day.exercises) || !day.exercises.length) return null;
  let seconds = 240; // calentamiento / preparación general mínima
  let validExercises = 0;

  for (const rawExercise of day.exercises) {
    if (!isObject(rawExercise)) continue;
    const sets = strictInteger(rawExercise.target_sets);
    const repMin = strictInteger(rawExercise.rep_min);
    const repMax = strictInteger(rawExercise.rep_max);
    const rest = strictInteger(rawExercise.rest_seconds);
    if (sets === null || sets < 1 || repMin === null || repMax === null || rest === null) continue;

    const unit = rawExercise.prescription_unit === "seconds" ? "seconds" : "reps";
    const midpoint = (repMin + repMax) / 2;
    const workPerSet = unit === "seconds" ? midpoint : midpoint * tempoSecondsPerRep(rawExercise.tempo);
    seconds += sets * workPerSet;
    seconds += Math.max(0, sets - 1) * Math.max(0, rest);
    seconds += 60; // transición/configuración mínima por ejercicio
    validExercises += 1;
  }

  if (!validExercises) return null;
  seconds *= 1.10; // margen operacional por desplazamientos/ajustes normales
  return Math.max(1, Math.ceil(seconds / 60));
}

function buildScheduleAudit(
  context: unknown,
  plan: unknown,
  scope: string,
): { audit: JsonObject; blockingErrors: string[] } {
  const root = isObject(context) ? context : {};
  const trainingContext = isObject(root.client_training_context) ? root.client_training_context : {};
  const onboarding = isObject(trainingContext.onboarding) ? trainingContext.onboarding : {};
  const weekly = isObject(trainingContext.latest_weekly_checkin) ? trainingContext.latest_weekly_checkin : {};
  const generatedPlan = isObject(plan) ? plan : {};
  const days = Array.isArray(generatedPlan.days) ? generatedPlan.days : [];

  const declaredDays = strictInteger(onboarding.training_days_per_week);
  const maxSessionMinutes = strictInteger(onboarding.session_minutes);
  const availableDaysNextWeek = strictInteger(weekly.available_days_next_week);
  const blockingErrors: string[] = [];

  let frequencyStatus = "not_available";
  if (scope === "program" && declaredDays !== null && declaredDays >= 1 && declaredDays <= 7) {
    frequencyStatus = days.length === declaredDays ? "ok" : "blocked";
    if (days.length !== declaredDays) {
      blockingErrors.push(
        `La rutina completa debe tener exactamente ${declaredDays} días porque esa es la frecuencia declarada por el cliente; la IA devolvió ${days.length}.`,
      );
    }
  } else if (scope === "day") {
    frequencyStatus = "not_applicable";
  }

  const dayAudits = days.map((rawDay, index) => {
    const day = isObject(rawDay) ? rawDay : {};
    const dayNumber = strictInteger(day.day_number) ?? index + 1;
    const modelMinutes = strictInteger(day.estimated_minutes);
    const deterministicMinutes = estimateDayMinutes(day);
    const candidates = [modelMinutes, deterministicMinutes].filter((v): v is number => v !== null);
    const effectiveMinutes = candidates.length ? Math.max(...candidates) : null;
    let status = "not_available";

    if (maxSessionMinutes !== null && maxSessionMinutes > 0 && effectiveMinutes !== null) {
      status = effectiveMinutes <= maxSessionMinutes ? "ok" : "blocked";
      if (effectiveMinutes > maxSessionMinutes) {
        blockingErrors.push(
          `Día ${dayNumber}: duración estimada ${effectiveMinutes} min supera el máximo declarado de ${maxSessionMinutes} min.`,
        );
      }
    }

    return {
      day_number: dayNumber,
      model_minutes: modelMinutes,
      deterministic_minutes: deterministicMinutes,
      effective_minutes: effectiveMinutes,
      max_minutes: maxSessionMinutes,
      status,
    };
  });

  return {
    audit: {
      version: "cv-schedule-audit-v1",
      scope,
      declared_days_per_week: declaredDays,
      generated_days: days.length,
      frequency_status: frequencyStatus,
      max_session_minutes: maxSessionMinutes,
      available_days_next_week: availableDaysNextWeek,
      overall_status: blockingErrors.length ? "blocked" : "ok",
      blocking_count: blockingErrors.length,
      methodology:
        "CV Coach usa el mayor valor entre estimated_minutes informado por la IA y una estimación determinística basada en series, rango medio de reps/segundos, tempo, descansos, calentamiento mínimo, transiciones y un margen operacional del 10%.",
      rule:
        "La frecuencia declarada y el tiempo máximo por sesión son restricciones duras: una rutina que no cabe en la disponibilidad del cliente no se aplica al borrador.",
      days: dayAudits,
    },
    blockingErrors,
  };
}
'''
edge = replace_once(edge, "\nconst outputSchema = {", "\n" + schedule_helpers + "\nconst outputSchema = {", "schedule helper insertion")

# 3) Make prompt semantics explicit, but deterministic validation remains authoritative.
edge = replace_once(
    edge,
    "3. Respeta equipamiento, disponibilidad, duración de sesión, experiencia y objetivo cuando estén presentes.",
    "3. Respeta equipamiento, disponibilidad, duración de sesión, experiencia y objetivo cuando estén presentes. training_days_per_week es la frecuencia semanal objetivo y session_minutes es el MÁXIMO de minutos disponibles por sesión, no una sugerencia.",
    "prompt hard duration",
)
edge = replace_once(
    edge,
    "7. scope=\"program\": devuelve una rutina completa. Usa la frecuencia declarada razonable (1-7 días); si falta, conserva la estructura existente y, si tampoco existe, usa 3 días.",
    "7. scope=\"program\": devuelve una rutina completa. Si training_days_per_week está presente (1-7), devuelve EXACTAMENTE esa cantidad de días. Si falta, conserva la estructura existente y, si tampoco existe, usa 3 días. Cada día debe caber dentro de session_minutes cuando esté informado.",
    "prompt exact frequency",
)

# 4) Build audit before validation so blocked generations persist the reason and never apply.
edge = replace_once(
    edge,
    "  const validationErrors = validateGeneratedOutput(generated, context, scope, targetDayNumber);",
    "  const scheduleCheck = buildScheduleAudit(modelContext, generated?.plan, scope);\n  const validationErrors = [\n    ...validateGeneratedOutput(generated, context, scope, targetDayNumber),\n    ...scheduleCheck.blockingErrors,\n  ];",
    "hard schedule validation",
)
edge = replace_once(
    edge,
    "  let explanations = isObject(generated?.explanations) ? generated.explanations : {};\n\n  if (validationErrors.length) {",
    "  let explanations = isObject(generated?.explanations) ? generated.explanations : {};\n  explanations = {\n    ...explanations,\n    schedule_audit: scheduleCheck.audit,\n    volume_audit: buildVolumeAudit(modelContext, generated?.plan, scope, targetDayNumber),\n  };\n\n  if (validationErrors.length) {",
    "persist audit before validation",
)
edge = replace_once(
    edge,
    "\n  explanations = {\n    ...explanations,\n    volume_audit: buildVolumeAudit(modelContext, generated.plan, scope, targetDayNumber),\n  };\n\n  await patchGeneration",
    "\n  await patchGeneration",
    "remove duplicate post-validation volume audit",
)

# 5) Coach-facing schedule audit in AI Review and Before/After modal.
schedule_ui = r'''function aiScheduleAuditHtml(value){let a=value&&typeof value==='object'?value:null;if(!a||a.version!=='cv-schedule-audit-v1')return '';let blocked=a.overall_status==='blocked',days=Array.isArray(a.days)?a.days:[],freq=a.declared_days_per_week==null?'—':a.declared_days_per_week,max=a.max_session_minutes==null?'—':a.max_session_minutes;return '<div class="card" style="margin-top:12px;border-color:'+(blocked?'#64202b':'#245b3c')+'"><div class="row"><div class="grow"><b>AUDITOR DE TIEMPO Y FRECUENCIA</b><div class="muted">Disponibilidad real del cliente · validación dura</div></div><span class="pill '+(blocked?'red':'green')+'">'+(blocked?'BLOQUEADO':'OK')+'</span></div><div class="metrics" style="margin-top:10px"><div class="metric"><span>Días declarados</span><b>'+esc(freq)+'</b></div><div class="metric"><span>Días generados</span><b>'+esc(a.generated_days??'—')+'</b></div><div class="metric"><span>Máx. por sesión</span><b>'+esc(max)+(max==='—'?'':' min')+'</b></div><div class="metric"><span>Bloqueos</span><b>'+esc(a.blocking_count??0)+'</b></div></div><div class="stack" style="margin-top:10px">'+days.map(d=>{let bad=d.status==='blocked';return '<div class="row" style="align-items:flex-start;border-top:1px solid var(--b);padding-top:8px"><div class="grow"><b>Día '+esc(d.day_number??'—')+'</b><div class="muted">IA: '+esc(d.model_minutes??'—')+' min · CV Coach: '+esc(d.deterministic_minutes??'—')+' min · usado: '+esc(d.effective_minutes??'—')+' min · máximo: '+esc(d.max_minutes??'—')+' min</div></div><span class="pill '+(bad?'red':'green')+'">'+(bad?'EXCEDE':'OK')+'</span></div>'}).join('')+'</div><div class="muted" style="margin-top:10px"><b>Regla:</b> '+esc(a.rule||'')+'</div><div class="muted" style="margin-top:6px"><b>Método:</b> '+esc(a.methodology||'')+'</div></div>'}'''
if "function aiScheduleAuditHtml" not in admin:
    admin = replace_once(admin, "function aiVolumeAuditHtml", schedule_ui + "function aiVolumeAuditHtml", "admin schedule renderer insertion")
admin = replace_once(
    admin,
    "return rationale+aiVolumeAuditHtml(x.volume_audit)}",
    "return rationale+aiScheduleAuditHtml(x.schedule_audit)+aiVolumeAuditHtml(x.volume_audit)}",
    "admin AI review schedule audit",
)
if "aiScheduleAuditHtml(g?.explanations?.schedule_audit)" not in admin and "aiVolumeAuditHtml(g?.explanations?.volume_audit)" in admin:
    admin = admin.replace(
        "aiVolumeAuditHtml(g?.explanations?.volume_audit)",
        "aiScheduleAuditHtml(g?.explanations?.schedule_audit)+aiVolumeAuditHtml(g?.explanations?.volume_audit)",
        1,
    )

# 6) Regression contracts.
contracts = replace_once(
    contracts,
    'require(admin, "aiVolumeAuditHtml", "volume audit renderer")\n',
    'require(admin, "aiVolumeAuditHtml", "volume audit renderer")\nrequire(admin, "AUDITOR DE TIEMPO Y FRECUENCIA", "hard schedule audit UI")\nrequire(admin, "aiScheduleAuditHtml", "schedule audit renderer")\n',
    "admin schedule contracts",
)
contracts = replace_once(
    contracts,
    'require(edge_program, "buildVolumeAudit", "deterministic volume audit builder")\n',
    'require(edge_program, "buildVolumeAudit", "deterministic volume audit builder")\nrequire(edge_program, "cv-schedule-audit-v1", "hard schedule audit contract version")\nrequire(edge_program, "buildScheduleAudit", "hard schedule audit builder")\nrequire(edge_program, "weekly_availability", "legacy onboarding frequency alias")\nrequire(edge_program, "session_duration_minutes", "legacy onboarding duration alias")\n',
    "edge schedule contracts",
)

EDGE.write_text(edge, encoding="utf-8")
ADMIN.write_text(admin, encoding="utf-8")
CONTRACTS.write_text(contracts, encoding="utf-8")
print("HARD_SCHEDULE_CONSTRAINTS_PATCH_OK")
