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

# Edge: current schedule preference overrides historical onboarding for generation.
edge=once(edge,
'''  const trainingPreferences = compactRecord(root.training_preferences, [
    "muscle_focus",
  ]);
  const weekly = compactRecord(root.latest_weekly_checkin, [''',
'''  const trainingPreferences = compactRecord(root.training_preferences, [
    "muscle_focus",
  ]);
  const schedulePreferences = compactRecord(root.schedule_preferences, [
    "training_days_per_week",
    "session_minutes",
    "source",
  ]);
  if (schedulePreferences.training_days_per_week !== undefined) {
    onboarding.training_days_per_week = schedulePreferences.training_days_per_week;
  }
  if (schedulePreferences.session_minutes !== undefined) {
    onboarding.session_minutes = schedulePreferences.session_minutes;
  }
  const weekly = compactRecord(root.latest_weekly_checkin, [''',
'edge schedule preferences sanitize')
edge=once(edge,
'''      training_preferences: trainingPreferences,
      latest_weekly_checkin: weekly,''',
'''      training_preferences: trainingPreferences,
      schedule_preferences: schedulePreferences,
      latest_weekly_checkin: weekly,''',
'edge schedule preferences output')
edge=once(edge,
'''  const onboarding = isObject(trainingContext.onboarding) ? trainingContext.onboarding : {};
  const weekly = isObject(trainingContext.latest_weekly_checkin) ? trainingContext.latest_weekly_checkin : {};''',
'''  const onboarding = isObject(trainingContext.onboarding) ? trainingContext.onboarding : {};
  const schedulePreferences = isObject(trainingContext.schedule_preferences) ? trainingContext.schedule_preferences : {};
  const weekly = isObject(trainingContext.latest_weekly_checkin) ? trainingContext.latest_weekly_checkin : {};''',
'edge audit schedule source')
edge=once(edge,
'''  const declaredDays = strictInteger(onboarding.training_days_per_week);
  const maxSessionMinutes = strictInteger(onboarding.session_minutes);''',
'''  const declaredDays = strictInteger(schedulePreferences.training_days_per_week ?? onboarding.training_days_per_week);
  const maxSessionMinutes = strictInteger(schedulePreferences.session_minutes ?? onboarding.session_minutes);''',
'edge audit current schedule priority')
edge=once(edge,
'''3. Respeta equipamiento, disponibilidad, duración de sesión, experiencia y objetivo cuando estén presentes. training_days_per_week es la frecuencia semanal objetivo y session_minutes es el MÁXIMO de minutos disponibles por sesión, no una sugerencia.''',
'''3. Respeta equipamiento, disponibilidad, duración de sesión, experiencia y objetivo cuando estén presentes. client_training_context.schedule_preferences representa la disponibilidad VIGENTE y tiene prioridad sobre el onboarding histórico. training_days_per_week es la frecuencia semanal objetivo y session_minutes es el MÁXIMO de minutos disponibles por sesión, no una sugerencia.''',
'edge prompt current schedule priority')

