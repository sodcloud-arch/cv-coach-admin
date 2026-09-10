from pathlib import Path

path = Path('index.html')
text = path.read_text(encoding='utf-8')
original = text

anchor = "function aiReviewDate(value){if(!value)return '—';let d=new Date(String(value));return Number.isNaN(d.getTime())?'—':d.toLocaleString('es-CL')}async function programEditor(id){try{"
helpers = r'''function aiReviewDate(value){if(!value)return '—';let d=new Date(String(value));return Number.isNaN(d.getTime())?'—':d.toLocaleString('es-CL')}let aiProgramCapabilityCache=null;async function aiProgramCapabilities(force=false){if(aiProgramCapabilityCache&&!force)return aiProgramCapabilityCache;try{let x=await req('/functions/v1/generate-ai-program',{method:'POST',body:JSON.stringify({action:'capabilities'})});return aiProgramCapabilityCache={configured:x?.configured===true,model:x?.model||null,error:null}}catch(e){return aiProgramCapabilityCache={configured:false,model:null,error:String(e?.message||e||'No disponible')}}}function openAiProgramGeneration(programId,clientId,scope,days){let isDay=scope==='day',available=(Array.isArray(days)?days:[]).filter(x=>Number.isInteger(Number(x.day_number))&&Number(x.day_number)>0),title=isDay?'Regenerar día con IA':(available.length?'Regenerar rutina con IA':'Generar rutina con IA');$('#modal').innerHTML=`<div class="modal"><div class="card"><div class="row"><div class="grow"><div class="ey">PROGRAMACIÓN IA</div><h2>${esc(title)}</h2></div><button id="closeAiGeneration" class="btn small">✕</button></div><p class="sub">La IA modificará únicamente este borrador. No publica ni aprueba el programa: después debes revisar el resultado y usar PUBLICAR PROGRAMA por separado.</p>${isDay?`<label>Día a regenerar</label><select id="aiTargetDay" class="input">${available.map(x=>`<option value="${esc(x.day_number)}">Día ${esc(x.day_number)} · ${esc(x.name||'Sin nombre')}</option>`).join('')}</select>`:'<div class="card muted" style="margin-bottom:10px">Se reemplazará la estructura del borrador completo por una nueva propuesta basada en onboarding, recuperación reciente, objetivo, disponibilidad, equipamiento y catálogo activo.</div>'}<div class="row"><button id="cancelAiGeneration" class="btn grow">CANCELAR</button><button id="runAiGeneration" class="btn primary grow" ${isDay&&!available.length?'disabled':''}>GENERAR BORRADOR</button></div><div id="aiGenerationStatus" class="status muted"></div></div></div>`;let close=()=>$('#modal').innerHTML='';$('#closeAiGeneration').onclick=close;$('#cancelAiGeneration').onclick=close;$('#runAiGeneration').onclick=async()=>{let b=$('#runAiGeneration'),s=$('#aiGenerationStatus'),target=isDay?Number($('#aiTargetDay').value):null,requestId=crypto.randomUUID();try{b.disabled=true;b.textContent='GENERANDO…';s.textContent='Analizando contexto y construyendo borrador seguro…';let result=await req('/functions/v1/generate-ai-program',{method:'POST',body:JSON.stringify({program_id:programId,client_id:clientId,scope,target_day_number:target,request_id:requestId})});if(!result||result.status!=='applied')throw Error('El backend no confirmó la aplicación del borrador.');close();cache={};aiProgramCapabilityCache=null;toast(isDay?'Día regenerado con IA. Revisa antes de publicar.':'Rutina generada con IA. Revisa antes de publicar.');await programEditor(programId)}catch(e){s.textContent='No se pudo generar: '+String(e?.message||e);b.disabled=false;b.textContent='GENERAR BORRADOR'}}}async function configureAiProgramButtons(programId,clientId,days){let routine=$('#regenerateRoutine'),day=$('#regenerateDay');if(!routine&&!day)return;let caps=await aiProgramCapabilities();if(!document.body.contains(routine||day))return;if(!caps.configured){[routine,day].filter(Boolean).forEach(b=>{b.disabled=true;b.title='Proveedor IA server-side pendiente de configuración'});return}if(routine){routine.disabled=false;routine.title='Generar una nueva propuesta sobre el borrador';routine.textContent=(days?.length?'REGENERAR RUTINA':'GENERAR RUTINA');routine.onclick=()=>openAiProgramGeneration(programId,clientId,'program',days)}if(day){let hasDays=Array.isArray(days)&&days.length>0;day.disabled=!hasDays;day.title=hasDays?'Regenerar un día del borrador':'Agrega un día o genera primero la rutina';if(hasDays)day.onclick=()=>openAiProgramGeneration(programId,clientId,'day',days)}}async function programEditor(id){try{'''
if anchor not in text:
    raise SystemExit('AI helper anchor not found')
text = text.replace(anchor, helpers, 1)

old_buttons = '''<button id="regenerateDay" class="btn small" disabled title="La generación segura aún no está disponible">REGENERAR DÍA</button><button id="regenerateRoutine" class="btn small" disabled title="La generación segura aún no está disponible">REGENERAR RUTINA</button>'''
new_buttons = '''<button id="regenerateDay" class="btn small" disabled title="Verificando disponibilidad IA…">REGENERAR DÍA</button><button id="regenerateRoutine" class="btn small" disabled title="Verificando disponibilidad IA…">REGENERAR RUTINA</button>'''
if old_buttons not in text:
    raise SystemExit('AI buttons anchor not found')
text = text.replace(old_buttons, new_buttons, 1)

old_tail = ";$('#publishProgram').onclick=()=>confirmPublish(id,pr.name)}catch(e){"
new_tail = ";configureAiProgramButtons(id,pr.client_id,days);$('#publishProgram').onclick=()=>confirmPublish(id,pr.name)}catch(e){"
if old_tail not in text:
    raise SystemExit('programEditor tail anchor not found')
text = text.replace(old_tail, new_tail, 1)

if text == original:
    raise SystemExit('No changes made')
path.write_text(text, encoding='utf-8')
print('AI program UI patch applied')
