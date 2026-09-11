from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
EDGE=ROOT/'supabase/functions/generate-ai-program/index.ts'
ADMIN=ROOT/'index.html'
CONTRACTS=ROOT/'scripts/validate-repo-contracts.py'
edge=EDGE.read_text(encoding='utf-8')
admin=ADMIN.read_text(encoding='utf-8')
contracts=CONTRACTS.read_text(encoding='utf-8')

def once(text,old,new,label):
    n=text.count(old)
    if n!=1: raise SystemExit(f'{label}: expected 1 anchor, found {n}')
    return text.replace(old,new,1)

def replace_between(text,start,end,new,label):
    i=text.find(start)
    if i<0: raise SystemExit(f'{label}: start not found')
    j=text.find(end,i)
    if j<0: raise SystemExit(f'{label}: end not found')
    return text[:i]+new+text[j:]

# ---------- EDGE: structured constraints, filtered catalog and time learning ----------
old_catalog='''  const rawCatalog = Array.isArray(root.exercise_catalog) ? root.exercise_catalog : [];
  const catalog = rawCatalog.slice(0, maxCatalogExercises).map((exercise) =>
    compactRecord(exercise, [
      "id",
      "name",
      "primary_muscle",
      "equipment",
      "movement_pattern",
      "difficulty",
      "default_tempo",
      "default_rest_sec",
      "prescription_unit",
    ])
  );

  return {'''
new_catalog='''  const trainingConstraints = (Array.isArray(root.training_constraints) ? root.training_constraints : [])
    .filter(isObject)
    .map((item) => compactRecord(item, ["constraint_code", "label", "region", "action", "note"]));
  const timeLearning = compactRecord(root.time_learning, ["sample_count", "median_ratio", "applied_factor"]);
  const rawExposures = Array.isArray(root.exercise_mechanical_exposures) ? root.exercise_mechanical_exposures : [];
  const exposuresByExercise = new Map<string, JsonObject[]>();
  for (const raw of rawExposures) {
    if (!isObject(raw) || typeof raw.exercise_id !== "string" || typeof raw.constraint_code !== "string") continue;
    const list = exposuresByExercise.get(raw.exercise_id) ?? [];
    list.push(compactRecord(raw, ["constraint_code", "exposure_level"]));
    exposuresByExercise.set(raw.exercise_id, list);
  }
  const avoidCodes = new Set(trainingConstraints.filter((x) => x.action === "avoid").map((x) => String(x.constraint_code)));
  const rawCatalog = Array.isArray(root.exercise_catalog) ? root.exercise_catalog : [];
  const excludedExerciseIds: string[] = [];
  const catalog = rawCatalog.slice(0, maxCatalogExercises).flatMap((exercise) => {
    const base = compactRecord(exercise, [
      "id",
      "name",
      "primary_muscle",
      "equipment",
      "movement_pattern",
      "difficulty",
      "default_tempo",
      "default_rest_sec",
      "prescription_unit",
    ]);
    const exerciseId = typeof base.id === "string" ? base.id : "";
    const exposures = exposuresByExercise.get(exerciseId) ?? [];
    if (exposures.some((x) => avoidCodes.has(String(x.constraint_code)))) {
      if (exerciseId) excludedExerciseIds.push(exerciseId);
      return [];
    }
    return [{ ...base, mechanical_exposures: exposures }];
  });

  return {'''
edge=once(edge,old_catalog,new_catalog,'edge catalog safety filter')
edge=once(edge,
'''      schedule_preferences: schedulePreferences,
      latest_weekly_checkin: weekly,
    },
    current_draft: draft,
    exercise_catalog: catalog,''',
'''      schedule_preferences: schedulePreferences,
      training_constraints: trainingConstraints,
      time_learning: timeLearning,
      latest_weekly_checkin: weekly,
    },
    safety_filter: {
      excluded_exercise_ids: excludedExerciseIds,
      excluded_count: excludedExerciseIds.length,
      avoid_constraint_codes: [...avoidCodes],
    },
    current_draft: draft,
    exercise_catalog: catalog,''',
'edge context safety output')