# Admin: helper + Ficha 360 UI.
schedule_ui=r'''function trainingScheduleNumber(value,min,max){let n=Number(value);return Number.isInteger(n)&&n>=min&&n<=max?n:null}function trainingScheduleEffective(pref,onboarding){let days=trainingScheduleNumber(pref?.training_days_per_week,1,7)??trainingScheduleNumber(onboarding?.training_days_per_week,1,7)??trainingScheduleNumber(onboarding?.weekly_availability,1,7),minutes=trainingScheduleNumber(pref?.session_minutes,10,240)??trainingScheduleNumber(onboarding?.session_minutes,10,240)??trainingScheduleNumber(onboarding?.session_duration_minutes,10,240);return {days,minutes,source:pref?.client_id?(pref.source||'coach'):'onboarding'}}function trainingScheduleSection(pref,onboarding){let s=trainingScheduleEffective(pref,onboarding),source=s.source==='coach'?'Actualizada por coach':s.source==='client'?'Actualizada por cliente':'Onboarding';return `<section style="margin:18px 0"><div class="row"><h2 class="grow">Disponibilidad de entrenamiento</h2><button id="manageTrainingSchedule" class="btn primary small">CAMBIAR DISPONIBILIDAD</button></div><div class="card"><div class="metrics nutritionMetrics"><div class="metric"><span>Días por semana</span><b>${esc(s.days??'—')}</b></div><div class="metric"><span>Máximo por sesión</span><b>${esc(s.minutes==null?'—':s.minutes+' min')}</b></div></div><div class="muted" style="margin-top:8px">Fuente vigente: ${esc(source)}${pref?.updated_at?' · Actualizado: '+esc(new Date(pref.updated_at).toLocaleString('es-CL')):''}. La IA y la publicación usan estos valores; el onboarding original no se modifica.</div></div></section>`}function openTrainingScheduleModal(clientId,pref,onboarding){let s=trainingScheduleEffective(pref,onboarding);$('#modal').innerHTML=`<div class="modal"><div class="card"><div class="row"><div class="grow"><div class="ey">PROGRAMACIÓN</div><h2>Disponibilidad vigente</h2></div><button id="closeTrainingSchedule" class="btn small">✕</button></div><p class="sub">Actualiza la disponibilidad actual del cliente. No cambia sus respuestas históricas del onboarding. Las futuras generaciones y la publicación respetarán estos límites.</p><label>Días de entrenamiento por semana</label><select id="trainingScheduleDays" class="input">${[1,2,3,4,5,6,7].map(n=>`<option value="${n}" ${n===s.days?'selected':''}>${n} día${n===1?'':'s'}</option>`).join('')}</select><label>Máximo disponible por sesión (minutos)</label><input id="trainingScheduleMinutes" class="input" type="number" min="10" max="240" step="1" value="${esc(s.minutes??'')}" placeholder="Ej. 45"><div class="card muted" style="margin:8px 0 12px">Ejemplo: 5 días · 45 min significa exactamente 5 sesiones por semana y ninguna propuesta publicable puede superar 45 min por sesión.</div><button id="saveTrainingSchedule" class="btn primary" style="width:100%">GUARDAR DISPONIBILIDAD</button><div id="trainingScheduleStatus" class="status muted"></div></div></div>`;let close=()=>$('#modal').innerHTML='';$('#closeTrainingSchedule').onclick=close;$('#saveTrainingSchedule').onclick=async()=>{let b=$('#saveTrainingSchedule'),out=$('#trainingScheduleStatus');try{b.disabled=true;out.textContent='Guardando…';let days=Number($('#trainingScheduleDays').value),minutes=Number($('#trainingScheduleMinutes').value);if(!Number.isInteger(days)||days<1||days>7)throw Error('Los días deben estar entre 1 y 7.');if(!Number.isInteger(minutes)||minutes<10||minutes>240)throw Error('Los minutos deben ser un entero entre 10 y 240.');let result=await req('/rest/v1/rpc/set_client_training_schedule_backend',{method:'POST',body:JSON.stringify({p_actor_id:me.id,p_client_id:clientId,p_training_days_per_week:days,p_session_minutes:minutes})});if(!result?.client_id)throw Error('El backend no confirmó el cambio.');let verify=await table('client_training_schedule_preferences','client_id=eq.'+encodeURIComponent(clientId)+'&select=training_days_per_week,session_minutes,source,updated_at'),saved=verify?.[0];if(Number(saved?.training_days_per_week)!==days||Number(saved?.session_minutes)!==minutes)throw Error('Supabase no confirmó la persistencia de la disponibilidad.');close();cache={};toast('Disponibilidad de entrenamiento actualizada.');await clientDetail(clientId)}catch(e){out.textContent='No se pudo guardar: '+String(e?.message||e);b.disabled=false}}}'''
admin=once(admin,'const trainingFocusItems=',schedule_ui+'const trainingFocusItems=','admin schedule UI insertion')
admin=once(admin,
"table('client_training_preferences','client_id=eq.'+encodeURIComponent(id)+'&select=*').catch(()=>[]) ]),onboardingMap=",
"table('client_training_preferences','client_id=eq.'+encodeURIComponent(id)+'&select=*').catch(()=>[]),table('client_training_schedule_preferences','client_id=eq.'+encodeURIComponent(id)+'&select=*').catch(()=>[]) ]),onboardingMap=",
'admin schedule table query')
admin=once(admin,
'weeklyProgramReviews,trainingPreferences]=await Promise.all',
'weeklyProgramReviews,trainingPreferences,trainingSchedulePreferences]=await Promise.all',
'admin schedule destructure')
admin=once(admin,
'${onboardingHtml}${trainingFocusSection(trainingPreferences[0]||null)}${cvEvolutionHtml}',
'${onboardingHtml}${trainingFocusSection(trainingPreferences[0]||null)}${trainingScheduleSection(trainingSchedulePreferences[0]||null,onboardingMap)}${cvEvolutionHtml}',
'admin schedule section render')
admin=once(admin,
"if($('#manageTrainingFocus'))$('#manageTrainingFocus').onclick=()=>openTrainingFocusModal(id,trainingPreferences[0]||null);$('#openMeasurement').onclick=",
"if($('#manageTrainingFocus'))$('#manageTrainingFocus').onclick=()=>openTrainingFocusModal(id,trainingPreferences[0]||null);if($('#manageTrainingSchedule'))$('#manageTrainingSchedule').onclick=()=>openTrainingScheduleModal(id,trainingSchedulePreferences[0]||null,onboardingMap);$('#openMeasurement').onclick=",
'admin schedule handler')

# Contract markers.
contracts=once(contracts,
'require(admin, "AUDITOR DE TIEMPO Y FRECUENCIA", "hard schedule audit UI")\n',
'require(admin, "AUDITOR DE TIEMPO Y FRECUENCIA", "hard schedule audit UI")\nrequire(admin, "Disponibilidad de entrenamiento", "current training availability UI")\nrequire(admin, "set_client_training_schedule_backend", "current training availability RPC")\n',
'contracts admin current schedule')
contracts=once(contracts,
'require(edge_program, "buildScheduleAudit", "hard schedule audit builder")\n',
'require(edge_program, "buildScheduleAudit", "hard schedule audit builder")\nrequire(edge_program, "schedule_preferences", "current schedule preference AI context")\n',
'contracts edge current schedule')

EDGE.write_text(edge,encoding='utf-8')
ADMIN.write_text(admin,encoding='utf-8')
CONTRACTS.write_text(contracts,encoding='utf-8')
print('CURRENT_TRAINING_SCHEDULE_PATCH_OK')
