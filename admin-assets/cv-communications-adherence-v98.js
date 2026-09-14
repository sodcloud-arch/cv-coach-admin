/* CV Coach V98 — Communications & Adherence Intelligence */
(() => {
  const VIEW='adherence-v98';
  const STYLE='cv-v98-adherence-style';
  const strategyLabel={supportive_nudge:'NUDGE SUAVE',barrier_checkin:'CHECK-IN DE BARRERAS',reactivation_reset:'REINICIO CONTROLADO'};
  const readinessLabel={DRAFT_READY:'BORRADOR LISTO',CONSENT_REQUIRED:'FALTA CONSENTIMIENTO',PHONE_REQUIRED:'FALTA TELÉFONO',NOT_RECOMMENDED:'MONITOREO'};

  function ensureStyle(){
    if(document.getElementById(STYLE))return;
    const s=document.createElement('style');s.id=STYLE;s.textContent=`
      .v98-head{display:flex;gap:16px;justify-content:space-between;align-items:flex-end;flex-wrap:wrap}.v98-title{font-size:clamp(30px,5vw,52px);line-height:.95;letter-spacing:-.04em;margin:4px 0 8px}.v98-sub{color:var(--m);max-width:900px;line-height:1.5}.v98-kpis{display:grid;grid-template-columns:repeat(6,1fr);gap:9px;margin:15px 0}.v98-kpi{background:#0d1013;border:1px solid var(--b);border-radius:12px;padding:12px}.v98-kpi b{display:block;font-size:25px}.v98-kpi span{font-size:8px;color:var(--m);text-transform:uppercase;letter-spacing:.08em}.v98-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:11px}.v98-card{background:linear-gradient(180deg,#15191d,#0e1114);border:1px solid var(--b);border-radius:15px;padding:15px}.v98-card[data-ready="DRAFT_READY"]{border-color:#315b46}.v98-card[data-score="high"]{border-color:#6b4a20}.v98-pills{display:flex;gap:6px;flex-wrap:wrap;margin:9px 0}.v98-pill{border:1px solid currentColor;border-radius:999px;padding:5px 8px;font-size:9px;font-weight:900;letter-spacing:.05em}.v98-green{color:#8be7ae;background:#0d261a}.v98-warn{color:#ffc480;background:#2a2010}.v98-blue{color:#9cc4ff;background:#102238}.v98-gray{color:#adb4bc;background:#181b20}.v98-message{background:#0b0e11;border:1px solid var(--b);border-radius:11px;padding:11px;line-height:1.5;font-size:12px;white-space:pre-wrap}.v98-metrics{display:grid;grid-template-columns:repeat(4,1fr);gap:6px;margin:10px 0}.v98-metric{background:#0b0e11;border:1px solid var(--b);border-radius:9px;padding:8px}.v98-metric span{display:block;font-size:8px;color:var(--m);text-transform:uppercase}.v98-metric b{font-size:13px}.v98-actions{display:flex;gap:7px;flex-wrap:wrap}.v98-learning{margin-top:20px}.v98-table{overflow:auto;border:1px solid var(--b);border-radius:12px}.v98-table table{width:100%;border-collapse:collapse;min-width:650px}.v98-table th,.v98-table td{padding:10px;border-bottom:1px solid var(--b);font-size:11px;text-align:left}.v98-table th{font-size:9px;color:var(--m);text-transform:uppercase;background:#101214}.v98-empty{text-align:center;padding:30px;color:var(--m)}.v98-modal-message{width:100%;min-height:150px;resize:vertical}.v98-note{font-size:10px;color:var(--m);line-height:1.45}.v98-alert{border-left:3px solid #ff9f43;padding:9px 10px;background:#21190d;border-radius:8px;font-size:11px;margin:9px 0}
      @media(max-width:1100px){.v98-kpis{grid-template-columns:repeat(3,1fr)}.v98-grid{grid-template-columns:1fr}}@media(max-width:700px){.v98-kpis{grid-template-columns:repeat(2,1fr)}.v98-metrics{grid-template-columns:repeat(2,1fr)}.v98-actions .btn{flex:1}}
    `;document.head.appendChild(s);
  }

  const clean=v=>v==null?'':String(v).trim();
  const arr=v=>Array.isArray(v)?v:[];
  const rpc=(name,body)=>req('/rest/v1/rpc/'+name,{method:'POST',body:JSON.stringify(body)});
  const pill=(t,c)=>`<span class="v98-pill ${c}">${esc(t)}</span>`;
  const metric=(t,v)=>`<div class="v98-metric"><span>${esc(t)}</span><b>${esc(v??'—')}</b></div>`;
  const fmtDate=v=>{if(!v)return '—';try{return new Date(v).toLocaleString('es-CL',{dateStyle:'short',timeStyle:'short'})}catch{return v}};
  const pct=v=>v==null?'—':`${Math.round(Number(v)*100)}%`;

  async function center(refresh=true){
    if(refresh){try{await rpc('refresh_adherence_followup_outcomes_v98',{p_actor_id:me.id})}catch(e){console.warn('V98 outcome refresh:',e.message)}}
    return rpc('get_adherence_communication_center_v98',{p_actor_id:me.id});
  }

  function readinessPill(x){
    const r=clean(x.readiness);return pill(readinessLabel[r]||r,r==='DRAFT_READY'?'v98-green':r==='NOT_RECOMMENDED'?'v98-gray':'v98-warn');
  }

  function card(x){
    const score=Number(x.adherence_contact_score||0),high=score>=75?'high':'normal',last=x.last_followup||{},comm=x.communication||{};
    const status=last.outcome_status?pill(clean(last.outcome_status).replaceAll('_',' '),last.outcome_status==='RETURNED'?'v98-green':last.outcome_status==='NO_RETURN'?'v98-warn':'v98-blue'):'';
    return `<article class="v98-card" data-ready="${esc(x.readiness||'')}" data-score="${high}">
      <div class="row"><div class="grow"><div class="ey">V98 · ADHERENCIA</div><h2 style="margin:4px 0 2px">${esc(x.client_name||'Cliente')}</h2><div class="muted">${esc(x.primary_goal||'Objetivo no definido')}</div></div><div style="text-align:right"><b style="font-size:28px">${esc(score)}</b><div class="v98-note">CONTACT SCORE</div></div></div>
      <div class="v98-pills">${readinessPill(x)}${x.strategy_code?pill(strategyLabel[x.strategy_code]||x.strategy_code,'v98-blue'):''}${pill('RIESGO '+clean(x.risk_level||'GREEN'),clean(x.risk_level)==='RED'?'v98-warn':'v98-gray')}${status}</div>
      <div class="v98-metrics">${metric('Días sin sesión',x.days_since_workout==null?'—':x.days_since_workout)}${metric('Última sesión',x.last_workout_at?fmtDate(x.last_workout_at):'Sin registro')}${metric('WhatsApp',comm.whatsapp_opt_in?'OPT-IN':'SIN OPT-IN')}${metric('Autoenvío','OFF')}</div>
      ${x.followup_recommended&&x.proposed_message?`<div class="v98-message">${esc(x.proposed_message)}</div>`:`<div class="v98-message muted">Sin contacto recomendado en este momento.</div>`}
      ${last.contacted_at?`<div class="v98-note" style="margin-top:8px">Último contacto registrado: ${esc(fmtDate(last.contacted_at))} · outcome ${esc(last.outcome_status||'pendiente')}${last.days_to_return!=null?` · retorno ${esc(last.days_to_return)} días`:''}</div>`:''}
      <div class="v98-actions" style="margin-top:10px"><button class="btn small v98Open" data-id="${esc(x.client_id)}">DETALLE V98</button><button class="btn small v98Client" data-id="${esc(x.client_id)}">ABRIR FICHA</button></div>
    </article>`;
  }

  function learningTable(catalog){
    if(!catalog.length)return '<div class="v98-card v98-empty">Aún no hay outcomes reales suficientes. V98 empezará a comparar estrategias después de contactos confirmados.</div>';
    return `<div class="v98-table"><table><thead><tr><th>Estrategia</th><th>Muestra</th><th>Retorno</th><th>Tiempo medio</th><th>Efectividad</th><th>Aprendizaje</th></tr></thead><tbody>${catalog.map(x=>`<tr><td>${esc(strategyLabel[x.strategy_code]||x.strategy_code)}</td><td>${esc(x.sample_size)}</td><td>${esc(pct(x.return_rate))}</td><td>${x.avg_days_to_return==null?'—':esc(x.avg_days_to_return)+' d'}</td><td>${x.avg_effectiveness==null?'—':esc(x.avg_effectiveness)}</td><td>${x.learning_ready?pill('MUESTRA ÚTIL','v98-green'):pill('RECOLECTANDO','v98-gray')}</td></tr>`).join('')}</tbody></table></div>`;
  }

  async function detail(clientId){
    try{
      const d=await center(false),x=arr(d.items).find(v=>v.client_id===clientId);if(!x)throw Error('Cliente no disponible en V98.');
      const comm=x.communication||{},last=x.last_followup||{};
      $('#modal').innerHTML=`<div class="modal"><div class="card"><div class="row"><div class="grow"><div class="ey">V98 · SEGUIMIENTO</div><h2 style="margin:5px 0">${esc(x.client_name||'Cliente')}</h2></div><button id="v98Close" class="btn small">✕</button></div>
        <div class="v98-pills">${readinessPill(x)}${x.strategy_code?pill(strategyLabel[x.strategy_code]||x.strategy_code,'v98-blue'):''}</div>
        <div class="v98-metrics">${metric('Inactividad',x.days_since_workout==null?'—':x.days_since_workout+' días')}${metric('Consentimiento',comm.whatsapp_opt_in?'ACTIVO':'NO')}${metric('Teléfono',comm.phone_ready?'LISTO':'FALTA')}${metric('Proveedor',comm.provider_dispatch_enabled?'ACTIVO':'MANUAL')}</div>
        ${comm.provider_dispatch_enabled?'':'<div class="v98-alert">Peach/CV Coach aún no tiene dispatch habilitado. V98 prepara el mensaje pero NO lo envía automáticamente.</div>'}
        <label>Mensaje propuesto</label><textarea id="v98Body" class="input v98-modal-message" readonly>${esc(x.proposed_message||'Sin mensaje recomendado.')}</textarea>
        <div id="v98DraftState" class="v98-note">${last.draft_id?'Existe un seguimiento anterior. Puedes crear un nuevo borrador solo cuando el cooldown lo permita.':'Crear un borrador no cuenta como contacto.'}</div>
        <div class="v98-actions" style="margin-top:12px"><button id="v98Copy" class="btn">COPIAR MENSAJE</button>${x.readiness==='DRAFT_READY'?'<button id="v98Prepare" class="btn primary">PREPARAR BORRADOR</button>':''}</div>
        <div class="v98-note" style="margin-top:12px">Guardrails: revisión del coach obligatoria · autoenvío OFF · sesiones abandonadas no reinician el reloj de adherencia · retorno medido a 7 días como asociación, no causalidad.</div></div></div>`;
      $('#v98Close').onclick=()=>{$('#modal').innerHTML=''};
      $('#v98Copy').onclick=async()=>{try{await navigator.clipboard.writeText(x.proposed_message||'');toast('Mensaje copiado')}catch{toast('No se pudo copiar')}};
      const prep=$('#v98Prepare');if(prep)prep.onclick=async()=>{
        prep.disabled=true;
        try{
          const p=await rpc('prepare_adherence_followup_v98',{p_actor_id:me.id,p_client_id:clientId}),draft=p?.draft||{},pre=p?.preflight||{};
          $('#v98DraftState').innerHTML=`<b>Borrador ${esc(draft.status||'—')}</b> · autoenvío OFF${pre.eligible_for_provider_dispatch?'':' · proveedor automático no disponible'}<br><span class="muted">Después de enviarlo manualmente, registra el contacto para iniciar la medición.</span>`;
          const box=document.createElement('div');box.className='v98-actions';box.style.marginTop='10px';box.innerHTML='<button id="v98ConfirmSent" class="btn good">YA LO ENVIÉ · REGISTRAR CONTACTO</button>';
          $('#v98DraftState').after(box);
          $('#v98ConfirmSent').onclick=async()=>{
            if(!confirm('Confirma solo si el mensaje ya fue enviado realmente al cliente por WhatsApp.'))return;
            const b=$('#v98ConfirmSent');b.disabled=true;
            try{await rpc('mark_adherence_followup_contacted_v98',{p_actor_id:me.id,p_draft_id:draft.id,p_sent_at:new Date().toISOString()});toast('Contacto registrado · ventana de outcome iniciada');$('#modal').innerHTML='';await renderAdherence();}catch(e){toast(e.message);b.disabled=false;}
          };
          toast('Borrador preparado');
        }catch(e){toast(e.message);prep.disabled=false;}
      };
    }catch(e){toast(e.message)}
  }

  function bind(items){
    $$('.v98Open').forEach(b=>b.onclick=()=>detail(b.dataset.id));
    $$('.v98Client').forEach(b=>b.onclick=()=>clientDetail(b.dataset.id));
  }

  async function renderAdherence(){
    ensureStyle();const root=$('#content');if(!root)return;root.innerHTML='<div class="card muted">Analizando adherencia y comunicaciones…</div>';
    try{
      const d=await center(true),items=arr(d.items),s=d.summary||{},catalog=arr(d.strategy_catalog),provider=d.provider||{};
      const recommended=items.filter(x=>x.followup_recommended),monitoring=items.filter(x=>!x.followup_recommended);
      root.innerHTML=`<div class="v98-head"><div><div class="ey">V98 · COMMUNICATIONS & ADHERENCE INTELLIGENCE</div><h1 class="v98-title">ADHERENCIA</h1><p class="v98-sub">Detecta inactividad real usando sesiones completadas/parciales, propone el seguimiento correcto, prepara un borrador para tu aprobación y mide si el cliente vuelve a entrenar. Ningún mensaje se envía automáticamente.</p></div><button id="v98Refresh" class="btn">↻ ACTUALIZAR</button></div>
        <div class="v98-kpis"><div class="v98-kpi"><span>Seguimientos</span><b>${esc(s.followup_recommended??0)}</b></div><div class="v98-kpi"><span>Borrador listo</span><b>${esc(s.draft_ready??0)}</b></div><div class="v98-kpi"><span>Falta consentimiento</span><b>${esc(s.consent_required??0)}</b></div><div class="v98-kpi"><span>Outcomes pendientes</span><b>${esc(s.waiting_outcomes??0)}</b></div><div class="v98-kpi"><span>Outcomes resueltos</span><b>${esc(s.resolved_followups??0)}</b></div><div class="v98-kpi"><span>Autoenvío</span><b>OFF</b></div></div>
        <section><div class="row"><h2 class="grow">Acción recomendada</h2><span class="muted">${esc(provider.provider||'peach')} · ${esc(provider.status||'unassigned')}</span></div><div class="v98-grid">${recommended.length?recommended.map(card).join(''):'<div class="v98-card v98-empty">No hay clientes que requieran contacto de adherencia ahora.</div>'}</div></section>
        <section class="v98-learning"><div class="row"><h2 class="grow">Qué seguimiento funciona mejor</h2><span class="muted">sample gate n ≥ 3</span></div>${learningTable(catalog)}</section>
        <section style="margin-top:20px"><details><summary class="click"><b>Clientes en monitoreo (${monitoring.length})</b></summary><div class="v98-grid" style="margin-top:10px">${monitoring.map(card).join('')||'<div class="v98-card v98-empty">Sin clientes.</div>'}</div></details></section>
        <div class="card" style="margin-top:20px"><div class="ey">GUARDRAILS V98</div><div class="muted" style="margin-top:7px">Solo sesiones completed/partial cuentan para adherencia · abandoned no reinicia el reloj · safety RED suprime contacto · consentimiento y teléfono válidos obligatorios · quiet hours respetadas · borrador ≠ contacto · confirmación manual obligatoria · autoenvío OFF · ventana de outcome 7 días · asociación ≠ causalidad.</div></div>`;
      $('#v98Refresh').onclick=()=>renderAdherence();bind(items);
    }catch(e){root.innerHTML=`<div class="card" style="border-color:#64202b"><b>No se pudo cargar Adherencia V98</b><div class="muted">${esc(e.message||e)}</div></div>`;}
  }

  function installNavigation(){
    const nav=document.querySelector('.nav');if(!nav||nav.querySelector('[data-v="'+VIEW+'"]'))return;
    const b=document.createElement('button');b.dataset.v=VIEW;b.textContent='🎯 Adherencia V98';const communications=nav.querySelector('[data-v="communications"]');communications?communications.after(b):nav.appendChild(b);b.onclick=()=>setView(VIEW);
  }

  if(typeof render!=='function'||typeof setView!=='function'||typeof req!=='function'){console.error('CV Coach V98: admin host contract unavailable');return;}
  const baseRender=render,baseSetView=setView;
  render=async function renderV98Aware(){if(view===VIEW)return renderAdherence();return baseRender();};
  setView=function setViewV98Aware(next){if(next!==VIEW)return baseSetView(next);clientDetailToken++;view=VIEW;$$('.nav button').forEach(b=>b.classList.toggle('on',b.dataset.v===VIEW));$('#topTitle').textContent='Adherencia V98';return render();};
  installNavigation();
  window.cvCommunicationsAdherenceV98={render:renderAdherence,version:'V98'};
  console.log('CV_ADMIN_COMMUNICATIONS_ADHERENCE_V98_READY');
})();