# Warnings for explicit structured constraints.
edge=once(edge,
'''  const sleep = finiteNumber(weekly.sleep_hours_avg);
  const energy = finiteNumber(weekly.energy_level);''',
'''  const constraints = Array.isArray(root.training_constraints) ? root.training_constraints.filter(isObject) : [];
  const avoidCount = constraints.filter((x) => x.action === "avoid").length;
  const cautionCount = constraints.filter((x) => x.action === "caution").length;
  if (avoidCount || cautionCount) {
    warnings.push({
      code: "STRUCTURED_TRAINING_CONSTRAINTS",
      severity: avoidCount ? "high" : "warning",
      message: `Restricciones mecánicas vigentes: ${avoidCount} EVITAR y ${cautionCount} PRECAUCIÓN. CV Coach filtrará y auditará la selección de ejercicios.`,
    });
  }

  const sleep = finiteNumber(weekly.sleep_hours_avg);
  const energy = finiteNumber(weekly.energy_level);''',
'edge deterministic structured constraint warning')

# Learned time factor in deterministic schedule audit.
edge=once(edge,
'''  const weekly = isObject(trainingContext.latest_weekly_checkin) ? trainingContext.latest_weekly_checkin : {};
  const generatedPlan = isObject(plan) ? plan : {};''',
'''  const weekly = isObject(trainingContext.latest_weekly_checkin) ? trainingContext.latest_weekly_checkin : {};
  const timeLearning = isObject(trainingContext.time_learning) ? trainingContext.time_learning : {};
  const learnedFactorRaw = finiteNumber(timeLearning.applied_factor);
  const learnedFactor = learnedFactorRaw !== null ? Math.min(1.5, Math.max(1, learnedFactorRaw)) : 1;
  const generatedPlan = isObject(plan) ? plan : {};''',
'edge learned factor source')
edge=once(edge,
'''    const modelMinutes = strictInteger(day.estimated_minutes);
    const deterministicMinutes = estimateDayMinutes(day);
    const candidates = [modelMinutes, deterministicMinutes].filter((v): v is number => v !== null);
    const effectiveMinutes = candidates.length ? Math.max(...candidates) : null;''',
'''    const modelMinutes = strictInteger(day.estimated_minutes);
    const baseDeterministicMinutes = estimateDayMinutes(day);
    const deterministicMinutes = baseDeterministicMinutes === null ? null : Math.ceil(baseDeterministicMinutes * learnedFactor);
    const candidates = [modelMinutes, deterministicMinutes].filter((v): v is number => v !== null);
    const effectiveMinutes = candidates.length ? Math.max(...candidates) : null;''',
'edge learned minutes')
edge=once(edge,
'''      model_minutes: modelMinutes,
      deterministic_minutes: deterministicMinutes,
      effective_minutes: effectiveMinutes,''',
'''      model_minutes: modelMinutes,
      base_deterministic_minutes: baseDeterministicMinutes,
      learned_factor: learnedFactor,
      deterministic_minutes: deterministicMinutes,
      effective_minutes: effectiveMinutes,''',
'edge learned audit fields')
edge=once(edge,
'''      max_session_minutes: maxSessionMinutes,
      available_days_next_week: availableDaysNextWeek,''',
'''      max_session_minutes: maxSessionMinutes,
      available_days_next_week: availableDaysNextWeek,
      time_learning_sample_count: strictInteger(timeLearning.sample_count) ?? 0,
      time_learning_factor: learnedFactor,''',
'edge learned audit summary')
edge=once(edge,
'''        "CV Coach usa el mayor valor entre estimated_minutes informado por la IA y una estimación determinística basada en series, rango medio de reps/segundos, tempo, descansos, calentamiento mínimo, transiciones y un margen operacional del 10%.",''',
'''        "CV Coach usa el mayor valor entre estimated_minutes informado por la IA y una estimación determinística basada en series, rango medio de reps/segundos, tempo, descansos, calentamiento mínimo y transiciones. Con 3+ sesiones válidas puede ampliar la estimación usando el ritmo real del cliente; nunca la reduce y limita el ajuste a 1.50x.",''',
'edge time methodology')

