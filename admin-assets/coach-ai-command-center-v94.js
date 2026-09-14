/* CV Coach V94 + V97 — Coach AI Unified Command Center + Decision Learning */
(() => {
  const VIEW='coach-ai';
  const STYLE_ID='cv-v94-command-style';
  const priorityMeta={CRITICAL:['CRÍTICO','v94-red'],HIGH:['ALTA','v94-warn'],MEDIUM:['MEDIA','v94-blue'],NORMAL:['NORMAL','v94-green']};
  const domainMeta={SAFETY:['SEGURIDAD','v94-red'],ONBOARDING:['ONBOARDING','v94-blue'],PROGRAMMING:['PROGRAMACIÓN','v94-warn'],ADHERENCE:['ADHERENCIA','v94-warn'],PROGRESSION:['PROGRESIÓN','v94-blue'],COMMERCIAL:['COMERCIAL','v94-gray'],MONITORING:['SEGUIMIENTO','v94-green']};

  function ensureStyle(){
    if(document.getElementById(STYLE_ID))return;
    const s=document.createElement('style');s.id=STYLE_ID;s.textContent=`
      .v94-head{display:flex;justify-content:space-between;gap:16px;align-items:flex-end;flex-wrap:wrap;margin-bottom:14px}.v94-title{font-size:clamp(32px,5vw,54px);letter-spacing:-.04em;line-height:.95;margin:5px 0 8px}.v94-sub{max-width:900px;color:var(--m);line-height:1.5}
      .v94-kpis{display:grid;grid-template-columns:repeat(7,minmax(105px,1fr));gap:9px;margin:15px 0}.v94-kpi{background:#0d1013;border:1px solid var(--b);border-radius:12px;padding:12px}.v94-kpi b{display:block;font-size:26px}.v94-kpi span{font-size:9px;color:var(--m);text-transform:uppercase;letter-spacing:.07em}
      .v94-toolbar{display:grid;grid-template-columns:minmax(220px,1fr) 170px 190px;gap:8px;margin:13px 0}.v94-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:11px}.v94-card{background:linear-gradient(180deg,#15191d,#0e1114);border:1px solid var(--b);border-radius:15px;padding:15px}.v94-card[data-priority="CRITICAL"]{border-color:#7a2631}.v94-card[data-priority="HIGH"]{border-color:#6c4a20}
      .v94-pills{display:flex;gap:6px;flex-wrap:wrap;margin:9px 0}.v94-pill{display:inline-flex;border:1px solid currentColor;border-radius:999px;padding:5px 8px;font-size:9px;font-weight:900;letter-spacing:.06em}.v94-red{color:#ff94a2;background:#2a0e13}.v94-warn{color:#ffc480;background:#2a2010}.v94-blue{color:#9cc4ff;background:#102238}.v94-green{color:#8be7ae;background:#0d261a}.v94-gray{color:#adb4bc;background:#181b20}
      .v94-score{font-size:28px;font-weight:950;line-height:1}.v94-score small{display:block;font-size:8px;color:var(--m);letter-spacing:.08em;margin-top:4px}.v94-action{background:#0b0e11;border:1px solid var(--b);border-radius:11px;padding:11px;margin-top:10px}.v94-action span{display:block;color:var(--m);font-size:9px;text-transform:uppercase;letter-spacing:.07em}.v94-action b{display:block;margin-top:4px;line-height:1.4}
      .v94-learning{background:#10151a;border:1px solid #29333c;border-radius:10px;padding:10px;margin-top:9px}.v94-learning span{display:block;color:#9cc4ff;font-size:8px;text-transform:uppercase;letter-spacing:.08em}.v94-learning b{display:block;margin-top:4px;font-size:11px;line-height:1.45}.v94-learning em{font-style:normal;color:var(--m);font-size:10px}
      .v94-reasons{display:grid;gap:5px;margin:10px 0}.v94-reason{font-size:11px;color:#c7cbd0;background:#101317;border-radius:8px;padding:7px 9px;border-left:2px solid #434b55}.v94-metrics{display:grid;grid-template-columns:repeat(4,1fr);gap:6px;margin-top:10px}.v94-metric{background:#0b0e11;border:1px solid var(--b);border-radius:9px;padding:8px}.v94-metric span{display:block;font-size:8px;color:var(--m);text-transform:uppercase}.v94-metric b{font-size:13px}.v94-actions{display:flex;gap:7px;flex-wrap:wrap;margin-top:11px}.v94-actions .btn{min-width:120px}.v94-pilot{border-style:dashed}.v94-empty{text-align:center;color:var(--m);padding:28px}
      @media(max-width:1280px){.v94-kpis{grid-template-columns:repeat(4,1fr)}}@media(max-width:1150px){.v94-grid{grid-template-columns:1fr}}@media(max-width:720px){.v94-kpis{grid-template-columns:repeat(2,1fr)}.v94-toolbar{grid-template-columns:1fr}.v94-metrics{grid-template-columns:repeat(2,1fr)}.v94-actions .btn{flex:1}}
    `;document.head.appendChild(s);
  }

  const clean=v=>v==null?'':String(v).trim();
  const arr=v=>Array.isArray(v)?v:[];
  const pm=p=>priorityMeta[p]||priorityMeta.NORMAL;
  const dm=d=>domainMeta[d]||domainMeta.MONITORING;
  const pill=(label,cls)=>`<span class="v94-pill ${cls}">${esc(label)}</span>`;
  async function command(){return req('/rest/v1/rpc/get_coach_ai_command_center_v94',{method:'POST',body:JSON.stringify({p_actor_id:me.id})});}

  function metric(label,value){return `<div class="v94-metric"><span>${esc(label)}</span><b>${esc(value??'—')}</b></div>`;}
  function pct(v){return v==null?'—':`${Math.round(Number(v)*100)}%`;}
  function learningStrip(x){
    const d=x.decision_learning||{};
    if(!d.eligible)return '';
    const adj=Number(d.score_adjustment||0),sign=adj>0?'+':'';
    return `<div class="v94-learning"><span>V97 · APRENDIZAJE HISTÓRICO</span><b>${esc(sign+adj)} puntos · confianza ${esc(pct(d.recommendation_confidence))} · muestra n=${esc(d.sample_size??0)}</b><em>${esc(clean(d.association_pattern||'').replaceAll('_',' '))} · asociación observada, no causalidad demostrada</em></div>`;
  }
  function actionButton(x){
    const code=clean(x.recommended_action_code);
    if(['review_onboarding','review_coach_assignment','review_account_status','review_client_profile'].includes(code))return `<button class="btn primary small v94Lifecycle" data-id="${esc(x.client_id)}">CLIENTES & ONBOARDING</button>`;
    if(['create_initial_program','finish_program_draft'].includes(code))return `<button class="btn primary small v94Program" data-id="${esc(x.client_id)}" data-program="${esc(x.lifecycle?.draft_program_id||x.lifecycle?.active_program_id||'')}">PROGRAMACIÓN</button>`;
    if(['review_deload','review_recovery','review_stagnation','review_training_signals'].includes(code))return `<button class="btn primary small v94Trends" data-id="${esc(x.client_id)}">REVISAR ENTRENAMIENTO</button>`;
    if(code==='review_progressions')return `<button class="btn primary small v94Progression" data-id="${esc(x.client_id)}">PROGRESIONES</button>`;
    return '';
  }

  function card(x){
    const [plabel,pcls]=pm(clean(x.priority));const [dlabel,dcls]=dm(clean(x.primary_domain));const t=x.training||{},l=x.lifecycle||{},dl=x.decision_learning||{};
    const reasons=arr(x.reasons).slice(0,5);
    const learningPill=dl.eligible?pill(`V97 ${Number(dl.score_adjustment||0)>0?'+':''}${Number(dl.score_adjustment||0)}`,Number(dl.score_adjustment||0)>=0?'v94-green':'v94-warn'):pill('V97 RECOLECTANDO','v94-gray');
    return `<article class="v94-card" data-priority="${esc(x.priority||'NORMAL')}" data-client="${esc(x.client_id||'')}">
      <div class="row"><div class="grow"><div class="ey">V94 + V97 · COACH AI</div><h2 style="margin:4px 0 2px">${esc(x.client_name||'Cliente')}</h2><div class="muted">${esc(x.primary_goal||'Objetivo no definido')}</div></div><div class="v94-score">${esc(x.command_score??0)}<small>SCORE CALIBRADO</small></div></div>
      <div class="v94-pills">${pill(plabel,pcls)}${pill(dlabel,dcls)}${pill('RIESGO '+clean(t.risk_level||'GREEN'),clean(t.risk_level)==='RED'?'v94-red':clean(t.risk_level)==='YELLOW'?'v94-warn':'v94-green')}${learningPill}${l.stage&&l.stage!=='operational'?pill(clean(l.stage).replaceAll('_',' ').toUpperCase(),'v94-gray'):''}</div>
      <div class="v94-action"><span>Acción recomendada</span><b>${esc(x.recommended_action||'Mantener seguimiento normal.')}</b></div>
      ${learningStrip(x)}
      <div class="v94-reasons">${reasons.map(r=>`<div class="v94-reason">${esc(r)}</div>`).join('')||'<div class="v94-reason">Sin señales adicionales.</div>'}</div>
      <div class="v94-metrics">${metric('Días sin sesión',t.days_since_workout==null?'Sin registro':t.days_since_workout)}${metric('Alertas',t.open_alerts??0)}${metric('Progresiones',t.pending_progressions??0)}${metric('Recuperación',t.recovery_flags??0)}</div>
      <div class="v94-actions"><button class="btn small v94Open" data-id="${esc(x.client_id||'')}">ABRIR FICHA</button>${actionButton(x)}</div>
    </article>`;
  }

  function pilotCard(x){const b=x.baseline_snapshot||{},[plabel,pcls]=pm(clean(x.priority));return `<article class="v94-card v94-pilot"><div class="row"><div class="grow"><div class="ey">PILOTO OBSERVADO</div><h2 style="margin:4px 0">${esc(x.subject_label||'Piloto')}</h2><div class="muted">${esc(clean(x.source_system).replaceAll('_',' ').toUpperCase())} · ${esc(clean(x.status).replaceAll('_',' ').toUpperCase())}</div></div>${pill(plabel,pcls)}</div><div class="v94-action"><span>Siguiente evidencia</span><b>${esc(x.next_action||'Continuar observación controlada.')}</b></div><div class="v94-metrics">${metric('Sesiones base',b.sessions_completed??0)}${metric('Ejercicios evidencia',b.evidence_exercises??0)}${metric('Auto publicar','OFF')}${metric('Identidad sintética','NO')}</div></article>`;}

  function bind(items){
    const map=new Map(items.map(x=>[x.client_id,x]));
    $$('.v94Open').forEach(b=>b.onclick=()=>clientDetail(b.dataset.id));
    $$('.v94Lifecycle').forEach(b=>b.onclick=()=>setView('lifecycle'));
    $$('.v94Program').forEach(b=>b.onclick=()=>{const x=map.get(b.dataset.id),pid=b.dataset.program;if(pid&&typeof programEditor==='function')programEditor(pid);else if(typeof newProgram==='function'){newProgram();setTimeout(()=>{const s=$('#programClient');if(s){s.value=x?.client_id||b.dataset.id;s.dispatchEvent(new Event('change',{bubbles:true}));}},0);}else setView('programs');});
    $$('.v94Trends').forEach(b=>b.onclick=()=>{if(typeof window.openTrainingTrendsV85==='function')window.openTrainingTrendsV85(b.dataset.id);else clientDetail(b.dataset.id);});
    $$('.v94Progression').forEach(b=>b.onclick=()=>{try{setView('progression')}catch{clientDetail(b.dataset.id)}});
  }

  async function renderCommand(){
    ensureStyle();const root=$('#content');if(!root)return;root.innerHTML='<div class="card muted">Analizando prioridades del coach…</div>';
    try{
      const d=await command(),items=arr(d?.items),pilots=arr(d?.pilots),s=d?.summary||{};
      root.innerHTML=`<div class="v94-head"><div><div class="ey">V97 · DECISION LEARNING FEEDBACK</div><h1 class="v94-title">COACH AI</h1><p class="v94-sub">Prioriza qué cliente necesita atención y recomienda la siguiente acción. V97 usa outcomes reconciliados de V96 para calibrar moderadamente score, prioridad y confianza solo cuando existe muestra suficiente; nunca cambia la acción determinística ni sustituye tu aprobación.</p></div><button id="v94Refresh" class="btn">↻ ACTUALIZAR</button></div>
        <div class="v94-kpis"><div class="v94-kpi"><span>Clientes</span><b>${esc(s.total_clients??0)}</b></div><div class="v94-kpi"><span>Requieren atención</span><b>${esc(s.requires_attention??0)}</b></div><div class="v94-kpi"><span>Críticos</span><b>${esc(s.critical??0)}</b></div><div class="v94-kpi"><span>Alta prioridad</span><b>${esc(s.high??0)}</b></div><div class="v94-kpi"><span>Programación</span><b>${esc(s.programming??0)}</b></div><div class="v94-kpi"><span>Aprendizaje aplicado</span><b>${esc(s.learning_applied??0)}</b></div><div class="v94-kpi"><span>Pilotos</span><b>${esc(s.active_pilots??0)}</b></div></div>
        <div class="v94-toolbar"><input id="v94Search" class="input" placeholder="Buscar cliente…" style="margin:0"><select id="v94Priority" class="input" style="margin:0"><option value="">Todas las prioridades</option><option>CRITICAL</option><option>HIGH</option><option>MEDIUM</option><option>NORMAL</option></select><select id="v94Domain" class="input" style="margin:0"><option value="">Todos los dominios</option>${Object.keys(domainMeta).map(k=>`<option value="${k}">${esc(domainMeta[k][0])}</option>`).join('')}</select></div>
        <section><div class="row"><h2 class="grow">Cola priorizada</h2><span class="muted">score determinístico + V97 sample-gated</span></div><div id="v94Grid" class="v94-grid"></div></section>
        <section style="margin-top:20px"><div class="row"><h2 class="grow">Pilotos observados</h2><span class="muted">sin identidad sintética · sin autoacción</span></div><div class="v94-grid">${pilots.map(pilotCard).join('')||'<div class="v94-card v94-empty">Sin pilotos activos.</div>'}</div></section>
        <div class="card" style="margin-top:20px"><div class="ey">GUARDRAILS V97</div><div class="muted" style="margin-top:7px">Muestra mínima n=3 · ajuste máximo ±12 · correlación ≠ causalidad · la acción recomendada no cambia por aprendizaje · seguridad nunca puede ser rebajada · auto-publicación OFF · auto-edición OFF · revisión del coach obligatoria.</div></div>`;
      const draw=()=>{const q=clean($('#v94Search')?.value).toLowerCase(),p=$('#v94Priority')?.value||'',dom=$('#v94Domain')?.value||'';const visible=items.filter(x=>(!p||x.priority===p)&&(!dom||x.primary_domain===dom)&&(!q||(`${x.client_name||''} ${x.email||''} ${x.primary_goal||''}`).toLowerCase().includes(q)));$('#v94Grid').innerHTML=visible.length?visible.map(card).join(''):'<div class="v94-card v94-empty">No hay clientes para este filtro.</div>';bind(visible);};
      $('#v94Search').oninput=draw;$('#v94Priority').onchange=draw;$('#v94Domain').onchange=draw;$('#v94Refresh').onclick=()=>{cache={};renderCommand();};draw();
    }catch(e){root.innerHTML=`<div class="card" style="border-color:#64202b"><b>No se pudo cargar Coach AI V97</b><div class="muted">${esc(String(e?.message||e))}</div></div>`;}
  }

  function installNavigation(){const nav=document.querySelector('.nav');if(!nav||nav.querySelector('[data-v="'+VIEW+'"]'))return;const b=document.createElement('button');b.dataset.v=VIEW;b.textContent='⚡ Coach AI';const lifecycle=nav.querySelector('[data-v="lifecycle"]');lifecycle?lifecycle.after(b):nav.prepend(b);b.onclick=()=>setView(VIEW);}

  if(typeof render!=='function'||typeof setView!=='function'||typeof req!=='function'){console.error('CV Coach V97: admin host contract unavailable');return;}
  const baseRender=render,baseSetView=setView;
  render=async function renderV94Aware(){if(view===VIEW)return renderCommand();return baseRender();};
  setView=function setViewV94Aware(next){if(next!==VIEW)return baseSetView(next);clientDetailToken++;view=VIEW;$$('.nav button').forEach(b=>b.classList.toggle('on',b.dataset.v===VIEW));$('#topTitle').textContent='Coach AI';return render();};
  installNavigation();
  window.coachAICommandCenterV94={render:renderCommand,version:'V97'};
  console.log('CV_ADMIN_COACH_AI_COMMAND_CENTER_V94_READY');
  console.log('CV_ADMIN_DECISION_LEARNING_V97_READY');
})();