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

volume_helpers = r'''
const focusMuscleMap: Record<string, string> = {
  glutes: "glúteos",
  quadriceps: "cuádriceps",
  hamstrings: "isquiotibiales",
  calves: "gemelos",
  back: "espalda",
  chest: "pecho",
  shoulders: "hombros",
  biceps: "bíceps",
  triceps: "tríceps",
  core: "core",
};

function normalizedAuditMuscle(value: unknown): string | null {
  const muscle = cleanText(value, 80)?.toLowerCase() ?? null;
  if (!muscle || muscle === "cardio" || muscle === "full body") return null;
  if (muscle === "deltoide posterior") return "hombros";
  return muscle;
}

function volumeBand(
  experience: string | null,
  muscle: string,
  priority: boolean,
): { min: number; max: number } | null {
  if (!experience || !["beginner", "intermediate", "advanced"].includes(experience)) return null;
  const small = new Set(["bíceps", "tríceps", "core", "gemelos"]).has(muscle);
  const bands = small
    ? {
        beginner: priority ? [4, 10] : [2, 8],
        intermediate: priority ? [5, 12] : [3, 10],
        advanced: priority ? [6, 14] : [4, 12],
      }
    : {
        beginner: priority ? [6, 14] : [4, 10],
        intermediate: priority ? [8, 16] : [6, 12],
        advanced: priority ? [10, 20] : [6, 16],
      };
  const [min, max] = bands[experience as keyof typeof bands];
  return { min, max };
}

function buildVolumeAudit(
  context: unknown,
  plan: unknown,
  scope: string,
  targetDayNumber: number | null,
): JsonObject {
  const root = isObject(context) ? context : {};
  const trainingContext = isObject(root.client_training_context) ? root.client_training_context : {};
  const profile = isObject(trainingContext.profile) ? trainingContext.profile : {};
  const preferences = isObject(trainingContext.training_preferences) ? trainingContext.training_preferences : {};
  const currentDraft = isObject(root.current_draft) ? root.current_draft : {};
  const generatedPlan = isObject(plan) ? plan : {};
  const generatedDays = Array.isArray(generatedPlan.days) ? generatedPlan.days : [];
  const currentDays = Array.isArray(currentDraft.days) ? currentDraft.days : [];
  const weeklyDays = scope === "day" && targetDayNumber !== null
    ? [
        ...currentDays.filter((day) => !isObject(day) || integer(day.day_number) !== targetDayNumber),
        ...generatedDays,
      ]
    : generatedDays;

  const catalog = Array.isArray(root.exercise_catalog) ? root.exercise_catalog : [];
  const muscleByExercise = new Map<string, string>();
  for (const raw of catalog) {
    if (!isObject(raw) || typeof raw.id !== "string") continue;
    const muscle = normalizedAuditMuscle(raw.primary_muscle);
    if (muscle) muscleByExercise.set(raw.id, muscle);
  }

  const focusRaw = Array.isArray(preferences.muscle_focus) ? preferences.muscle_focus : [];
  const fullBodyFocus = focusRaw.some((value) => String(value) === "full_body");
  const focusGroups = fullBodyFocus
    ? []
    : [...new Set(focusRaw.map((value) => focusMuscleMap[String(value)]).filter(Boolean))];
  const focusSet = new Set(focusGroups);
  const setsByMuscle = new Map<string, number>();
  let directSetsTotal = 0;

  for (const rawDay of weeklyDays) {
    if (!isObject(rawDay) || !Array.isArray(rawDay.exercises)) continue;
    for (const rawExercise of rawDay.exercises) {
      if (!isObject(rawExercise) || typeof rawExercise.exercise_id !== "string") continue;
      const muscle = muscleByExercise.get(rawExercise.exercise_id);
      const sets = integer(rawExercise.target_sets);
      if (!muscle || sets === null || sets < 0) continue;
      setsByMuscle.set(muscle, (setsByMuscle.get(muscle) ?? 0) + sets);
      directSetsTotal += sets;
    }
  }

  const experience = cleanText(profile.experience_level, 40)?.toLowerCase() ?? null;
  const allGroups = [...new Set([...setsByMuscle.keys(), ...focusGroups])].sort((a, b) => a.localeCompare(b, "es"));
  let flaggedCount = 0;
  let overallReview = !experience || !["beginner", "intermediate", "advanced"].includes(experience);
  const muscles = allGroups.map((muscle) => {
    const weeklySets = setsByMuscle.get(muscle) ?? 0;
    const priority = focusSet.has(muscle);
    const band = volumeBand(experience, muscle, priority);
    let status = "review";
    let note = "Nivel de experiencia no disponible; revisión manual requerida.";
    if (band) {
      if (weeklySets < band.min) {
        status = "low";
        note = priority
          ? "Por debajo de la referencia operativa para un grupo prioritario."
          : "Por debajo de la referencia operativa; puede ser intencional si el objetivo es mantenimiento o menor prioridad.";
      } else if (weeklySets > band.max) {
        status = "high";
        note = "Por encima de la referencia operativa; revisar recuperación, redundancia y tolerancia antes de publicar.";
      } else {
        status = "in_range";
        note = priority
          ? "Dentro de la referencia operativa para un grupo prioritario."
          : "Dentro de la referencia operativa general.";
      }
      if (status === "high" || (priority && status !== "in_range")) overallReview = true;
    }
    if (status !== "in_range") flaggedCount += 1;
    return {
      muscle,
      weekly_sets: weeklySets,
      priority,
      range_min: band?.min ?? null,
      range_max: band?.max ?? null,
      status,
      note,
    };
  });

  return {
    version: "cv-volume-audit-v1",
    experience_level: experience,
    scope,
    full_body_focus: fullBodyFocus,
    focus_groups: focusGroups,
    overall_status: overallReview ? "review" : "ok",
    flagged_count: flaggedCount,
    direct_sets_total: directSetsTotal,
    methodology:
      "Cuenta series directas según el músculo primario del catálogo. No suma participación indirecta de ejercicios compuestos. Las bandas son una referencia operativa CV Coach v1 para revisión del coach, no umbrales clínicos ni una garantía de resultado.",
    criteria:
      "La referencia considera nivel de experiencia y eleva el rango esperado de los grupos marcados como foco muscular vigente. Dolor, recuperación, adherencia y restricciones pueden justificar valores fuera de banda.",
    muscles,
  };
}
'''