# Independent safety audit.
safety_code=r'''
function buildSafetyAudit(
  context: unknown,
  plan: unknown,
): { audit: JsonObject; blockingErrors: string[]; cautionWarnings: JsonObject[] } {
  const root = isObject(context) ? context : {};
  const trainingContext = isObject(root.client_training_context) ? root.client_training_context : {};
  const constraints = Array.isArray(trainingContext.training_constraints)
    ? trainingContext.training_constraints.filter(isObject)
    : [];
  const constraintByCode = new Map<string, JsonObject>();
  for (const item of constraints) {
    if (typeof item.constraint_code === "string") constraintByCode.set(item.constraint_code, item);
  }
  const catalog = Array.isArray(root.exercise_catalog) ? root.exercise_catalog : [];
  const catalogById = new Map<string, JsonObject>();
  for (const item of catalog) if (isObject(item) && typeof item.id === "string") catalogById.set(item.id, item);
  const days = isObject(plan) && Array.isArray(plan.days) ? plan.days : [];
  const matches: JsonObject[] = [];
  const blockingErrors: string[] = [];
  const cautionWarnings: JsonObject[] = [];

  for (const rawDay of days) {
    if (!isObject(rawDay) || !Array.isArray(rawDay.exercises)) continue;
    const dayNumber = integer(rawDay.day_number) ?? null;
    for (const rawExercise of rawDay.exercises) {
      if (!isObject(rawExercise) || typeof rawExercise.exercise_id !== "string") continue;
      const meta = catalogById.get(rawExercise.exercise_id);
      if (!meta) continue;
      const exposures = Array.isArray(meta.mechanical_exposures) ? meta.mechanical_exposures.filter(isObject) : [];
      for (const exposure of exposures) {
        const code = typeof exposure.constraint_code === "string" ? exposure.constraint_code : "";
        const constraint = constraintByCode.get(code);
        if (!constraint) continue;
        const action = String(constraint.action ?? "");
        const label = cleanText(constraint.label, 120) ?? code;
        const exerciseName = cleanText(meta.name, 120) ?? "Ejercicio";
        matches.push({
          day_number: dayNumber,
          exercise_id: rawExercise.exercise_id,
          exercise_name: exerciseName,
          constraint_code: code,
          label,
          action,
          exposure_level: exposure.exposure_level ?? null,
        });
        if (action === "avoid") {
          blockingErrors.push(`Día ${dayNumber ?? "?"}: ${exerciseName} coincide con una restricción EVITAR (${label}).`);
        } else if (action === "caution") {
          cautionWarnings.push({
            code: "MECHANICAL_CAUTION_MATCH",
            severity: "warning",
            message: `Día ${dayNumber ?? "?"}: ${exerciseName} coincide con PRECAUCIÓN (${label}); revisar tolerancia individual antes de publicar.`,
          });
        }
      }
    }
  }

  const safetyFilter = isObject(root.safety_filter) ? root.safety_filter : {};
  return {
    audit: {
      version: "cv-safety-audit-v1",
      active_constraints: constraints.length,
      avoid_constraints: constraints.filter((x) => x.action === "avoid").length,
      caution_constraints: constraints.filter((x) => x.action === "caution").length,
      excluded_from_ai_catalog: integer(safetyFilter.excluded_count) ?? 0,
      generated_matches: matches,
      overall_status: blockingErrors.length ? "blocked" : cautionWarnings.length ? "review" : "ok",
      rule: "EVITAR se excluye antes de llamar a la IA y bloquea cualquier coincidencia defensiva. PRECAUCIÓN no diagnostica ni prohíbe: exige revisión del coach.",
    },
    blockingErrors,
    cautionWarnings,
  };
}
'''
edge=once(edge,'\nconst outputSchema = {','\n'+safety_code+'\nconst outputSchema = {','edge safety audit insertion')
edge=once(edge,
'''4. Considera dolor/lesiones/limitaciones de forma conservadora. Si no puedes satisfacer una restricción con seguridad suficiente, registra un conflicto blocking=true; no ocultes incertidumbre.''',
'''4. Considera dolor/lesiones/limitaciones de forma conservadora. Si no puedes satisfacer una restricción con seguridad suficiente, registra un conflicto blocking=true; no ocultes incertidumbre.
4A. client_training_context.training_constraints contiene restricciones mecánicas explícitas del coach. Los ejercicios que coinciden con EVITAR ya fueron eliminados de exercise_catalog: nunca intentes recuperarlos ni inventar equivalentes fuera del catálogo. Las coincidencias PRECAUCIÓN pueden usarse solo si la propuesta es razonable y deben explicarse para revisión humana.''',
'edge safety prompt')
edge=once(edge,
'''  const scheduleCheck = buildScheduleAudit(modelContext, generated?.plan, scope);
  const validationErrors = [
    ...validateGeneratedOutput(generated, context, scope, targetDayNumber),
    ...scheduleCheck.blockingErrors,
  ];
  const warnings = [
    ...requestWarnings,
    ...(Array.isArray(generated?.warnings) ? generated.warnings : []),
  ];''',
'''  const scheduleCheck = buildScheduleAudit(modelContext, generated?.plan, scope);
  const safetyCheck = buildSafetyAudit(modelContext, generated?.plan);
  const validationErrors = [
    ...validateGeneratedOutput(generated, modelContext, scope, targetDayNumber),
    ...scheduleCheck.blockingErrors,
    ...safetyCheck.blockingErrors,
  ];
  const warnings = [
    ...requestWarnings,
    ...safetyCheck.cautionWarnings,
    ...(Array.isArray(generated?.warnings) ? generated.warnings : []),
  ];''',
'edge deterministic safety validation')
edge=once(edge,
'''    schedule_audit: scheduleCheck.audit,
    volume_audit: buildVolumeAudit(modelContext, generated?.plan, scope, targetDayNumber),''',
'''    schedule_audit: scheduleCheck.audit,
    safety_audit: safetyCheck.audit,
    volume_audit: buildVolumeAudit(modelContext, generated?.plan, scope, targetDayNumber),''',
'edge safety explanations')

