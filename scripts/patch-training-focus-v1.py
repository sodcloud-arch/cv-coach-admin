from pathlib import Path


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 marker, found {count}")
    return text.replace(old, new, 1)

# CLIENT PORTAL
client_path = Path('client-portal/index.html')
client = client_path.read_text(encoding='utf-8')

old = "const onboardingSleepItems=[['5','≤5 horas'],['6','6 horas'],['7','7 horas'],['8','8 horas'],['9','9+ horas']];const onboardingStepItems=[['4000','<5.000'],['6500','5–8k'],['9000','8–10k'],['11000','10–12k'],['13000','12k+']];const onboardingEquipmentItems=['Gimnasio completo','Máquinas','Mancuernas','Barras','Bandas','Peso corporal','Entreno en casa'];const onboardingDayItems=['Lunes','Martes','Miércoles','Jueves','Viernes','Sábado','Domingo'];"
new = "const onboardingSleepItems=[['5','≤5 horas'],['6','6 horas'],['7','7 horas'],['8','8 horas'],['9','9+ horas']];const onboardingStepItems=[['4000','<5.000'],['6500','5–8k'],['9000','8–10k'],['11000','10–12k'],['13000','12k+']];const onboardingEquipmentItems=['Gimnasio completo','Máquinas','Mancuernas','Barras','Bandas','Peso corporal','Entreno en casa'];const onboardingMuscleFocusItems=[['full_body','Cuerpo completo'],['glutes','Glúteos'],['quadriceps','Cuádriceps'],['hamstrings','Isquiotibiales'],['calves','Pantorrillas'],['back','Espalda'],['chest','Pecho'],['shoulders','Hombros'],['biceps','Bíceps'],['triceps','Tríceps'],['core','Abdomen / Core']];const onboardingDayItems=['Lunes','Martes','Miércoles','Jueves','Viernes','Sábado','Domingo'];"
client = replace_once(client, old, new, 'client focus items')

marker = "function onboardingHTML(){"
helpers = "function onboardingMuscleFocusChoices(raw){const selected=new Set(Array.isArray(raw)?raw:onboardingParts(raw));return `<input id=\"ob_muscle_focus\" type=\"hidden\" required value=\"${esc([...selected].join(', '))}\"><div class=\"onboardingChoices multiple\" role=\"group\" aria-label=\"Foco muscular\" data-muscle-focus=\"true\">${onboardingMuscleFocusItems.map(([value,label])=>`<button type=\"button\" class=\"onboardingChoice compact ${selected.has(value)?'selected':''}\" data-value=\"${value}\" aria-pressed=\"${selected.has(value)}\" onclick=\"onboardingMuscleFocusChoice(this)\"><strong>${label}</strong></button>`).join('')}</div>`}function onboardingMuscleFocusChoice(button){const group=button?.parentElement,input=document.getElementById('ob_muscle_focus');if(!group||!input)return;const value=button.dataset.value;if(value==='full_body'){group.querySelectorAll('.onboardingChoice').forEach(x=>{const selected=x===button;x.classList.toggle('selected',selected);x.setAttribute('aria-pressed',String(selected))})}else{const full=group.querySelector('[data-value=\"full_body\"]');if(full){full.classList.remove('selected');full.setAttribute('aria-pressed','false')}button.classList.toggle('selected');button.setAttribute('aria-pressed',String(button.classList.contains('selected')))}const values=[...group.querySelectorAll('.onboardingChoice.selected')].map(x=>x.dataset.value).filter(Boolean);input.value=values.join(', ');input.dispatchEvent(new Event('input',{bubbles:true}))}function onboardingMuscleFocusValue(){const raw=onboardingText('ob_muscle_focus','el foco muscular');const values=onboardingParts(raw);if(!values.length)throw new Error('Completa: el foco muscular.');if(values.includes('full_body')&&values.length!==1)throw new Error('Cuerpo completo no se puede combinar con focos específicos.');return values}"
client = replace_once(client, marker, helpers + marker, 'client focus helpers')