edge = replace_once(
    edge,
    "\nconst outputSchema = {",
    "\n" + volume_helpers + "\nconst outputSchema = {",
    "edge volume helper insertion",
)
edge = replace_once(
    edge,
    "9. Prioriza técnica, adherencia, progresión gradual y volumen razonable. Evita redundancia innecesaria.\n10. Las explicaciones, advertencias y conflictos deben escribirse en español claro para el coach.",
    "9. Prioriza técnica, adherencia, progresión gradual y volumen razonable. Evita redundancia innecesaria.\n9A. En explanations.summary explica brevemente cómo el nivel de experiencia y muscle_focus influyeron en la distribución del volumen. No declares rangos científicos exactos: CV Coach hará una auditoría determinística independiente.\n10. Las explicaciones, advertencias y conflictos deben escribirse en español claro para el coach.",
    "edge prompt volume rationale",
)
edge = replace_once(
    edge,
    "  const explanations = isObject(generated?.explanations) ? generated.explanations : {};",
    "  let explanations = isObject(generated?.explanations) ? generated.explanations : {};",
    "edge mutable explanations",
)
edge = replace_once(
    edge,
    "\n  await patchGeneration(supabaseUrl, serviceKey, generationId, {\n    output_snapshot: generated,",
    "\n  explanations = {\n    ...explanations,\n    volume_audit: buildVolumeAudit(modelContext, generated.plan, scope, targetDayNumber),\n  };\n\n  await patchGeneration(supabaseUrl, serviceKey, generationId, {\n    output_snapshot: generated,",
    "edge persist volume audit",
)

start = admin.find("function aiReviewExplanations(value){")
end = admin.find("function aiReviewHtml", start)
if start < 0 or end < 0:
    raise SystemExit("admin explanation function anchors not found")