# ---------- ADMIN: constraints, program audit, pre-generation summary ----------
admin_helpers=r'''function trainingConstraintPill(action){let a=String(action||'');return `<span class="pill ${a==='avoid'?'red':'warn'}">${a==='avoid'?'EVITAR':'PRECAUCIÓN'}</span>`}function trainingConstraintsSection(catalog,rows){let active=Array.isArray(rows)?rows.filter(x=>x.active!==false):[],byCode=new Map((catalog||[]).map(x=>[x.code,x]));return `<section style="margin:18px 0"><div class="row"><h2 class="grow">Restricciones mecánicas</h2><button id="manageTrainingConstraints" class="btn primary small">GESTIONAR RESTRICCIONES</button></div><div class="card">${active.length?`<div class="stack">${active.map(x=>{let meta=byCode.get(x.constraint_code)||{};return `<div class="row" style="align-items:flex-start"><div class="grow"><b>${esc(meta.label||x.constraint_code)}</b><div class="muted">${esc(meta.region||'')} ${x.note?'· '+esc(x.note):''}</div></div>${trainingConstraintPill(x.action)}</div>`}).join('')}</div>`:'<div class="muted">Sin restricciones mecánicas estructuradas. Los textos de dolor/lesión siguen siendo contexto, pero no se convierten automáticamente en diagnósticos.</div>'}<div class="muted" style="margin-top:10px">EVITAR excluye ejercicios compatibles del generador y bloquea publicación. PRECAUCIÓN exige revisión del coach.</div></div></section>`}function openTrainingConstraintsModal(clientId,catalog,rows){let active=new Map((rows||[]).filter(x=>x.active!==false).map(x=>[x.constraint_code,x]));$('#modal').innerHTML=`<div class="modal"><div class="card"><div class="row"><div class="grow"><div class="ey">SEGURIDAD DE PROGRAMACIÓN</div><h2>Restricciones mecánicas</h2></div><button id="closeTrainingConstraints" class="btn small">✕</button></div><p class="sub">Estas opciones describen exposiciones de movimiento. No diagnostican lesiones. Usa EVITAR solo cuando corresponda a una decisión operativa del coach.</p><div class="stack">${(catalog||[]).map(meta=>{let current=active.get(meta.code)||{};return `<div class="card"><div class="row"><div class="grow"><b>${esc(meta.label)}</b><div class="muted">${esc(meta.region)} · ${esc(meta.description||'')}</div></div><select class="input constraintAction" data-code="${esc(meta.code)}" style="width:auto;min-width:150px;margin:0"><option value="" ${!current.action?'selected':''}>Sin restricción</option><option value="caution" ${current.action==='caution'?'selected':''}>PRECAUCIÓN</option><option value="avoid" ${current.action==='avoid'?'selected':''}>EVITAR</option></select></div><input class="input constraintNote" data-code="${esc(meta.code)}" maxlength="500" placeholder="Nota opcional" value="${esc(current.note||'')}"></div>`}).join('')}</div><button id="saveTrainingConstraints" class="btn primary" style="width:100%;margin-top:12px">GUARDAR RESTRICCIONES</button><div id="trainingConstraintsStatus" class="status muted"></div></div></div>`;let close=()=>$('#modal').innerHTML='';$('#closeTrainingConstraints').onclick=close;$('#saveTrainingConstraints').onclick=async()=>{let b=$('#saveTrainingConstraints'),out=$('#trainingConstraintsStatus');try{b.disabled=true;out.textContent='Guardando…';let constraints=$$('.constraintAction').map(s=>{let action=s.value,code=s.dataset.code,note=$(`.constraintNote[data-code="${code}"]`)?.value.trim()||null;return action?{constraint_code:code,action,note}:null}).filter(Boolean);let result=await req('/rest/v1/rpc/replace_client_training_constraints_backend',{method:'POST',body:JSON.stringify({p_actor_id:me.id,p_client_id:clientId,p_constraints:constraints})});if(!result?.client_id)throw Error('El backend no confirmó el cambio.');let verify=await table('client_training_constraints','client_id=eq.'+encodeURIComponent(clientId)+'&active=eq.true&select=constraint_code,action,note,active');if(verify.length!==constraints.length)throw Error('Supabase no confirmó todas las restricciones.');close();cache={};toast('Restricciones de entrenamiento actualizadas.');await clientDetail(clientId)}catch(e){out.textContent='No se pudo guardar: '+String(e?.message||e);b.disabled=false}}}async function programQualityAudit(programId){try{return await req('/rest/v1/rpc/get_program_quality_audit_backend',{method:'POST',body:JSON.stringify({p_actor_id:me.id,p_program_id:programId})})}catch(e){return {unavailable:true,error:String(e?.message||e)}}}function programQualityAuditHtml(a){if(!a)return '';if(a.unavailable)return `<div class="card" style="margin:12px 0;border-color:#64202b"><b>CONTROL DE CALIDAD NO DISPONIBLE</b><div class="muted">${esc(a.error||'No se pudo auditar el programa.')}</div></div>`;let schedule=a.schedule||{},days=Array.isArray(a.days)?a.days:[],safety=a.safety||{},learning=a.time_learning||{},blocked=a.overall_status==='blocked',week=Number(schedule.available_days_next_week),habitual=Number(schedule.required_days),weekConflict=Number.isInteger(week)&&Number.isInteger(habitual)&&week<habitual;return `<div class="card" style="margin:12px 0;border-color:${blocked?'#64202b':'#245b3c'}"><div class="row"><div class="grow"><b>CONTROL DE CALIDAD CV COACH</b><div class="muted">Validación determinística independiente de la IA</div></div><span class="pill ${blocked?'red':'green'}">${blocked?'BLOQUEADO':'OK'}</span></div><div class="metrics"><div class="metric"><span>Frecuencia</span><b>${esc(schedule.program_days??'—')} / ${esc(schedule.required_days??'—')}</b></div><div class="metric"><span>Máx. sesión</span><b>${esc(schedule.session_minutes_max==null?'—':schedule.session_minutes_max+' min')}</b></div><div class="metric"><span>Restricciones EVITAR</span><b>${esc((safety.constraints||[]).filter(x=>x.action==='avoid').length)}</b></div><div class="metric"><span>Ritmo aprendido</span><b>${Number(learning.sample_count||0)>=3?'×'+esc(learning.applied_factor||1):esc((learning.sample_count||0)+'/3')}</b></div></div>${weekConflict?`<div class="card" style="margin-top:10px;border-color:#62451f"><b>ESTA SEMANA: ${esc(week)} días disponibles vs ${esc(habitual)} habituales</b><div class="muted">Se trata como disponibilidad temporal: no reescribe la frecuencia habitual ni bloquea por sí sola el programa de largo plazo.</div></div>`:''}<div class="stack" style="margin-top:10px">${days.map(d=>`<div class="row" style="border-top:1px solid var(--b);padding-top:8px"><div class="grow"><b>Día ${esc(d.day_number)} · ${esc(d.name||'')}</b><div class="muted">CV Coach: ${esc(d.effective_minutes??'—')} min / máximo ${esc(d.max_minutes??'—')} min${Number(learning.sample_count||0)>=3?' · factor real ×'+esc(learning.applied_factor):''}</div></div><span class="pill ${d.status==='blocked'?'red':'green'}">${d.status==='blocked'?'EXCEDE':'OK'}</span></div>`).join('')}</div>${(safety.matches||[]).length?`<div style="margin-top:10px"><b>Coincidencias con restricciones</b><div class="stack">${safety.matches.map(x=>`<div class="row"><div class="muted grow">Día ${esc(x.day_number)} · ${esc(x.exercise_name)} · ${esc(x.label)}</div>${trainingConstraintPill(x.action)}</div>`).join('')}</div></div>`:''}</div>`}'''
admin=once(admin,'const trainingFocusItems=',admin_helpers+'const trainingFocusItems=','admin guardrail helpers')