old = "<label for=\"ob_secondary_goal\">Objetivos secundarios · opcional</label>${onboardingGoalChoices('ob_secondary_goal',v('secondary_goal'),true)}<h2>CUÉNTANOS SOBRE TU RUTINA</h2>"
new = "<label for=\"ob_secondary_goal\">Objetivos secundarios · opcional</label>${onboardingGoalChoices('ob_secondary_goal',v('secondary_goal'),true)}<div id=\"ob_muscle_focus_block\"><label>¿Qué grupos musculares te gustaría priorizar? *</label><div class=\"hint\">Puedes marcar varios. Si quieres un desarrollo equilibrado, elige Cuerpo completo.</div>${onboardingMuscleFocusChoices(a('muscle_focus'))}</div><h2>CUÉNTANOS SOBRE TU RUTINA</h2>"
client = replace_once(client, old, new, 'client focus UI')

old = "notes_for_coach:onboardingText('ob_notes','las notas para tu coach',false)};"
new = "notes_for_coach:onboardingText('ob_notes','las notas para tu coach',false),muscle_focus:onboardingMuscleFocusValue()};"
client = replace_once(client, old, new, 'client submit focus')

old = " ]:step===1?[\n ['ob_primary_goal','el objetivo principal']\n ]:["
new = " ]:step===1?[\n ['ob_primary_goal','el objetivo principal'],['ob_muscle_focus','el foco muscular']\n ]:["
client = replace_once(client, old, new, 'client wizard validation')

old = "secondaryOther=document.getElementById('ob_secondary_goal_other_wrap'),routineHeading=headings[1];"
new = "secondaryOther=document.getElementById('ob_secondary_goal_other_wrap'),muscleFocusBlock=document.getElementById('ob_muscle_focus_block'),routineHeading=headings[1];"
client = replace_once(client, old, new, 'client wizard variable')

old = "steps[1].append(primary,secondaryLabel,secondaryInput,secondaryGroup,secondaryOther);"
new = "steps[1].append(primary,secondaryLabel,secondaryInput,secondaryGroup,secondaryOther,muscleFocusBlock);"
client = replace_once(client, old, new, 'client wizard focus placement')

client_path.write_text(client, encoding='utf-8')

# ADMIN
admin_path = Path('index.html')
admin = admin_path.read_text(encoding='utf-8')

