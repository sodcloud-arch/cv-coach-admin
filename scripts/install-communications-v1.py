from pathlib import Path

path = Path('index.html')
text = path.read_text()

def replace_once(old, new, label):
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected 1 anchor, found {count}')
    text = text.replace(old, new, 1)

replace_once(
    "let sess=null,me=null,view='dashboard',cache={},clientDetailToken=0,reportClientId=null,attentionQueueLastError=null;",
    "let sess=null,me=null,view='dashboard',cache={},clientDetailToken=0,reportClientId=null,attentionQueueLastError=null,communicationClientId=null,communicationSeed=null;",
    'communication global state'
)

replace_once(
    '<button data-v="retention">🛡 Retención</button><button data-v="library">▤ Biblioteca</button>',
    '<button data-v="retention">🛡 Retención</button><button data-v="communications">💬 Comunicaciones</button><button data-v="library">▤ Biblioteca</button>',
    'communication navigation'
)

replace_once(
    "retention:'Retención',library:'Biblioteca'",
    "retention:'Retención',communications:'Comunicaciones',library:'Biblioteca'",
    'communication title mapping'
)

replace_once(
    "if(view==='retention')await retention();if(view==='library')await library();",
    "if(view==='retention')await retention();if(view==='communications')await communications();if(view==='library')await library();",
    'communication render dispatch'
)

replace_once(
    '<button class="btn small retentionCopy" data-id="'+"'+esc(row.client_id)+'"+'">COPIAR SEGUIMIENTO</button></div><div class="status muted retentionCopyStatus"></div></article>',
    '<button class="btn small retentionCopy" data-id="'+"'+esc(row.client_id)+'"+'">COPIAR SEGUIMIENTO</button><button class="btn small retentionPrepare" data-id="'+"'+esc(row.client_id)+'"+'">PREPARAR WHATSAPP</button></div><div class="status muted retentionCopyStatus"></div></article>',
    'retention prepare whatsapp button'
)

replace_once(
    "$$('.retentionReport').forEach(button=>button.onclick=()=>{reportClientId=button.dataset.id;setView('reports')});\n    $$('.retentionCopy').forEach(button=>button.onclick=async()=>{",
    "$$('.retentionReport').forEach(button=>button.onclick=()=>{reportClientId=button.dataset.id;setView('reports')});\n    $$('.retentionPrepare').forEach(button=>button.onclick=()=>{let row=queue.find(x=>x.client_id===button.dataset.id);if(!row)return;communicationClientId=row.client_id;communicationSeed={client_id:row.client_id,message_type:'retention_followup',body:followupText(row,commercialFor(row.client_id)),idempotency_key:'retention:'+row.client_id+':'+chileToday(),source:'retention',source_ref:'attention_queue'};setView('communications')});\n    $$('.retentionCopy').forEach(button=>button.onclick=async()=>{",
    'retention prepare handler'
)

