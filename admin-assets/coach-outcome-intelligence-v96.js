/* CV Coach V96 — Action Reconciliation & Outcome Intelligence */
(() => {
  const VIEW='outcome-intelligence';
  const STYLE_ID='cv-v96-outcome-style';
  let state={data:null,status:'',query:'',reconciling:false};

  const clean=v=>v==null?'':String(v).trim();
  const arr=v=>Array.isArray(v)?v:[];
  const num=v=>Number.isFinite(Number(v))?Number(v):0;
  const statusLabel={WAITING_EVIDENCE:'ESPERANDO EVIDENCIA',RESOLVED:'RESUELTA',IMPROVED:'MEJORÓ',MIXED:'MIXTA',NO_CHANGE:'SIN CAMBIO',WORSENED:'EMPEORÓ'};
  const statusClass={WAITING_EVIDENCE:'v96-gray',RESOLVED:'v96-green',IMPROVED:'v96-green',MIXED:'v96-warn',NO_CHANGE:'v96-blue',WORSENED:'v96-red'};
  const patternLabel={INSUFFICIENT_SAMPLE:'MUESTRA INSUFICIENTE',FAVORABLE_ASSOCIATION:'ASOCIACIÓN FAVORABLE',VARIABLE_ASSOCIATION:'RESULTADO VARIABLE',WEAK_ASSOCIATION:'ASOCIACIÓN DÉBIL'};

  function ensureStyle(){
    if(document.getElementById(STYLE_ID))return;
    const s=document.createElement('style');s.id=STYLE_ID;s.textContent=`
      .v96-head{display:flex;justify-content:space-between;align-items:flex-end;gap:14px;flex-wrap:wrap;margin-bottom:14px}.v96-title{font-size:clamp(32px,5vw,54px);line-height:.95;letter-spacing:-.04em;margin:5px 0 8px}.v96-sub{color:var(--m);max-width:940px;line-height:1.5}
      .v96-kpis{display:grid;grid-template-columns:repeat(7,minmax(100px,1fr));gap:9px;margin:15px 0}.v96-kpi{background:#0d1013;border:1px solid var(--b);border-radius:12px;padding:12px}.v96-kpi b{display:block;font-size:25px}.v96-kpi span{font-size:9px;color:var(--m);text-transform:uppercase;letter-spacing:.07em}
      .v96-toolbar{display:grid;grid-template-columns:minmax(220px,1fr) 210px auto;gap:8px;margin:12px 0 14px}.v96-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:11px}.v96-card{background:linear-gradient(180deg,#15191d,#0e1114);border:1px solid var(--b);border-radius:15px;padding:15px}.v96-pills{display:flex;gap:6px;flex-wrap:wrap;margin:9px 0}.v96-pill{display:inline-flex;border:1px solid currentColor;border-radius:999px;padding:5px 8px;font-size:9px;font-weight:900;letter-spacing:.06em}.v96-green{color:#8be7ae;background:#0d261a}.v96-warn{color:#ffc480;background:#2a2010}.v96-red{color:#ff94a2;background:#2a0e13}.v96-blue{color:#9cc4ff;background:#102238}.v96-gray{color:#adb4bc;background:#181b20}
      .v96-score{font-size:30px;font-weight:900;line-height:1}.v96-action{background:#0b0e11;border:1px solid var(--b);border-radius:11px;padding:11px;margin:10px 0}.v96-action span{display:block;font-size:9px;color:var(--m);text-transform:uppercase;letter-spacing:.07em}.v96-action b{display:block;margin-top:4px;line-height:1.4}.v96-explain{font-size:12px;line-height:1.5;color:#d2d6db;margin:10px 0}.v96-evidence{display:grid;grid-template-columns:repeat(3,1fr);gap:7px;margin-top:10px}.v96-ev{background:#101317;border:1px solid #252b31;border-radius:9px;padding:9px}.v96-ev span{display:block;color:var(--m);font-size:8px;text-transform:uppercase;letter-spacing:.06em}.v96-ev b{display:block;margin-top:3px;font-size:12px}.v96-actions{display:flex;gap:7px;flex-wrap:wrap;margin-top:11px}
      .v96-learning{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px}.v96-learn{background:#0d1013;border:1px solid var(--b);border-radius:12px;padding:13px}.v96-learn h3{margin:4px 0 9px;font-size:14px}.v96-bar{height:7px;border-radius:999px;background:#1a1f25;overflow:hidden;margin:8px 0}.v96-bar>i{display:block;height:100%;background:currentColor}.v96-empty{text-align:center;padding:28px;color:var(--m)}
      @media(max-width:1180px){.v96-kpis{grid-template-columns:repeat(4,1fr)}.v96-learning{grid-template-columns:repeat(2,1fr)}}@media(max-width:850px){.v96-grid{grid-template-columns:1fr}.v96-kpis{grid-template-columns:repeat(2,1fr)}.v96-toolbar{grid-template-columns:1fr}.v96-learning{grid-template-columns:1fr}.v96-evidence{grid-template-columns:1fr 1fr}}
    `;document.head.appendChild(s);
  }

  async function api(name,body){return req('/rest/v1/rpc/'+name,{method:'POST',body:JSON.stringify(body)});}
  async function loadCenter(){return api('get_coach_outcome_intelligence_v96',{p_actor_id:me.id});}
  async function reconcileDue(){return api('reconcile_due_coach_action_outcomes_v96',{p_actor_id:me.id,p_limit:50});}
  async function reconcileOne(id){return api('reconcile_coach_action_outcome_v96',{p_actor_id:me.id,p_workspace_id:id});}
  function pill(label,cls='v96-gray'){return `<span class="v96-pill ${cls}">${esc(label)}</span>`;}
  function fmtDate(v){if(!v)return '—';try{return new Date(v).toLocaleString('es-CL');}catch{return clean(v)||'—';}}
  function pct(v){return `${Math.round(num(v)*100)}%`;}
  function scoreText(v){return v==null?'—':`${num(v)>0?'+':''}${num(v)}`;}
  function actionName(v){return clean(v||'acción').replaceAll('_',' ').toUpperCase();}

  async function refresh({auto=true}={}){
    if(state.reconciling)return;
    state.reconciling=true;
    try{
      if(auto)await reconcileDue();
      state.data=await loadCenter();
      renderOutcome();
    }catch(e){
      const root=$('#content');if(root)root.innerHTML=`<div class="card" style="border-color:#64202b"><b>No se pudo cargar V96</b><div class="muted">${esc(String(e?.message||e))}</div></div>`;
    }finally{state.reconciling=false;}
  }

  function outcomeCard(x){
    const st=clean(x.outcome_status||'WAITING_EVIDENCE');
    const ev=x.evidence||{},risk=ev.risk||{},burden=ev.signal_burden||{},prog=ev.pending_progressions||{},life=ev.lifecycle||{};
    const post=num(ev.post_sessions),required=num(ev.minimum_post_sessions);
    const evidenceLabel=x.evidence_status==='SUFFICIENT'?'EVIDENCIA SUFICIENTE':'EVIDENCIA INSUFICIENTE';
    const evidenceClass=x.evidence_status==='SUFFICIENT'?'v96-green':'v96-gray';
    return `<article class="v96-card" data-id="${esc(x.workspace_id)}">
      <div class="row"><div class="grow"><div class="ey">V96 · OUTCOME</div><h2 style="margin:4px 0 2px">${esc(x.client_name||'Cliente')}</h2><div class="muted">${esc(actionName(x.action_code))} · ${esc(fmtDate(x.completed_at))}</div></div><div style="text-align:right"><div class="v96-score">${esc(scoreText(x.effectiveness_score))}</div><div class="muted" style="font-size:9px">EFECTIVIDAD</div></div></div>
      <div class="v96-pills">${pill(statusLabel[st]||st,statusClass[st]||'v96-gray')}${pill(evidenceLabel,evidenceClass)}${pill(`CONFIANZA ${pct(x.confidence)}`,'v96-blue')}${x.completion_verification==='system_reconciled'?pill('SYSTEM RECONCILED','v96-green'):pill('COACH REPORTED','v96-gray')}</div>
      <div class="v96-action"><span>Acción ejecutada</span><b>${esc(x.action||'—')}</b></div>
      <div class="v96-explain">${esc(x.explanation||'Aún no existe una evaluación persistida para esta acción.')}</div>
      <div class="v96-evidence">
        <div class="v96-ev"><span>Sesiones posteriores</span><b>${esc(post)}${required?` / mín. ${esc(required)}`:''}</b></div>
        <div class="v96-ev"><span>Riesgo</span><b>${esc(risk.before||'—')} → ${esc(risk.after||'—')}</b></div>
        <div class="v96-ev"><span>Carga de señales</span><b>${esc(burden.before??'—')} → ${esc(burden.after??'—')}</b></div>
        <div class="v96-ev"><span>Progresiones</span><b>${esc(prog.before??'—')} → ${esc(prog.after??'—')}</b></div>
        <div class="v96-ev"><span>Ciclo de vida</span><b>${esc((life.before||'—').replaceAll('_',' '))} → ${esc((life.after||'—').replaceAll('_',' '))}</b></div>
        <div class="v96-ev"><span>Próxima revisión</span><b>${esc(x.next_check_after?fmtDate(x.next_check_after):'cerrada')}</b></div>
      </div>
      <div class="v96-actions"><button class="btn primary small v96Action">ABRIR ACCIÓN</button><button class="btn small v96Reconcile">RECONCILIAR</button><button class="btn small v96Client">FICHA CLIENTE</button></div>
    </article>`;
  }

  function learningCard(x){
    const rate=num(x.positive_rate),ready=!!x.learning_ready,pattern=patternLabel[x.association_pattern]||x.association_pattern||'—';
    return `<div class="v96-learn"><div class="ey">${ready?'APRENDIZAJE ACTIVO':'RECOLECTANDO MUESTRA'}</div><h3>${esc(actionName(x.action_code))}</h3><div class="row"><b class="grow">${esc(pct(rate))} positivos</b><span class="muted">n=${esc(x.sample_size)}</span></div><div class="v96-bar" style="color:${rate>=.75?'#8be7ae':rate>=.4?'#ffc480':'#9cc4ff'}"><i style="width:${Math.max(0,Math.min(100,Math.round(rate*100)))}%"></i></div><div class="muted">${esc(pattern)} · score medio ${esc(x.average_score??'—')} · confianza ${esc(pct(x.average_confidence))}</div></div>`;
  }

  function filteredItems(){
    const d=state.data||{},q=clean(state.query).toLowerCase(),st=clean(state.status);
    return arr(d.items).filter(x=>(!st||x.outcome_status===st)&&(!q||(`${x.client_name||''} ${x.action||''} ${x.action_code||''}`).toLowerCase().includes(q)));
  }

  function drawCards(){
    const items=filteredItems(),grid=$('#v96Grid');if(!grid)return;
    grid.innerHTML=items.length?items.map(outcomeCard).join(''):'<div class="v96-card v96-empty">No hay resultados para este filtro.</div>';
    const map=new Map(items.map(x=>[x.workspace_id,x]));
    $$('.v96-card[data-id]').forEach(el=>{
      const x=map.get(el.dataset.id);if(!x)return;
      el.querySelector('.v96Action')?.addEventListener('click',()=>{if(window.coachActionWorkspaceV95?.open)return window.coachActionWorkspaceV95.open(x.client_id);clientDetail(x.client_id);});
      el.querySelector('.v96Client')?.addEventListener('click',()=>clientDetail(x.client_id));
      el.querySelector('.v96Reconcile')?.addEventListener('click',async()=>{try{await reconcileOne(x.workspace_id);state.data=await loadCenter();renderOutcome();}catch(e){alert('No se pudo reconciliar: '+String(e?.message||e));}});
    });
  }

  function renderOutcome(){
    ensureStyle();const root=$('#content');if(!root)return;
    const d=state.data||{},s=d.summary||{},learning=arr(d.learning);
    root.innerHTML=`<div class="v96-head"><div><div class="ey">V96 · ACTION RECONCILIATION</div><h1 class="v96-title">OUTCOME INTELLIGENCE</h1><p class="v96-sub">Mide qué pasó después de cada decisión del coach. El sistema compara las señales que originaron la acción con evidencia posterior real y aprende patrones solo cuando existe muestra suficiente. Asociación observada ≠ causalidad demostrada.</p></div><button id="v96Refresh" class="btn primary">↻ RECONCILIAR AHORA</button></div>
      <div class="v96-kpis"><div class="v96-kpi"><span>Acciones completadas</span><b>${esc(s.completed_actions??0)}</b></div><div class="v96-kpi"><span>Evaluadas</span><b>${esc(s.assessed??0)}</b></div><div class="v96-kpi"><span>Esperando</span><b>${esc(s.waiting??0)}</b></div><div class="v96-kpi"><span>Positivas</span><b>${esc(s.positive??0)}</b></div><div class="v96-kpi"><span>Mixtas</span><b>${esc(s.mixed??0)}</b></div><div class="v96-kpi"><span>Sin cambio</span><b>${esc(s.no_change??0)}</b></div><div class="v96-kpi"><span>Empeoraron</span><b>${esc(s.worsened??0)}</b></div></div>
      <div class="v96-toolbar"><input id="v96Search" class="input" placeholder="Buscar cliente o acción…" style="margin:0"><select id="v96Status" class="input" style="margin:0"><option value="">Todos los resultados</option><option value="WAITING_EVIDENCE">Esperando evidencia</option><option value="RESOLVED">Resuelta</option><option value="IMPROVED">Mejoró</option><option value="MIXED">Mixta</option><option value="NO_CHANGE">Sin cambio</option><option value="WORSENED">Empeoró</option></select><div class="v96-pill v96-gray" style="justify-content:center">DUE ${esc(s.due??0)}</div></div>
      <section><div class="row"><h2 class="grow">Resultados por acción</h2><span class="muted">mínimo entrenamiento: 2 sesiones · seguridad: 1</span></div><div id="v96Grid" class="v96-grid"></div></section>
      <section style="margin-top:24px"><div class="row"><h2 class="grow">Aprendizaje por tipo de decisión</h2><span class="muted">se activa con n ≥ 3</span></div><div class="v96-learning">${learning.length?learning.map(learningCard).join(''):'<div class="v96-learn v96-empty">Aún no hay una muestra suficiente de acciones reconciliadas.</div>'}</div></section>
      <div class="card" style="margin-top:20px"><div class="ey">GUARDRAILS V96</div><div class="muted" style="margin-top:7px">Correlación ≠ causalidad · una sesión no basta para concluir eficacia de entrenamiento · auto-publicación OFF · auto-edición OFF · auto-mensajería OFF · auto-cobros OFF · V96 solo modifica metadatos privados de auditoría de resultados.</div></div>`;
    $('#v96Search').value=state.query;$('#v96Status').value=state.status;
    $('#v96Search').oninput=e=>{state.query=e.target.value;drawCards();};$('#v96Status').onchange=e=>{state.status=e.target.value;drawCards();};
    $('#v96Refresh').onclick=async()=>{state.data=null;await refresh({auto:true});};drawCards();
  }

  async function renderView(){
    ensureStyle();const root=$('#content');if(!root)return;root.innerHTML='<div class="card muted">Reconciliando resultados V96…</div>';
    if(state.data)return renderOutcome();
    await refresh({auto:true});
  }

  function installNavigation(){const nav=document.querySelector('.nav');if(!nav||nav.querySelector('[data-v="'+VIEW+'"]'))return;const b=document.createElement('button');b.dataset.v=VIEW;b.textContent='↗ Resultados';const a=nav.querySelector('[data-v="action-workspace"]');a?a.after(b):nav.prepend(b);b.onclick=()=>setView(VIEW);}

  if(typeof render!=='function'||typeof setView!=='function'||typeof req!=='function'){console.error('CV Coach V96: admin host contract unavailable');return;}
  const baseRender=render,baseSetView=setView;
  render=async function renderV96Aware(){if(view===VIEW)return renderView();return baseRender();};
  setView=function setViewV96Aware(next){if(next!==VIEW)return baseSetView(next);clientDetailToken++;view=VIEW;$$('.nav button').forEach(b=>b.classList.toggle('on',b.dataset.v===VIEW));$('#topTitle').textContent='Outcome Intelligence';return render();};
  installNavigation();
  window.coachOutcomeIntelligenceV96={version:'V96',open:()=>{state.data=null;setView(VIEW);},refresh:()=>refresh({auto:true})};
  console.log('CV_ADMIN_ACTION_OUTCOME_INTELLIGENCE_V96_READY');
})();
