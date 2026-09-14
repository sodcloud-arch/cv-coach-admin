/* CV Coach V95 — Coach Action Workspace */
(() => {
  const VIEW='action-workspace';
  const STYLE_ID='cv-v95-action-style';
  let state={data:null,clientFilter:null};

  const clean=v=>v==null?'':String(v).trim();
  const arr=v=>Array.isArray(v)?v:[];
  const statusLabel={PENDING:'PENDIENTE',READY:'LISTA',EXECUTING:'EN EJECUCIÓN',COMPLETED:'COMPLETADA',REJECTED:'RECHAZADA'};
  const priorityClass={CRITICAL:'v95-red',HIGH:'v95-warn',MEDIUM:'v95-blue',NORMAL:'v95-green'};

  function ensureStyle(){
    if(document.getElementById(STYLE_ID))return;
    const s=document.createElement('style');s.id=STYLE_ID;s.textContent=`
      .v95-head{display:flex;justify-content:space-between;align-items:flex-end;gap:14px;flex-wrap:wrap;margin-bottom:14px}.v95-title{font-size:clamp(32px,5vw,54px);line-height:.95;letter-spacing:-.04em;margin:5px 0 8px}.v95-sub{color:var(--m);max-width:900px;line-height:1.5}
      .v95-kpis{display:grid;grid-template-columns:repeat(6,minmax(105px,1fr));gap:9px;margin:15px 0}.v95-kpi{background:#0d1013;border:1px solid var(--b);border-radius:12px;padding:12px}.v95-kpi b{display:block;font-size:25px}.v95-kpi span{font-size:9px;color:var(--m);text-transform:uppercase;letter-spacing:.07em}
      .v95-toolbar{display:grid;grid-template-columns:minmax(220px,1fr) 170px 170px;gap:8px;margin:12px 0 14px}.v95-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:11px}.v95-card{background:linear-gradient(180deg,#15191d,#0e1114);border:1px solid var(--b);border-radius:15px;padding:15px}.v95-card[data-priority="CRITICAL"]{border-color:#7a2631}.v95-card[data-priority="HIGH"]{border-color:#6c4a20}
      .v95-pills{display:flex;gap:6px;flex-wrap:wrap;margin:9px 0}.v95-pill{display:inline-flex;border:1px solid currentColor;border-radius:999px;padding:5px 8px;font-size:9px;font-weight:900;letter-spacing:.06em}.v95-red{color:#ff94a2;background:#2a0e13}.v95-warn{color:#ffc480;background:#2a2010}.v95-blue{color:#9cc4ff;background:#102238}.v95-green{color:#8be7ae;background:#0d261a}.v95-gray{color:#adb4bc;background:#181b20}
      .v95-action{background:#0b0e11;border:1px solid var(--b);border-radius:11px;padding:11px;margin:10px 0}.v95-action span{display:block;font-size:9px;color:var(--m);text-transform:uppercase;letter-spacing:.07em}.v95-action b{display:block;margin-top:4px;line-height:1.4}.v95-evidence{font-size:11px;color:#c7cbd0;background:#101317;border-radius:8px;padding:7px 9px;border-left:2px solid #434b55;margin:5px 0}
      .v95-actions{display:flex;gap:7px;flex-wrap:wrap;margin-top:11px}.v95-actions .btn{min-width:105px}.v95-history{display:grid;gap:8px}.v95-history-row{display:grid;grid-template-columns:160px 1fr 150px;gap:10px;align-items:center;background:#0e1114;border:1px solid var(--b);border-radius:10px;padding:10px}.v95-empty{text-align:center;padding:28px;color:var(--m)}
      @media(max-width:1150px){.v95-kpis{grid-template-columns:repeat(3,1fr)}.v95-grid{grid-template-columns:1fr}}@media(max-width:720px){.v95-kpis{grid-template-columns:repeat(2,1fr)}.v95-toolbar{grid-template-columns:1fr}.v95-history-row{grid-template-columns:1fr}.v95-actions .btn{flex:1}}
    `;document.head.appendChild(s);
  }

  async function api(name,body){return req('/rest/v1/rpc/'+name,{method:'POST',body:JSON.stringify(body)});}
  async function loadWorkspace(){return api('get_coach_action_workspace_v95',{p_actor_id:me.id});}
  function pill(label,cls='v95-gray'){return `<span class="v95-pill ${cls}">${esc(label)}</span>`;}
  function fmtDate(v){if(!v)return '—';try{return new Date(v).toLocaleString('es-CL');}catch{return v;}}

  function routeTarget(x){
    const target=clean(x.execution_target);
    if(target==='lifecycle')return setView('lifecycle');
    if(target==='programming'){
      const pid=x.lifecycle?.draft_program_id||x.lifecycle?.active_program_id||'';
      if(pid&&typeof programEditor==='function')return programEditor(pid);
      if(typeof newProgram==='function'){
        newProgram();setTimeout(()=>{const s=$('#programClient');if(s){s.value=x.client_id||'';s.dispatchEvent(new Event('change',{bubbles:true}));}},0);return;
      }
      return setView('programs');
    }
    if(target==='training_trends'){
      if(typeof window.openTrainingTrendsV85==='function')return window.openTrainingTrendsV85(x.client_id);
      return clientDetail(x.client_id);
    }
    if(target==='progression'){try{return setView('progression');}catch{return clientDetail(x.client_id);}}
    if(target==='communications'||target==='commercial'||target==='client_profile')return clientDetail(x.client_id);
    return clientDetail(x.client_id);
  }

  async function decide(x,decision){
    let modifiedCode=null,modifiedAction=null,note=null;
    if(decision==='MODIFIED'){
      modifiedAction=prompt('Acción que quieres ejecutar como coach:',x.effective_action||x.recommended_action||'');
      if(modifiedAction===null)return;
      modifiedAction=clean(modifiedAction);if(!modifiedAction){alert('Debes escribir la acción modificada.');return;}
      modifiedCode='custom_coach_action';
      note=prompt('Nota del coach (opcional):','')||null;
    }else if(decision==='REJECTED'){
      note=prompt('Motivo del rechazo:','');if(note===null)return;note=clean(note);if(!note){alert('Debes indicar el motivo del rechazo.');return;}
    }else{
      note=prompt('Nota del coach (opcional):','')||null;
    }
    try{
      await api('decide_coach_action_v95',{p_actor_id:me.id,p_recommendation_key:x.recommendation_key,p_client_id:x.client_id,p_decision:decision,p_modified_action_code:modifiedCode,p_modified_action:modifiedAction,p_note:note});
      await refresh();
    }catch(e){alert('No se pudo registrar la decisión: '+String(e?.message||e));}
  }

  async function start(x){
    if(!x.workspace_id){alert('Primero acepta o modifica la recomendación.');return;}
    try{
      const r=await api('start_coach_action_v95',{p_actor_id:me.id,p_workspace_id:x.workspace_id});
      state.clientFilter=x.client_id;await refresh(false);routeTarget({...x,...r});
    }catch(e){alert('No se pudo iniciar la acción: '+String(e?.message||e));}
  }

  async function complete(x){
    if(!x.workspace_id)return;
    const note=prompt('Describe brevemente qué se hizo y el resultado:','');
    if(note===null)return;if(!clean(note)){alert('La nota de resolución es obligatoria.');return;}
    try{await api('complete_coach_action_v95',{p_actor_id:me.id,p_workspace_id:x.workspace_id,p_resolution_note:clean(note)});await refresh();}
    catch(e){alert('No se pudo completar la acción: '+String(e?.message||e));}
  }

  function buttons(x){
    const st=clean(x.workflow_status||'PENDING');
    if(st==='PENDING')return `<button class="btn primary small v95Accept">ACEPTAR</button><button class="btn small v95Modify">MODIFICAR</button><button class="btn small v95Reject">RECHAZAR</button>`;
    if(st==='READY')return `<button class="btn primary small v95Start">EJECUTAR</button><button class="btn small v95Modify">MODIFICAR</button><button class="btn small v95Reject">RECHAZAR</button>`;
    if(st==='EXECUTING')return `<button class="btn primary small v95Go">IR AL MÓDULO</button><button class="btn small v95Complete">MARCAR COMPLETADA</button>`;
    return `<button class="btn small v95Open">ABRIR FICHA</button>`;
  }

  function card(x){
    const status=clean(x.workflow_status||'PENDING'),pri=clean(x.priority||'NORMAL');
    const evidence=arr(x.reasons).slice(0,4);
    return `<article class="v95-card" data-key="${esc(x.recommendation_key)}" data-priority="${esc(pri)}">
      <div class="row"><div class="grow"><div class="ey">V95 · ACCIÓN DEL COACH</div><h2 style="margin:4px 0 2px">${esc(x.client_name||'Cliente')}</h2><div class="muted">${esc(x.primary_goal||'Objetivo no definido')}</div></div><div style="text-align:right"><b style="font-size:26px">${esc(x.command_score??0)}</b><div class="muted" style="font-size:9px">SCORE</div></div></div>
      <div class="v95-pills">${pill(pri,priorityClass[pri]||'v95-gray')}${pill(clean(x.primary_domain||'MONITORING'),'v95-gray')}${pill(statusLabel[status]||status,status==='REJECTED'?'v95-red':status==='COMPLETED'?'v95-green':status==='EXECUTING'?'v95-blue':'v95-warn')}</div>
      <div class="v95-action"><span>${x.decision==='MODIFIED'?'Acción modificada por el coach':'Acción recomendada'}</span><b>${esc(x.effective_action||x.recommended_action||'—')}</b></div>
      ${x.coach_note?`<div class="v95-evidence"><b>Nota coach:</b> ${esc(x.coach_note)}</div>`:''}
      ${evidence.map(r=>`<div class="v95-evidence">${esc(r)}</div>`).join('')}
      <div class="v95-actions">${buttons(x)}</div>
    </article>`;
  }

  function historyRow(h){
    const snap=h.recommendation_snapshot||{};
    return `<div class="v95-history-row"><div>${pill(statusLabel[h.workflow_status]||h.workflow_status,h.workflow_status==='COMPLETED'?'v95-green':h.workflow_status==='REJECTED'?'v95-red':'v95-gray')}<div class="muted" style="margin-top:5px">${esc(fmtDate(h.updated_at))}</div></div><div><b>${esc(snap.client_name||'Cliente')}</b><div class="muted">${esc(h.effective_action||'—')}</div>${h.resolution_note?`<div style="margin-top:5px">${esc(h.resolution_note)}</div>`:''}</div><div class="muted">${esc(h.completion_verification||h.decision||'')}</div></div>`;
  }

  function bind(items){
    const byKey=new Map(items.map(x=>[x.recommendation_key,x]));
    $$('.v95-card[data-key]').forEach(el=>{
      const x=byKey.get(el.dataset.key);if(!x)return;
      el.querySelector('.v95Accept')?.addEventListener('click',()=>decide(x,'ACCEPTED'));
      el.querySelector('.v95Modify')?.addEventListener('click',()=>decide(x,'MODIFIED'));
      el.querySelector('.v95Reject')?.addEventListener('click',()=>decide(x,'REJECTED'));
      el.querySelector('.v95Start')?.addEventListener('click',()=>start(x));
      el.querySelector('.v95Go')?.addEventListener('click',()=>routeTarget(x));
      el.querySelector('.v95Complete')?.addEventListener('click',()=>complete(x));
      el.querySelector('.v95Open')?.addEventListener('click',()=>clientDetail(x.client_id));
    });
  }

  function draw(){
    const d=state.data||{},all=arr(d.current),q=clean($('#v95Search')?.value).toLowerCase(),st=$('#v95Status')?.value||'',pri=$('#v95Priority')?.value||'';
    const visible=all.filter(x=>(!state.clientFilter||x.client_id===state.clientFilter)&&(!st||x.workflow_status===st)&&(!pri||x.priority===pri)&&(!q||(`${x.client_name||''} ${x.primary_goal||''} ${x.effective_action||x.recommended_action||''}`).toLowerCase().includes(q)));
    const grid=$('#v95Grid');if(grid)grid.innerHTML=visible.length?visible.map(card).join(''):'<div class="v95-card v95-empty">No hay acciones para este filtro.</div>';
    bind(visible);
  }

  async function refresh(redraw=true){state.data=await loadWorkspace();if(redraw)renderWorkspace();else draw();}

  async function renderWorkspace(){
    ensureStyle();const root=$('#content');if(!root)return;root.innerHTML='<div class="card muted">Cargando Coach Action Workspace…</div>';
    try{
      if(!state.data)state.data=await loadWorkspace();const d=state.data,s=d.summary||{},history=arr(d.history);
      root.innerHTML=`<div class="v95-head"><div><div class="ey">V95 · HUMAN-IN-THE-LOOP EXECUTION</div><h1 class="v95-title">COACH ACTION WORKSPACE</h1><p class="v95-sub">Convierte recomendaciones de Coach AI en decisiones humanas auditables. Aceptar o modificar solo prepara un handoff; ejecutar abre el módulo correcto y nunca publica, modifica rutinas, envía mensajes ni altera cobros automáticamente.</p></div><div class="row"><button id="v95ClearClient" class="btn" ${state.clientFilter?'':'style="display:none"'}>VER TODOS</button><button id="v95Refresh" class="btn">↻ ACTUALIZAR</button></div></div>
      <div class="v95-kpis"><div class="v95-kpi"><span>Acciones actuales</span><b>${esc(s.total??0)}</b></div><div class="v95-kpi"><span>Pendientes</span><b>${esc(s.pending??0)}</b></div><div class="v95-kpi"><span>Listas</span><b>${esc(s.ready??0)}</b></div><div class="v95-kpi"><span>En ejecución</span><b>${esc(s.executing??0)}</b></div><div class="v95-kpi"><span>Críticas</span><b>${esc(s.critical??0)}</b></div><div class="v95-kpi"><span>Alta prioridad</span><b>${esc(s.high??0)}</b></div></div>
      <div class="v95-toolbar"><input id="v95Search" class="input" placeholder="Buscar cliente o acción…" style="margin:0"><select id="v95Status" class="input" style="margin:0"><option value="">Todos los estados</option><option value="PENDING">Pendiente</option><option value="READY">Lista</option><option value="EXECUTING">En ejecución</option><option value="COMPLETED">Completada</option><option value="REJECTED">Rechazada</option></select><select id="v95Priority" class="input" style="margin:0"><option value="">Todas las prioridades</option><option>CRITICAL</option><option>HIGH</option><option>MEDIUM</option><option>NORMAL</option></select></div>
      <section><div class="row"><h2 class="grow">Bandeja accionable</h2><span class="muted">V94 → decisión coach → handoff seguro</span></div><div id="v95Grid" class="v95-grid"></div></section>
      <section style="margin-top:22px"><div class="row"><h2 class="grow">Historial de decisiones</h2><span class="muted">últimas 100 acciones</span></div><div class="v95-history">${history.slice(0,30).map(historyRow).join('')||'<div class="v95-card v95-empty">Todavía no hay decisiones persistidas.</div>'}</div></section>
      <div class="card" style="margin-top:20px"><div class="ey">GUARDRAILS V95</div><div class="muted" style="margin-top:7px">Decisión humana obligatoria · handoff-only · auto-publicación OFF · auto-edición OFF · auto-mensajería OFF · auto-cobros OFF · completar = declaración del coach, no verificación automática.</div></div>`;
      $('#v95Search').oninput=draw;$('#v95Status').onchange=draw;$('#v95Priority').onchange=draw;$('#v95Refresh').onclick=async()=>{state.data=null;await refresh();};
      $('#v95ClearClient').onclick=()=>{state.clientFilter=null;renderWorkspace();};draw();
    }catch(e){root.innerHTML=`<div class="card" style="border-color:#64202b"><b>No se pudo cargar V95</b><div class="muted">${esc(String(e?.message||e))}</div></div>`;}
  }

  function installNavigation(){const nav=document.querySelector('.nav');if(!nav||nav.querySelector('[data-v="'+VIEW+'"]'))return;const b=document.createElement('button');b.dataset.v=VIEW;b.textContent='✓ Acciones';const ai=nav.querySelector('[data-v="coach-ai"]');ai?ai.after(b):nav.prepend(b);b.onclick=()=>setView(VIEW);}

  if(typeof render!=='function'||typeof setView!=='function'||typeof req!=='function'){console.error('CV Coach V95: admin host contract unavailable');return;}
  const baseRender=render,baseSetView=setView;
  render=async function renderV95Aware(){if(view===VIEW)return renderWorkspace();return baseRender();};
  setView=function setViewV95Aware(next){if(next!==VIEW)return baseSetView(next);clientDetailToken++;view=VIEW;$$('.nav button').forEach(b=>b.classList.toggle('on',b.dataset.v===VIEW));$('#topTitle').textContent='Coach Action Workspace';return render();};
  installNavigation();
  window.coachActionWorkspaceV95={version:'V95',open:(clientId)=>{state.clientFilter=clientId||null;state.data=null;setView(VIEW);},refresh:()=>{state.data=null;return refresh();}};
  console.log('CV_ADMIN_COACH_ACTION_WORKSPACE_V95_READY');
})();