marker = "async function clientDetail(id){"
helpers = "const trainingFocusItems=[['full_body','Cuerpo completo'],['glutes','Glúteos'],['quadriceps','Cuádriceps'],['hamstrings','Isquiotibiales'],['calves','Pantorrillas'],['back','Espalda'],['chest','Pecho'],['shoulders','Hombros'],['biceps','Bíceps'],['triceps','Tríceps'],['core','Abdomen / Core']];function trainingFocusLabel(value){return trainingFocusItems.find(x=>x[0]===value)?.[1]||value}function trainingFocusSection(pref){let focus=Array.isArray(pref?.muscle_focus)?pref.muscle_focus:[];return `<section style=\"margin:18px 0\"><div class=\"row\"><h2 class=\"grow\">Foco de entrenamiento</h2><button id=\"manageTrainingFocus\" class=\"btn primary small\">CAMBIAR FOCO</button></div><div class=\"card\">${focus.length?`<div class=\"row\" style=\"flex-wrap:wrap\">${focus.map(x=>`<span class=\"pill blue\">${esc(trainingFocusLabel(x))}</span>`).join('')}</div><div class=\"muted\" style=\"margin-top:8px\">Preferencia vigente · Fuente: ${esc(pref?.source||'—')} · Actualizado: ${esc(pref?.updated_at?new Date(pref.updated_at).toLocaleString('es-CL'):'—')}</div>`:'<div class=\"muted\">Sin foco muscular definido. La IA no debe inventarlo.</div>'}</div></section>`}function openTrainingFocusModal(clientId,pref){let current=new Set(Array.isArray(pref?.muscle_focus)?pref.muscle_focus:[]);$('#modal').innerHTML=`<div class=\"modal\"><div class=\"card\"><div class=\"row\"><div class=\"grow\"><div class=\"ey\">PROGRAMACIÓN</div><h2>Foco muscular vigente</h2></div><button id=\"closeTrainingFocus\" class=\"btn small\">✕</button></div><p class=\"sub\">Selecciona uno o varios grupos. Cuerpo completo es exclusivo. Este dato será usado por futuras generaciones IA; no modifica automáticamente una rutina ya publicada.</p><div id=\"trainingFocusOptions\" class=\"clients\">${trainingFocusItems.map(([value,label])=>`<button type=\"button\" class=\"btn trainingFocusOption ${current.has(value)?'good':''}\" data-value=\"${value}\" aria-pressed=\"${current.has(value)}\">${esc(label)}</button>`).join('')}</div><button id=\"saveTrainingFocus\" class=\"btn primary\" style=\"width:100%;margin-top:12px\">GUARDAR FOCO</button><div id=\"trainingFocusStatus\" class=\"status muted\"></div></div></div>`;let close=()=>$('#modal').innerHTML='';$('#closeTrainingFocus').onclick=close;let sync=()=>{$$('#trainingFocusOptions .trainingFocusOption').forEach(b=>{let on=current.has(b.dataset.value);b.classList.toggle('good',on);b.setAttribute('aria-pressed',String(on))})};$$('#trainingFocusOptions .trainingFocusOption').forEach(b=>b.onclick=()=>{let value=b.dataset.value;if(value==='full_body'){current=new Set(['full_body'])}else{current.delete('full_body');current.has(value)?current.delete(value):current.add(value)}sync()});$('#saveTrainingFocus').onclick=async()=>{let b=$('#saveTrainingFocus'),out=$('#trainingFocusStatus');try{b.disabled=true;out.textContent='Guardando…';let values=[...current];if(!values.length)throw Error('Selecciona al menos un foco muscular.');let result=await req('/rest/v1/rpc/set_client_training_focus_backend',{method:'POST',body:JSON.stringify({p_actor_id:me.id,p_client_id:clientId,p_muscle_focus:values})});if(!result?.client_id)throw Error('El backend no confirmó el cambio.');close();cache={};toast('Foco muscular actualizado.');await clientDetail(clientId)}catch(e){out.textContent='No se pudo guardar: '+String(e?.message||e);b.disabled=false}}}"
admin = replace_once(admin, marker, helpers + marker, 'admin focus helpers')

old = "billingRows,weeklyCheckins,weeklyProgramReviews]=await Promise.all(["
new = "billingRows,weeklyCheckins,weeklyProgramReviews,trainingPreferences]=await Promise.all(["
admin = replace_once(admin, old, new, 'admin preference destructuring')

old = "table('weekly_program_reviews','client_id=eq.'+encodeURIComponent(id)+'&select=*&order=week_start.desc,updated_at.desc&limit=8').catch(()=>[]) ]),onboardingMap="
new = "table('weekly_program_reviews','client_id=eq.'+encodeURIComponent(id)+'&select=*&order=week_start.desc,updated_at.desc&limit=8').catch(()=>[]),table('client_training_preferences','client_id=eq.'+encodeURIComponent(id)+'&select=*').catch(()=>[]) ]),onboardingMap="
admin = replace_once(admin, old, new, 'admin preference query')

old = "['notes_for_coach','Notas para el coach','notes_for_coach']]"
new = "['notes_for_coach','Notas para el coach','notes_for_coach'],['muscle_focus','Foco muscular','muscle_focus']]"
admin = replace_once(admin, old, new, 'admin onboarding review field')

old = "${onboardingHtml}${cvEvolutionHtml}${billingHtml}"
new = "${onboardingHtml}${trainingFocusSection(trainingPreferences[0]||null)}${cvEvolutionHtml}${billingHtml}"
admin = replace_once(admin, old, new, 'admin focus section')

old = "$('#openMeasurement').onclick=()=>openMeasurementModal(id);"
new = "if($('#manageTrainingFocus'))$('#manageTrainingFocus').onclick=()=>openTrainingFocusModal(id,trainingPreferences[0]||null);$('#openMeasurement').onclick=()=>openMeasurementModal(id);"
admin = replace_once(admin, old, new, 'admin focus binding')

admin_path.write_text(admin, encoding='utf-8')

print('training focus patch applied')
