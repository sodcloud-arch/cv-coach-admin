/* CV Coach V93 — Client Lifecycle & Onboarding Control Center */
(() => {
  const VIEW = 'lifecycle';
  const STYLE_ID = 'cv-v93-lifecycle-style';
  const stageMeta = {
    account_blocked:['Cuenta bloqueada','v93-red'],
    profile_incomplete:['Perfil incompleto','v93-warn'],
    onboarding_in_progress:['Onboarding','v93-blue'],
    onboarding_review:['Revisar onboarding','v93-warn'],
    coach_assignment:['Asignar coach','v93-warn'],
    program_draft:['Borrador pendiente','v93-blue'],
    program_needed:['Crear programa','v93-warn'],
    operational:['Operativo','v93-green'],
    needs_review:['Revisar','v93-warn']
  };
  const nextMeta = {
    review_account_status:'Revisar estado de cuenta',
    review_client_profile:'Revisar perfil',
    generate_access_link:'Generar acceso',
    wait_for_onboarding:'Esperar onboarding',
    wait_for_onboarding_completion:'Esperar finalización',
    review_onboarding:'Revisar onboarding',
    review_coach_assignment:'Revisar relación coach',
    finish_program_draft:'Terminar borrador',
    create_initial_program:'Crear programa inicial',
    monitor_client:'Seguimiento normal',
    review_client:'Revisar cliente'
  };

  function ensureStyle(){
    if(document.getElementById(STYLE_ID)) return;
    const s=document.createElement('style');
    s.id=STYLE_ID;
    s.textContent=`
      .v93-head{display:flex;gap:14px;justify-content:space-between;align-items:flex-end;flex-wrap:wrap;margin-bottom:14px}
      .v93-title{font-size:clamp(30px,5vw,52px);line-height:.96;margin:6px 0 8px;letter-spacing:-.03em}.v93-sub{color:var(--m);max-width:840px;line-height:1.5}
      .v93-kpis{display:grid;grid-template-columns:repeat(5,minmax(110px,1fr));gap:9px;margin:14px 0}.v93-kpi{background:#0d1013;border:1px solid var(--b);border-radius:12px;padding:12px}.v93-kpi b{display:block;font-size:25px}.v93-kpi span{font-size:9px;color:var(--m);text-transform:uppercase;letter-spacing:.07em}
      .v93-toolbar{display:grid;grid-template-columns:minmax(220px,1fr) 220px;gap:9px;margin:12px 0}.v93-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:11px}.v93-card{background:linear-gradient(180deg,#14181c,#0e1114);border:1px solid var(--b);border-radius:14px;padding:15px}.v93-card.v93-priority{border-color:#62451f}
      .v93-pill{display:inline-flex;border:1px solid currentColor;border-radius:999px;padding:5px 8px;font-size:9px;font-weight:900;letter-spacing:.05em;text-transform:uppercase}.v93-green{color:#7de6a6;background:#0d261a}.v93-blue{color:#9cc4ff;background:#102238}.v93-warn{color:#ffc480;background:#2a2010}.v93-red{color:#ff91a0;background:#2a0e13}.v93-gray{color:#aab0b8;background:#181b20}
      .v93-status{display:flex;gap:6px;flex-wrap:wrap;margin:9px 0}.v93-steps{display:grid;grid-template-columns:repeat(5,1fr);gap:5px;margin:11px 0}.v93-step{border:1px solid var(--b);border-radius:8px;padding:7px 5px;text-align:center;font-size:9px;color:var(--m)}.v93-step.done{border-color:#245b3c;color:#8be7ae}.v93-step.current{border-color:#62451f;color:#ffc480}.v93-meta{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:7px;margin:10px 0}.v93-meta>div{background:#0c0f12;border:1px solid var(--b);border-radius:9px;padding:9px}.v93-meta span{display:block;font-size:9px;color:var(--m);text-transform:uppercase}.v93-meta b{font-size:11px;word-break:break-word}.v93-actions{display:flex;gap:7px;flex-wrap:wrap;margin-top:10px}.v93-actions .btn{min-width:120px}.v93-note{font-size:10px;color:var(--m);line-height:1.45;margin-top:8px}.v93-empty{padding:28px;text-align:center;color:var(--m)}
      @media(max-width:1050px){.v93-kpis{grid-template-columns:repeat(3,1fr)}.v93-grid{grid-template-columns:1fr}}@media(max-width:720px){.v93-kpis{grid-template-columns:repeat(2,1fr)}.v93-toolbar{grid-template-columns:1fr}.v93-steps{grid-template-columns:1fr}.v93-actions .btn{flex:1}}
    `;
    document.head.appendChild(s);
  }
  const clean=v=>v==null?'':String(v).trim();
  const date=v=>{if(!v)return '—';const d=new Date(v);return Number.isNaN(d.getTime())?'—':d.toLocaleDateString('es-CL')};
  const pill=(label,cls='v93-gray')=>`<span class="v93-pill ${cls}">${esc(label)}</span>`;
  const stageLabel=s=>stageMeta[s]?.[0]||s||'Revisar';
  const stageClass=s=>stageMeta[s]?.[1]||'v93-gray';
  const onboardDone=s=>s==='approved';
  const accessDone=x=>x.access_state==='activity_detected';
  const coachDone=x=>x.coach_relationship_status==='active';
  const programDone=x=>!!x.active_program_id;
  const subscriptionHealthy=x=>['active','trialing'].includes(clean(x.subscription_status));

  async function rpc(name,payload={}){return req('/rest/v1/rpc/'+name,{method:'POST',body:JSON.stringify(payload)});}

  function stepHtml(x){
    const steps=[
      ['Acceso',accessDone(x),['no_access_link','setup_link_generated','access_revoked'].includes(x.access_state)],
      ['Onboarding',onboardDone(x),['pending','in_progress','completed'].includes(x.onboarding_status)],
      ['Coach',coachDone(x),onboardDone(x)&&!coachDone(x)],
      ['Programa',programDone(x),onboardDone(x)&&coachDone(x)&&!programDone(x)],
      ['Operación',x.lifecycle_stage==='operational',x.lifecycle_stage==='operational']
    ];
    return `<div class="v93-steps">${steps.map(([l,done,current])=>`<div class="v93-step ${done?'done':current?'current':''}">${done?'✓ ':''}${esc(l)}</div>`).join('')}</div>`;
  }

  function accessLabel(x){
    return ({activity_detected:'Actividad detectada',setup_link_generated:'Enlace generado',access_revoked:'Acceso revocado',no_access_link:'Sin enlace'})[x.access_state]||x.access_state||'—';
  }
  function onboardingLabel(s){return ({pending:'Pendiente',in_progress:'En progreso',completed:'Por revisar',approved:'Aprobado'})[s]||s||'—';}
  function subscriptionLabel(s){return ({pending:'Pendiente',trialing:'Prueba',active:'Activa',past_due:'Vencida',cancelled:'Cancelada',ended:'Finalizada'})[s]||s||'Sin suscripción';}

  function card(x){
    const priority=x.lifecycle_stage!=='operational';
    const program=x.draft_program_id?`Borrador V${x.draft_program_version??'—'}`:x.active_program_id?`Activo V${x.active_program_version??'—'}`:'Sin programa';
    const email=clean(x.email);
    const subscriptionCls=subscriptionHealthy(x)?'v93-green':x.subscription_status==='past_due'?'v93-red':'v93-gray';
    return `<article class="v93-card ${priority?'v93-priority':''}" data-client="${esc(x.client_id)}">
      <div class="row"><div class="grow"><div class="ey">CLIENT LIFECYCLE · V93</div><h2 style="margin:4px 0 2px">${esc(x.client_name||'Cliente')}</h2><div class="muted">${esc(x.primary_goal||'Objetivo no definido')}</div></div>${pill(stageLabel(x.lifecycle_stage),stageClass(x.lifecycle_stage))}</div>
      <div class="v93-status">${pill(accessLabel(x),accessDone(x)?'v93-green':'v93-blue')} ${pill(onboardingLabel(x.onboarding_status),onboardDone(x)?'v93-green':x.onboarding_status==='completed'?'v93-warn':'v93-blue')} ${pill(x.coach_relationship_status==='active'?'Coach activo':'Coach pendiente',coachDone(x)?'v93-green':'v93-gray')} ${pill(subscriptionLabel(x.subscription_status),subscriptionCls)}</div>
      ${stepHtml(x)}
      <div class="v93-meta"><div><span>Correo operativo</span><b>${esc(email||'No disponible')}</b></div><div><span>Respuestas onboarding</span><b>${Number(x.onboarding_response_count||0)}</b></div><div><span>Programa</span><b>${esc(program)}</b></div><div><span>Plan / renovación</span><b>${esc(x.plan_name||'—')} · ${date(x.subscription_renews_at)}</b></div></div>
      <div class="card" style="padding:10px"><div class="muted">Siguiente acción</div><b>${esc(nextMeta[x.next_action]||x.next_action||'Revisar')}</b></div>
      <div class="v93-actions"><button class="btn small v93Open" data-id="${esc(x.client_id)}">ABRIR FICHA</button>${x.onboarding_status==='completed'?`<button class="btn good small v93Onboarding" data-id="${esc(x.client_id)}">REVISAR ONBOARDING</button>`:''}${x.draft_program_id?`<button class="btn primary small v93Program" data-program="${esc(x.draft_program_id)}">ABRIR BORRADOR</button>`:x.active_program_id?`<button class="btn small v93Program" data-program="${esc(x.active_program_id)}">ABRIR PROGRAMA</button>`:onboardDone(x)&&coachDone(x)?`<button class="btn primary small v93CreateProgram" data-id="${esc(x.client_id)}">CREAR PROGRAMA</button>`:''}${email?`<button class="btn small v93Access" data-id="${esc(x.client_id)}">REGENERAR ACCESO</button>`:''}</div>
      <div class="v93-note">V93 no publica rutinas ni aprueba onboarding automáticamente. Las acciones reutilizan los backends existentes y requieren una acción explícita del coach.</div>
    </article>`;
  }

  function validateSetupLink(raw){
    if(typeof raw!=='string'||!raw) throw Error('El backend no devolvió un enlace de activación.');
    let u;try{u=new URL(raw)}catch{throw Error('El enlace de activación no es válido.');}
    const token=u.searchParams.get('token_hash');
    if(u.protocol!=='https:'||u.origin!=='https://cv-coach-roan.vercel.app'||u.username||u.password||u.pathname!=='/'||u.hash||u.searchParams.size!==3||u.searchParams.get('setup')!=='1'||u.searchParams.get('type')!=='recovery'||!token) throw Error('El enlace de activación no cumple el contrato de seguridad.');
    return raw;
  }

  function showSetupLink(x,raw){
    const link=validateSetupLink(raw);
    $('#modal').innerHTML=`<div class="modal"><div class="card"><div class="row"><div class="grow"><div class="ey">ACCESO CLIENTE · V93</div><h2>Enlace regenerado</h2></div><button id="v93CloseLink" class="btn small">✕</button></div><p class="sub">Se regeneró el acceso de ${esc(x.client_name)}. El cliente podrá crear/restablecer su contraseña y continuar el onboarding.</p><textarea id="v93SetupLink" class="input" readonly rows="4">${esc(link)}</textarea><button id="v93CopyLink" class="btn primary" style="width:100%">COPIAR ENLACE</button><div id="v93CopyStatus" class="status muted"></div></div></div>`;
    const close=()=>$('#modal').innerHTML='';$('#v93CloseLink').onclick=close;$('#v93CopyLink').onclick=async()=>{const out=$('#v93CopyStatus');try{if(!navigator.clipboard?.writeText)throw Error('Portapapeles no disponible');await navigator.clipboard.writeText(link);out.textContent='Enlace copiado.'}catch(e){out.textContent='Copia el enlace manualmente desde el campo visible.'}};
  }

  function confirmAccess(x,onConfirm){
    $('#modal').innerHTML=`<div class="modal"><div class="card"><div class="ey">CONFIRMACIÓN V93</div><h2>Regenerar acceso</h2><p class="sub">Esto generará un nuevo enlace de acceso para <b>${esc(x.client_name)}</b>. No cambia onboarding, programación ni suscripción.</p><label>Escribe REGENERAR para confirmar</label><input id="v93ConfirmAccess" class="input"><div class="row"><button id="v93CancelAccess" class="btn grow">CANCELAR</button><button id="v93DoAccess" class="btn primary grow">REGENERAR</button></div><div id="v93AccessStatus" class="status muted"></div></div></div>`;
    $('#v93CancelAccess').onclick=()=>$('#modal').innerHTML='';$('#v93DoAccess').onclick=async()=>{const out=$('#v93AccessStatus'),b=$('#v93DoAccess');if($('#v93ConfirmAccess').value.trim()!=='REGENERAR')return out.textContent='Debes escribir REGENERAR exactamente.';try{b.disabled=true;out.textContent='Generando enlace…';await onConfirm()}catch(e){out.textContent='No se pudo regenerar: '+String(e?.message||e);b.disabled=false}};
  }

  function preselectProgram(clientId){
    if(typeof newProgram!=='function') return toast('El flujo de programación no está disponible.');
    newProgram();
    setTimeout(()=>{const s=$('#programClient');if(!s)return;s.value=clientId;s.dispatchEvent(new Event('change',{bubbles:true}));},0);
  }

  function bind(items){
    const map=new Map(items.map(x=>[x.client_id,x]));
    $$('.v93Open,.v93Onboarding').forEach(b=>b.onclick=()=>clientDetail(b.dataset.id));
    $$('.v93Program').forEach(b=>b.onclick=()=>programEditor(b.dataset.program));
    $$('.v93CreateProgram').forEach(b=>b.onclick=()=>preselectProgram(b.dataset.id));
    $$('.v93Access').forEach(b=>b.onclick=()=>{const x=map.get(b.dataset.id);if(!x||!clean(x.email))return toast('No hay correo operativo registrado.');confirmAccess(x,async()=>{const d=await req('/functions/v1/provision-client',{method:'POST',body:JSON.stringify({email:clean(x.email).toLowerCase(),first_name:clean(x.first_name)||clean(x.client_name)||'Cliente',last_name:clean(x.last_name),phone:clean(x.phone)||null,client_url:'https://cv-coach-roan.vercel.app'})});if(String(d?.client_id||'')!==String(x.client_id))throw Error('El backend devolvió una identidad distinta al cliente seleccionado.');showSetupLink(x,d?.setup_link);cache={};});});
  }

  async function renderLifecycle(){
    ensureStyle();
    const root=$('#content');if(!root)return;
    root.innerHTML='<div class="card muted">Cargando ciclo de vida de clientes…</div>';
    try{
      const data=await rpc('get_client_lifecycle_center_v93',{p_actor_id:me.id});
      const items=Array.isArray(data?.items)?data.items:[];
      const counts={total:items.length,action:items.filter(x=>x.lifecycle_stage!=='operational').length,onboarding:items.filter(x=>x.lifecycle_stage==='onboarding_review').length,program:items.filter(x=>['program_needed','program_draft'].includes(x.lifecycle_stage)).length,operational:items.filter(x=>x.lifecycle_stage==='operational').length};
      root.innerHTML=`<div class="v93-head"><div><div class="ey">V93 · CLIENT LIFECYCLE</div><h1 class="v93-title">CLIENTES & ONBOARDING</h1><p class="v93-sub">Alta, acceso, onboarding, relación coach y programación en una sola vista. V93 coordina los módulos existentes; no crea un segundo sistema de clientes.</p></div><div class="row"><button id="v93NewClient" class="btn primary">+ NUEVO CLIENTE</button><button id="v93Refresh" class="btn">↻ ACTUALIZAR</button></div></div><div class="v93-kpis"><div class="v93-kpi"><span>Clientes</span><b>${counts.total}</b></div><div class="v93-kpi"><span>Requieren acción</span><b>${counts.action}</b></div><div class="v93-kpi"><span>Onboarding por revisar</span><b>${counts.onboarding}</b></div><div class="v93-kpi"><span>Programación pendiente</span><b>${counts.program}</b></div><div class="v93-kpi"><span>Operativos</span><b>${counts.operational}</b></div></div><div class="v93-toolbar"><input id="v93Search" class="input" placeholder="Buscar por nombre o correo…" style="margin:0"><select id="v93Filter" class="input" style="margin:0"><option value="">Todos los estados</option>${Object.entries(stageMeta).map(([k,v])=>`<option value="${k}">${esc(v[0])}</option>`).join('')}</select></div><div id="v93Grid" class="v93-grid"></div>`;
      const draw=()=>{const q=clean($('#v93Search')?.value).toLowerCase(),f=$('#v93Filter')?.value||'',visible=items.filter(x=>(!f||x.lifecycle_stage===f)&&(!q||(`${x.client_name||''} ${x.email||''}`).toLowerCase().includes(q)));$('#v93Grid').innerHTML=visible.length?visible.map(card).join(''):'<div class="v93-card v93-empty">No hay clientes para este filtro.</div>';bind(visible);};
      $('#v93Search').oninput=draw;$('#v93Filter').onchange=draw;$('#v93Refresh').onclick=renderLifecycle;$('#v93NewClient').onclick=()=>newClient();draw();
    }catch(e){root.innerHTML=`<div class="card" style="border-color:#64202b"><b>No se pudo cargar V93</b><div class="muted">${esc(String(e?.message||e))}</div></div>`;}
  }

  function installNavigation(){
    const nav=document.querySelector('.nav');if(!nav||nav.querySelector('[data-v="lifecycle"]'))return;
    const b=document.createElement('button');b.dataset.v=VIEW;b.textContent='◎ Clientes & Onboarding';
    const clients=nav.querySelector('[data-v="clients"]');clients?clients.after(b):nav.prepend(b);b.onclick=()=>setView(VIEW);
  }

  if(typeof render!=='function'||typeof setView!=='function'||typeof req!=='function'){console.error('CV Coach V93: admin host contract unavailable');return;}
  const baseRender=render,baseSetView=setView;
  render=async function renderV93Aware(){if(view===VIEW)return renderLifecycle();return baseRender();};
  setView=function setViewV93Aware(next){if(next!==VIEW)return baseSetView(next);clientDetailToken++;view=VIEW;$$('.nav button').forEach(b=>b.classList.toggle('on',b.dataset.v===VIEW));$('#topTitle').textContent='Clientes & Onboarding';return render();};
  installNavigation();
  window.clientLifecycleV93={render:renderLifecycle,version:'V93'};
})();