# Ficha 360 data and UI.
admin=once(admin,
'weeklyProgramReviews,trainingPreferences,trainingSchedulePreferences]=await Promise.all',
'weeklyProgramReviews,trainingPreferences,trainingSchedulePreferences,trainingConstraintCatalog,clientTrainingConstraints]=await Promise.all',
'admin client detail destructure')
admin=once(admin,
"table('client_training_schedule_preferences','client_id=eq.'+encodeURIComponent(id)+'&select=*').catch(()=>[]) ]),onboardingMap=",
"table('client_training_schedule_preferences','client_id=eq.'+encodeURIComponent(id)+'&select=*').catch(()=>[]),table('training_constraint_catalog','active=eq.true&select=code,label,region,description&order=region,label').catch(()=>[]),table('client_training_constraints','client_id=eq.'+encodeURIComponent(id)+'&active=eq.true&select=*').catch(()=>[]) ]),onboardingMap=",
'admin client detail constraint queries')
admin=once(admin,
'${trainingScheduleSection(trainingSchedulePreferences[0]||null,onboardingMap)}${cvEvolutionHtml}',
'${trainingScheduleSection(trainingSchedulePreferences[0]||null,onboardingMap)}${trainingConstraintsSection(trainingConstraintCatalog,clientTrainingConstraints)}${cvEvolutionHtml}',
'admin client detail constraint section')
admin=once(admin,
"if($('#manageTrainingSchedule'))$('#manageTrainingSchedule').onclick=()=>openTrainingScheduleModal(id,trainingSchedulePreferences[0]||null,onboardingMap);$('#openMeasurement').onclick=",
"if($('#manageTrainingSchedule'))$('#manageTrainingSchedule').onclick=()=>openTrainingScheduleModal(id,trainingSchedulePreferences[0]||null,onboardingMap);if($('#manageTrainingConstraints'))$('#manageTrainingConstraints').onclick=()=>openTrainingConstraintsModal(id,trainingConstraintCatalog,clientTrainingConstraints);$('#openMeasurement').onclick=",
'admin constraint handler')