volume_ui = r'''function aiVolumeAuditHtml(value){let a=value&&typeof value==='object'?value:null;if(!a||a.version!=='cv-volume-audit-v1')return '';let rows=Array.isArray(a.muscles)?a.muscles:[],exp={beginner:'Principiante',intermediate:'Intermedio',advanced:'Avanzado'}[a.experience_level]||'Sin nivel',overall=a.overall_status==='ok',statusLabel=s=>({in_range:'EN RANGO',low:'BAJO REFERENCIA',high:'ALTO',review:'REVISAR'})[s]||'REVISAR',statusClass=s=>s==='in_range'?'green':s==='high'?'red':s==='low'?'warn':'blue';return '<div class="card" style="margin-top:12px;border-color:'+(overall?'#245b3c':'#62451f')+'"><div class="row"><div class="grow"><b>AUDITOR DE VOLUMEN SEMANAL</b><div class="muted">Series directas · referencia operativa · Nivel: '+esc(exp)+'</div></div><span class="pill '+(overall?'green':'warn')+'">'+(overall?'OK':'REVISAR')+'</span></div><div class="metrics" style="margin-top:10px"><div class="metric"><span>Series directas</span><b>'+esc(a.direct_sets_total??'—')+'</b></div><div class="metric"><span>Grupos auditados</span><b>'+esc(rows.length)+'</b></div><div class="metric"><span>Fuera de rango / revisar</span><b>'+esc(a.flagged_count??0)+'</b></div><div class="metric"><span>Foco vigente</span><b style="font-size:12px">'+esc(Array.isArray(a.focus_groups)&&a.focus_groups.length?a.focus_groups.join(' + '):(a.full_body_focus?'Cuerpo completo':'Sin foco'))+'</b></div></div><div class="stack" style="margin-top:10px">'+rows.map(r=>'<div class="row" style="align-items:flex-start;border-top:1px solid var(--b);padding-top:8px"><div class="grow"><b>'+esc(r.muscle||'Grupo')+(r.priority?' · FOCO':'')+'</b><div class="muted">'+esc(r.weekly_sets??0)+' series directas · referencia '+esc(r.range_min==null||r.range_max==null?'manual':r.range_min+'–'+r.range_max)+'</div><div class="muted">'+esc(r.note||'')+'</div></div><span class="pill '+statusClass(r.status)+'">'+esc(statusLabel(r.status))+'</span></div>').join('')+'</div><div class="muted" style="margin-top:10px"><b>Método:</b> '+esc(a.methodology||'')+'</div><div class="muted" style="margin-top:6px"><b>Criterio:</b> '+esc(a.criteria||'')+'</div></div>'}function aiReviewExplanations(value){let x=value&&typeof value==='object'?value:{},days=Array.isArray(x.day_rationale)?x.day_rationale:[],summary=String(x.summary||'').trim(),rationale=!summary&&!days.length?'':'<div style="margin-top:10px"><b>Por qué la IA propuso esta rutina</b>'+(summary?'<div class="muted" style="margin-top:6px">'+esc(summary)+'</div>':'')+(days.length?'<div class="stack" style="margin-top:8px">'+days.map(d=>'<div class="muted"><b>Día '+esc(d?.day_number??'—')+':</b> '+esc(d?.reason||'Sin explicación')+'</div>').join('')+'</div>':'')+'</div>';return rationale+aiVolumeAuditHtml(x.volume_audit)}'''
admin = admin[:start] + volume_ui + admin[end:]

comparison_anchor = "+'</div><div style=\"display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:12px;margin-top:12px\"><section><div class=\"ey\">ANTES</div>"
comparison_replacement = "+'</div>'+aiVolumeAuditHtml(g?.explanations?.volume_audit)+'<div style=\"display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:12px;margin-top:12px\"><section><div class=\"ey\">ANTES</div>"
admin = replace_once(admin, comparison_anchor, comparison_replacement, "admin comparison volume audit")

if "aiReviewExplanations(generation.explanations)" not in admin:
    raise SystemExit("admin canonical explanation binding missing")

contracts = replace_once(
    contracts,
    'vercel = read("vercel.json")\n',
    'vercel = read("vercel.json")\nedge_program = read("supabase/functions/generate-ai-program/index.ts")\n',
    "contracts edge load",
)
contracts = replace_once(
    contracts,
    'require(admin, "Rutina anterior vs nueva rutina", "AI comparison summary modal")\n',
    'require(admin, "Rutina anterior vs nueva rutina", "AI comparison summary modal")\nrequire(admin, "AUDITOR DE VOLUMEN SEMANAL", "deterministic weekly volume audit UI")\nrequire(admin, "aiVolumeAuditHtml", "volume audit renderer")\nrequire(edge_program, "cv-volume-audit-v1", "volume audit contract version")\nrequire(edge_program, "buildVolumeAudit", "deterministic volume audit builder")\n',
    "contracts volume audit markers",
)

EDGE.write_text(edge, encoding="utf-8")
ADMIN.write_text(admin, encoding="utf-8")
CONTRACTS.write_text(contracts, encoding="utf-8")
print("VOLUME_AUDIT_PATCH_OK")