communications_js = r'''
function communicationStatusPill(status){
  let value=String(status||'draft').toLowerCase();
  let label={draft:'Borrador',blocked:'Bloqueado',ready:'Listo · NO ENVIADO',archived:'Archivado'}[value]||value;
  let cls=value==='ready'?'green':value==='blocked'?'red':value==='archived'?'blue':'warn';
  return '<span class="pill '+cls+'">'+esc(label)+'</span>';
}
function communicationDate(value){
  if(!value)return '—';
  let d=new Date(String(value));
  return Number.isNaN(d.getTime())?'—':d.toLocaleString('es-CL',{timeZone:'America/Santiago'});
}
function communicationTime(value,fallback){
  let raw=String(value||fallback||'');
  return /^\d{2}:\d{2}/.test(raw)?raw.slice(0,5):fallback;
}
function communicationPhoneValid(value){return /^\+[1-9][0-9]{7,14}$/.test(String(value||'').trim())}
function communicationRpcRow(result){return Array.isArray(result)?result[0]:result}
function communicationNewIdempotency(clientId,type){
  let suffix=(crypto&&typeof crypto.randomUUID==='function')?crypto.randomUUID():String(Date.now())+'-'+Math.random().toString(36).slice(2);
  return 'manual:'+type+':'+clientId+':'+suffix;
}
async function communications(){
  let d=await core(),profiles=d.profiles||[],prefs=[],drafts=[];
  try{[prefs,drafts]=await Promise.all([
    table('communication_preferences','select=*&order=updated_at.desc'),
    table('communication_drafts','select=*&order=created_at.desc&limit=250')
  ])}catch(error){
    $('#content').innerHTML='<div class="ey">COMUNICACIONES</div><h1 class="title">WhatsApp · Preparación segura</h1><div class="card" style="border-color:#64202b"><b>No se pudo cargar Comunicaciones</b><div class="muted">'+esc(error.message)+'</div></div>';
    return;
  }
  let selected=profiles.find(x=>x.id===communicationClientId)||profiles[0]||null;
  let prefFor=id=>prefs.find(x=>x.client_id===id)||null;
  let clientDrafts=id=>drafts.filter(x=>x.client_id===id);
  let opted=prefs.filter(x=>x.whatsapp_opt_in===true).length,blocked=drafts.filter(x=>x.status==='blocked').length,ready=drafts.filter(x=>x.status==='ready').length;

  $('#content').innerHTML='<div class="head"><div><div class="ey">COMUNICACIONES V1</div><h1 class="title">WhatsApp · Preparación segura</h1><p class="sub">Consentimiento, preferencias y borradores. En esta versión no existe envío automático ni botón de envío.</p></div></div>'+
    '<div class="card" style="margin:12px 0;border-color:#274a73"><b>Modo seguro activo</b><div class="muted" style="margin-top:6px">READY significa elegible para una futura integración; no significa enviado. Nunca marques opt-in sin confirmación real del cliente.</div></div>'+
    '<div class="kpis"><div class="kpi"><div class="l">Clientes</div><div class="n">'+esc(profiles.length)+'</div></div><div class="kpi"><div class="l">Opt-in WhatsApp</div><div class="n">'+esc(opted)+'</div></div><div class="kpi"><div class="l">Borradores listos</div><div class="n">'+esc(ready)+'</div></div><div class="kpi"><div class="l">Borradores bloqueados</div><div class="n">'+esc(blocked)+'</div></div><div class="kpi"><div class="l">Enviados desde V1</div><div class="n">0</div></div></div>'+
    '<div class="filters"><input id="communicationSearch" class="input" placeholder="Buscar cliente…"><select id="communicationClient" class="input"></select><select id="communicationDraftStatus" class="input"><option value="">Todos los borradores</option><option value="ready">Listos · NO ENVIADOS</option><option value="blocked">Bloqueados</option><option value="draft">Borradores</option><option value="archived">Archivados</option></select></div><div id="communicationBody"></div>';

  let search=$('#communicationSearch'),clientSelect=$('#communicationClient'),statusFilter=$('#communicationDraftStatus'),body=$('#communicationBody');
  function drawClientSelect(){
    let q=search.value.trim().toLowerCase(),rows=profiles.filter(p=>cname(p).toLowerCase().includes(q));
    if(selected&&!rows.some(x=>x.id===selected.id))selected=rows[0]||null;
    clientSelect.innerHTML=rows.length?rows.map(p=>'<option value="'+esc(p.id)+'" '+(p.id===selected?.id?'selected':'')+'>'+esc(cname(p))+'</option>').join(''):'<option value="">Sin clientes</option>';
    if(selected&&rows.some(x=>x.id===selected.id))clientSelect.value=selected.id;
  }
  function renderSelected(){
    let id=clientSelect.value;
    if(!id){communicationClientId=null;body.innerHTML='<div class="card muted">No hay clientes disponibles.</div>';return}
    communicationClientId=id;selected=profiles.find(x=>x.id===id)||null;
    if(!selected){body.innerHTML='<div class="card muted">El cliente ya no está disponible.</div>';return}
    let pref=prefFor(id),rows=clientDrafts(id),status=statusFilter.value;
    if(status)rows=rows.filter(x=>x.status===status);
    let phone=pref?.whatsapp_phone_e164||selected.phone||'—';
    body.innerHTML='<div class="grid"><section><div class="row"><h2 class="grow">Preferencia WhatsApp</h2><button id="manageCommunicationPreference" class="btn primary small">GESTIONAR CONSENTIMIENTO</button></div><div class="card"><div class="metrics nutritionMetrics">'+
      reportMetric('Opt-in',pref?.whatsapp_opt_in===true?'Sí':'No')+reportMetric('Teléfono',phone)+reportMetric('Fuente',pref?.consent_source||'—')+reportMetric('Última actualización',communicationDate(pref?.updated_at))+
      '</div><div class="muted" style="margin-top:10px">Quiet hours: '+esc(communicationTime(pref?.quiet_hours_start,'21:00'))+' → '+esc(communicationTime(pref?.quiet_hours_end,'08:00'))+' · Zona: '+esc(pref?.timezone||'America/Santiago')+'</div><div class="muted" style="margin-top:6px">Opt-in: '+esc(communicationDate(pref?.whatsapp_opt_in_at))+' · Opt-out: '+esc(communicationDate(pref?.whatsapp_opt_out_at))+'</div><div class="muted" style="margin-top:6px">Evidencia/nota: '+esc(pref?.consent_note||'Sin nota registrada')+'</div></div></section><section><div class="row"><h2 class="grow">Preparación</h2><button id="newCommunicationDraft" class="btn good small">+ NUEVO BORRADOR</button></div><div class="card"><b>Integración externa desactivada en V1</b><div class="muted" style="margin-top:6px">Los borradores se guardan en CV Coach. Ningún dato se envía a Peach/WhatsApp desde esta pantalla.</div></div></section></div>'+
      '<section style="margin-top:16px"><div class="row"><h2 class="grow">Borradores del cliente</h2><span class="muted">'+esc(rows.length)+' visibles</span></div><div class="stack">'+(rows.map(x=>'<article class="card"><div class="row"><div class="grow"><b>'+esc(x.message_type)+'</b><div class="muted">'+esc(communicationDate(x.created_at))+' · '+esc(x.source||'admin')+'</div></div>'+communicationStatusPill(x.status)+'</div><div style="white-space:pre-wrap;margin-top:10px">'+esc(x.body)+'</div>'+(x.blocked_reason?'<div class="muted" style="margin-top:8px;color:#ff93a1">Motivo de bloqueo: '+esc(x.blocked_reason)+'</div>':'')+'<div class="muted" style="margin-top:8px">ID de idempotencia: '+esc(x.idempotency_key)+'</div></article>').join('')||'<div class="card muted">No hay borradores para este filtro.</div>')+'</div></section>';
    $('#manageCommunicationPreference').onclick=()=>openCommunicationPreferenceModal(selected,pref);
    $('#newCommunicationDraft').onclick=()=>openCommunicationDraftModal(selected,null);
  }

  function openCommunicationPreferenceModal(client,pref){
    let suggested=pref?.whatsapp_phone_e164||(communicationPhoneValid(client.phone)?String(client.phone).trim():'');
    $('#modal').innerHTML='<div class="modal"><div class="card"><div class="row"><div class="grow"><div class="ey">CONSENTIMIENTO WHATSAPP</div><h2>'+esc(cname(client))+'</h2></div><button id="closeCommunicationPref" class="btn small">✕</button></div><div class="card" style="border-color:#62451f;margin-bottom:10px"><b>Registro de evidencia</b><div class="muted">Activa opt-in solo si el cliente confirmó expresamente que acepta comunicaciones por WhatsApp.</div></div><label>Teléfono E.164</label><input id="communicationPhone" class="input" placeholder="+56912345678" value="'+esc(suggested)+'"><label><input id="communicationOptIn" type="checkbox" '+(pref?.whatsapp_opt_in===true?'checked':'')+'> Cliente confirmó opt-in de WhatsApp</label><label style="display:block;margin-top:12px">Fuente de consentimiento</label><select id="communicationConsentSource" class="input"><option value="coach_recorded">Confirmación registrada por coach</option><option value="client_portal">Confirmación en portal del cliente</option><option value="imported">Consentimiento importado verificable</option></select><label>Nota/evidencia</label><textarea id="communicationConsentNote" class="input" rows="3" maxlength="500" placeholder="Ej.: Cliente confirma por escrito el 10/09/2026…">'+esc(pref?.consent_note||'')+'</textarea><div class="grid"><div><label>Quiet hours desde</label><input id="communicationQuietStart" class="input" type="time" value="'+esc(communicationTime(pref?.quiet_hours_start,'21:00'))+'"></div><div><label>Quiet hours hasta</label><input id="communicationQuietEnd" class="input" type="time" value="'+esc(communicationTime(pref?.quiet_hours_end,'08:00'))+'"></div></div><button id="saveCommunicationPref" class="btn primary" style="width:100%">GUARDAR ESTADO</button><div id="communicationPrefStatus" class="status muted"></div></div></div>';
    let close=()=>$('#modal').innerHTML='';$('#closeCommunicationPref').onclick=close;
    $('#saveCommunicationPref').onclick=async()=>{let b=$('#saveCommunicationPref'),out=$('#communicationPrefStatus');try{b.disabled=true;let optIn=$('#communicationOptIn').checked,phone=$('#communicationPhone').value.trim(),source=$('#communicationConsentSource').value,note=$('#communicationConsentNote').value.trim(),start=$('#communicationQuietStart').value||'21:00',end=$('#communicationQuietEnd').value||'08:00';if(phone&&!communicationPhoneValid(phone))throw Error('Usa formato E.164, por ejemplo +56912345678.');if(optIn&&!phone)throw Error('El opt-in requiere un teléfono E.164.');if(optIn&&!note)throw Error('Registra una nota/evidencia antes de activar opt-in.');if(!/^\d{2}:\d{2}$/.test(start)||!/^\d{2}:\d{2}$/.test(end))throw Error('Las horas no son válidas.');let result=await req('/rest/v1/rpc/set_whatsapp_communication_preference',{method:'POST',body:JSON.stringify({p_client_id:client.id,p_phone_e164:phone||null,p_opt_in:optIn,p_consent_source:source,p_consent_note:note||null,p_quiet_hours_start:start,p_quiet_hours_end:end})});if(!communicationRpcRow(result)?.client_id)throw Error('El backend no confirmó la preferencia.');close();cache={};toast('Preferencia de comunicación guardada.');await communications()}catch(error){out.textContent='No se pudo guardar: '+error.message}finally{b.disabled=false}};
  }

  function openCommunicationDraftModal(client,seed){
    let initial=seed||((communicationSeed&&communicationSeed.client_id===client.id)?communicationSeed:null),type=initial?.message_type||'general',draftBody=initial?.body||'',key=initial?.idempotency_key||communicationNewIdempotency(client.id,type),source=initial?.source||'admin',sourceRef=initial?.source_ref||null;
    $('#modal').innerHTML='<div class="modal"><div class="card"><div class="row"><div class="grow"><div class="ey">BORRADOR · NO ENVÍA</div><h2>'+esc(cname(client))+'</h2></div><button id="closeCommunicationDraft" class="btn small">✕</button></div><div class="card" style="border-color:#274a73;margin-bottom:10px"><b>Sin envío externo</b><div class="muted">Guardar solo prepara el contenido. El backend bloqueará automáticamente si no existe opt-in válido.</div></div><label>Tipo</label><select id="communicationMessageType" class="input"><option value="retention_followup" '+(type==='retention_followup'?'selected':'')+'>Seguimiento de retención</option><option value="workout_reminder" '+(type==='workout_reminder'?'selected':'')+'>Recordatorio de entrenamiento</option><option value="onboarding" '+(type==='onboarding'?'selected':'')+'>Onboarding</option><option value="payment_reminder" '+(type==='payment_reminder'?'selected':'')+'>Recordatorio de pago</option><option value="general" '+(type==='general'?'selected':'')+'>General</option></select><label>Mensaje</label><textarea id="communicationDraftBody" class="input" rows="10" maxlength="4000" placeholder="Escribe el borrador…">'+esc(draftBody)+'</textarea><div class="muted">ID idempotente: '+esc(key)+'</div><button id="saveCommunicationDraft" class="btn primary" style="width:100%;margin-top:10px">GUARDAR BORRADOR</button><div id="communicationDraftStatus" class="status muted"></div></div></div>';
    let close=()=>$('#modal').innerHTML='';$('#closeCommunicationDraft').onclick=()=>{communicationSeed=null;close()};
    $('#saveCommunicationDraft').onclick=async()=>{let b=$('#saveCommunicationDraft'),out=$('#communicationDraftStatus');try{b.disabled=true;let messageType=$('#communicationMessageType').value,message=$('#communicationDraftBody').value.trim();if(!message)throw Error('El mensaje no puede estar vacío.');if(message.length>4000)throw Error('El mensaje supera 4000 caracteres.');let effectiveKey=initial?.idempotency_key||communicationNewIdempotency(client.id,messageType);let result=await req('/rest/v1/rpc/prepare_communication_draft',{method:'POST',body:JSON.stringify({p_client_id:client.id,p_message_type:messageType,p_body:message,p_idempotency_key:effectiveKey,p_source:source,p_source_ref:sourceRef})}),row=communicationRpcRow(result);if(!row?.id)throw Error('El backend no confirmó el borrador.');communicationSeed=null;close();toast(row.status==='blocked'?'Borrador guardado y bloqueado por seguridad.':'Borrador listo · NO ENVIADO.');await communications()}catch(error){out.textContent='No se pudo guardar: '+error.message}finally{b.disabled=false}};
  }

  drawClientSelect();
  search.oninput=()=>{drawClientSelect();renderSelected()};
  clientSelect.onchange=()=>{selected=profiles.find(x=>x.id===clientSelect.value)||null;communicationClientId=clientSelect.value||null;communicationSeed=null;renderSelected()};
  statusFilter.onchange=renderSelected;
  renderSelected();
  if(communicationSeed&&communicationSeed.client_id===selected?.id){let seed=communicationSeed;setTimeout(()=>openCommunicationDraftModal(selected,seed),0)}
}
'''

replace_once('function subscriptionBlockHtml(rows,plans)', communications_js + '\nfunction subscriptionBlockHtml(rows,plans)', 'communications implementation')

required = [
    'data-v="communications"',
    "communications:'Comunicaciones'",
    "if(view==='communications')await communications();",
    'async function communications()',
    'set_whatsapp_communication_preference',
    'prepare_communication_draft',
    'PREPARAR WHATSAPP',
    'READY significa elegible',
    'no existe envío automático',
    'communicationSeed'
]
missing=[x for x in required if x not in text]
if missing:
    raise SystemExit('Missing communications markers: '+', '.join(missing))

path.write_text(text)