# Program editor loads and shows deterministic quality audit.
admin=once(admin,
"generation=generationRows[0]||null,draft=pr.status==='draft'",
"generation=generationRows[0]||null,qualityAudit=await programQualityAudit(id),draft=pr.status==='draft'",
'admin program quality load')
admin=once(admin,
"${draft?generationReview:''}<div class=\"card\"><h2>Datos del programa</h2>",
"${programQualityAuditHtml(qualityAudit)}${draft?generationReview:''}<div class=\"card\"><h2>Datos del programa</h2>",
'admin program quality render')

# Replace AI modal with preflight context. Missing habitual schedule blocks spending; weekly temporary mismatch is informative.
new_ai=r'''async function openAiProgramGeneration(programId,clientId,scope,days){let isDay=scope==='day',available=(Array.isArray(days)?days:[]).filter(x=>Number.isInteger(Number(x.day_number))&&Number(x.day_number)>0),title=isDay?'Regenerar día con IA':(available.length?'Regenerar rutina con IA':'Generar rutina con IA'),audit=await programQualityAudit(programId),schedule=audit?.schedule||{},safety=audit?.safety||{},learning=audit?.time_learning||{},requiredDays=Number(schedule.required_days),sessionMax=Number(schedule.session_minutes_max),preflightOk=!audit?.unavailable&&Number.isInteger(requiredDays)&&requiredDays>=1&&requiredDays<=7&&Number.isInteger(sessionMax)&&sessionMax>=10,week=Number(schedule.available_days_next_week),weekConflict=Number.isInteger(week)&&week<requiredDays,constraints=Array.isArray(safety.constraints)?safety.constraints:[];$('#modal').innerHTML=`<div class="modal"><div class="card"><div class="row"><div class="grow"><div class="ey">PROGRAMACIÓN IA · PREFLIGHT</div><h2>${esc(title)}</h2></div><button id="closeAiGeneration" class="btn small">✕</button></div><p class="sub">La IA modificará únicamente este borrador. Antes de gastar una llamada, CV Coach verifica el contexto operativo que recibirá.</p>${audit?.unavailable?`<div class="card" style="border-color:#64202b"><b>No se pudo cargar el control de calidad</b><div class="muted">${esc(audit.error||'')}</div></div>`:`<div class="metrics"><div class="metric"><span>Frecuencia vigente</span><b>${esc(schedule.required_days??'—')} días</b></div><div class="metric"><span>Máximo por sesión</span><b>${esc(schedule.session_minutes_max==null?'—':schedule.session_minutes_max+' min')}</b></div><div class="metric"><span>EVITAR</span><b>${esc(constraints.filter(x=>x.action==='avoid').length)}</b></div><div class="metric"><span>PRECAUCIÓN</span><b>${esc(constraints.filter(x=>x.action==='caution').length)}</b></div></div><div class="muted" style="margin-top:8px">Ritmo real: ${Number(learning.sample_count||0)>=3?'factor ×'+esc(learning.applied_factor||1):esc(learning.sample_count||0)+' / 3 sesiones válidas para comenzar a aprender'}.</div>${weekConflict?`<div class="card" style="margin-top:10px;border-color:#62451f"><b>Disponibilidad temporal: ${esc(week)} días esta semana vs ${esc(requiredDays)} habituales</b><div class="muted">No cambia tu configuración habitual. Revisa si conviene adaptar solo esta semana.</div></div>`:''}${constraints.length?`<div class="card" style="margin-top:10px"><b>Restricciones mecánicas vigentes</b><div class="row" style="flex-wrap:wrap;margin-top:8px">${constraints.map(x=>`${trainingConstraintPill(x.action)} <span class="muted">${esc(x.label)}</span>`).join(' ')}</div></div>`:''}`}${!preflightOk?'<div class="card" style="margin-top:10px;border-color:#64202b"><b>GENERACIÓN BLOQUEADA ANTES DE GASTAR IA</b><div class="muted">Define primero días habituales y minutos máximos por sesión en Ficha 360.</div></div>':''}${isDay?`<label>Día a regenerar</label><select id="aiTargetDay" class="input">${available.map(x=>`<option value="${esc(x.day_number)}">Día ${esc(x.day_number)} · ${esc(x.name||'Sin nombre')}</option>`).join('')}</select>`:'<div class="card muted" style="margin-bottom:10px">Se reemplazará la estructura del borrador completo. Los ejercicios marcados EVITAR quedan fuera del catálogo enviado a la IA.</div>'}<div class="row"><button id="cancelAiGeneration" class="btn grow">CANCELAR</button><button id="runAiGeneration" class="btn primary grow" ${(!preflightOk||(isDay&&!available.length))?'disabled':''}>GENERAR BORRADOR</button></div><div id="aiGenerationStatus" class="status muted"></div></div></div>`;let close=()=>$('#modal').innerHTML='';$('#closeAiGeneration').onclick=close;$('#cancelAiGeneration').onclick=close;if(!preflightOk)return;$('#runAiGeneration').onclick=async()=>{let b=$('#runAiGeneration'),s=$('#aiGenerationStatus'),target=isDay?Number($('#aiTargetDay').value):null,requestId=crypto.randomUUID();try{b.disabled=true;b.textContent='GENERANDO…';s.textContent='Analizando contexto, restricciones y presupuesto de tiempo…';let result=await req('/functions/v1/generate-ai-program',{method:'POST',body:JSON.stringify({program_id:programId,client_id:clientId,scope,target_day_number:target,request_id:requestId})});if(!result||result.status!=='applied')throw Error('El backend no confirmó la aplicación del borrador.');close();cache={};aiProgramCapabilityCache=null;toast(isDay?'Día regenerado con IA. Revisa antes de publicar.':'Rutina generada con IA. Revisa antes de publicar.');await programEditor(programId);await openAiGenerationComparison(result.generation_id)}catch(e){s.textContent='No se pudo generar: '+String(e?.message||e);b.disabled=false;b.textContent='GENERAR BORRADOR'}}}
'''
admin=replace_between(admin,'function openAiProgramGeneration(','async function configureAiProgramButtons',new_ai,'admin AI preflight replacement')

# AI persisted review also displays safety audit.
safety_ui=r'''function aiSafetyAuditHtml(value){let a=value&&typeof value==='object'?value:null;if(!a||a.version!=='cv-safety-audit-v1')return '';let blocked=a.overall_status==='blocked',review=a.overall_status==='review',matches=Array.isArray(a.generated_matches)?a.generated_matches:[];return '<div class="card" style="margin-top:12px;border-color:'+(blocked?'#64202b':review?'#62451f':'#245b3c')+'"><div class="row"><div class="grow"><b>AUDITOR DE RESTRICCIONES MECÁNICAS</b><div class="muted">Filtro determinístico · no diagnóstico</div></div><span class="pill '+(blocked?'red':review?'warn':'green')+'">'+(blocked?'BLOQUEADO':review?'REVISAR':'OK')+'</span></div><div class="metrics" style="margin-top:10px"><div class="metric"><span>Restricciones activas</span><b>'+esc(a.active_constraints??0)+'</b></div><div class="metric"><span>EVITAR</span><b>'+esc(a.avoid_constraints??0)+'</b></div><div class="metric"><span>PRECAUCIÓN</span><b>'+esc(a.caution_constraints??0)+'</b></div><div class="metric"><span>Excluidos antes de IA</span><b>'+esc(a.excluded_from_ai_catalog??0)+'</b></div></div>'+(matches.length?'<div class="stack" style="margin-top:10px">'+matches.map(x=>'<div class="row"><div class="muted grow">Día '+esc(x.day_number??'—')+' · '+esc(x.exercise_name||'Ejercicio')+' · '+esc(x.label||x.constraint_code)+'</div>'+trainingConstraintPill(x.action)+'</div>').join('')+'</div>':'')+'<div class="muted" style="margin-top:10px"><b>Regla:</b> '+esc(a.rule||'')+'</div></div>'}'''
admin=once(admin,'function aiScheduleAuditHtml',safety_ui+'function aiScheduleAuditHtml','admin AI safety renderer insertion')
admin=once(admin,
'return rationale+aiScheduleAuditHtml(x.schedule_audit)+aiVolumeAuditHtml(x.volume_audit)}',
'return rationale+aiScheduleAuditHtml(x.schedule_audit)+aiSafetyAuditHtml(x.safety_audit)+aiVolumeAuditHtml(x.volume_audit)}',
'admin AI safety review')
admin=once(admin,
"+aiScheduleAuditHtml(g?.explanations?.schedule_audit)+aiVolumeAuditHtml(g?.explanations?.volume_audit)+aiReviewWarnings",
"+aiScheduleAuditHtml(g?.explanations?.schedule_audit)+aiSafetyAuditHtml(g?.explanations?.safety_audit)+aiVolumeAuditHtml(g?.explanations?.volume_audit)+aiReviewWarnings",
'admin AI comparison safety')
admin=once(admin,
"El backend validará que el programa tenga ejercicios. Si rechaza la operación, el programa no se publicará.",
"El backend validará frecuencia, tiempo máximo, ritmo real aprendido, restricciones EVITAR y estructura del programa. Si algo no cumple, no se publicará.",
'admin publish confirmation quality')

# ---------- CONTRACTS ----------
contracts=once(contracts,
'require(admin, "Disponibilidad de entrenamiento", "current training availability UI")\n',
'require(admin, "Disponibilidad de entrenamiento", "current training availability UI")\nrequire(admin, "Restricciones mecánicas", "structured mechanical constraint UI")\nrequire(admin, "CONTROL DE CALIDAD CV COACH", "program quality audit UI")\nrequire(admin, "PROGRAMACIÓN IA · PREFLIGHT", "AI preflight quality summary")\nrequire(admin, "replace_client_training_constraints_backend", "constraint management RPC")\nrequire(admin, "get_program_quality_audit_backend", "quality audit RPC")\n',
'contracts admin program quality')
contracts=once(contracts,
'require(edge_program, "schedule_preferences", "current schedule preference AI context")\n',
'require(edge_program, "schedule_preferences", "current schedule preference AI context")\nrequire(edge_program, "training_constraints", "structured training constraints context")\nrequire(edge_program, "mechanical_exposures", "exercise exposure safety metadata")\nrequire(edge_program, "cv-safety-audit-v1", "deterministic safety audit")\nrequire(edge_program, "time_learning", "client-specific time learning")\n',
'contracts edge program quality')

EDGE.write_text(edge,encoding='utf-8')
ADMIN.write_text(admin,encoding='utf-8')
CONTRACTS.write_text(contracts,encoding='utf-8')
print('PROGRAM_QUALITY_GUARDRAILS_V2_PATCH_OK')
