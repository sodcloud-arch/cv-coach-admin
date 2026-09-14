/* CV Coach V100 — Exercise Asset Guardrail & Auto-Backfill */
(() => {
  const VIEW='exercise-assets-v100';
  const MARK='CV_ADMIN_EXERCISE_ASSETS_V100_READY';
  const statusLabel={approved:'APROBADO',external_verified:'VERIFICADO',external_unverified:'EXTERNO SIN VERIFICAR',missing:'FALTA ASSET',generation_pending:'GENERACIÓN PENDIENTE',pending_review:'REVISIÓN PENDIENTE',failed:'FALLÓ',queued:'EN COLA',generating:'GENERANDO'};
  const arr=v=>Array.isArray(v)?v:[];
  const clean=v=>v==null?'':String(v).trim();
  const rpc=(name,body)=>req('/rest/v1/rpc/'+name,{method:'POST',body:JSON.stringify(body)});

  // V100 wraps only AI program generation. Every other request keeps the mature host behavior.
  if(typeof req==='function'&&!window.__cvV100ReqWrapped){
    const previous=req;
    req=async function cvV100Req(path,opt={},retry=true){
      const target=path==='/functions/v1/generate-ai-program'?'/functions/v1/generate-ai-program-v100':path;
      return previous(target,opt,retry);
    };
    window.__cvV100ReqWrapped=true;
  }

  function color(status){return ['approved','external_verified'].includes(status)?'green':status==='failed'?'red':['pending_review','generation_pending','queued','generating','external_unverified','missing'].includes(status)?'warn':'blue'}
  function badge(text,cls='blue'){return `<span class="pill ${cls}">${esc(text)}</span>`}
  function requestName(r,itemMap){return clean(r.proposed_name)||clean(itemMap.get(r.exercise_id)?.name)||'Ejercicio pendiente'}

  async function center(){return rpc('get_exercise_asset_control_center_v100',{p_actor_id:me.id})}

  async function generate(requestId,button){
    try{
      button.disabled=true;button.textContent='GENERANDO…';
      const out=await req('/functions/v1/generate-exercise-asset-v100',{method:'POST',body:JSON.stringify({request_id:requestId})});
      toast(out?.status==='pending_review'?'Lámina generada · requiere revisión':'Solicitud procesada');
      await renderAssets();
    }catch(e){toast('No se pudo generar: '+String(e?.message||e));button.disabled=false;button.textContent='GENERAR LÁMINA'}
  }

  async function review(exerciseId,decision){
    const note=decision==='reject'?prompt('Motivo del rechazo (recomendado):','')||'Asset rechazado en QA V100':prompt('Nota de aprobación (opcional):','')||null;
    if(decision==='reject'&&!confirm('¿Rechazar este asset? No se activará ni publicará automáticamente.'))return;
    try{
      await rpc('review_exercise_asset_v100',{p_actor_id:me.id,p_exercise_id:exerciseId,p_decision:decision,p_note:note});
      toast(decision==='approve'?'Asset aprobado e integrado a biblioteca':'Asset rechazado');
      await renderAssets();
    }catch(e){toast('No se pudo revisar: '+String(e?.message||e))}
  }

  async function requestBackfill(exerciseId){
    try{
      await rpc('request_exercise_asset_backfill_v100',{p_actor_id:me.id,p_exercise_id:exerciseId,p_reason:'Solicitado desde Assets V100',p_program_id:null});
      toast('Backfill encolado');await renderAssets();
    }catch(e){toast('No se pudo encolar: '+String(e?.message||e))}
  }

  function openNewExercise(){
    $('#modal').innerHTML=`<div class="modal"><div class="card"><div class="row"><div class="grow"><div class="ey">V100 · LIBRARY GAP</div><h2>Solicitar ejercicio nuevo</h2></div><button id="v100CloseNew" class="btn small">✕</button></div><p class="sub">Crea una solicitud, no un ejercicio visible. La lámina se genera y el ejercicio permanece inactivo hasta aprobación.</p><label>Nombre *</label><input id="v100Name" class="input"><label>Músculo principal *</label><input id="v100Muscle" class="input"><label>Equipamiento *</label><input id="v100Equipment" class="input"><label>Patrón de movimiento *</label><input id="v100Pattern" class="input"><label>Unidad</label><select id="v100Unit" class="input"><option value="reps">Repeticiones</option><option value="seconds">Segundos</option></select><label>Razón</label><textarea id="v100Reason" class="input" rows="3"></textarea><button id="v100Create" class="btn primary" style="width:100%">CREAR SOLICITUD</button><div id="v100NewStatus" class="status muted"></div></div></div>`;
    $('#v100CloseNew').onclick=()=>$('#modal').innerHTML='';
    $('#v100Create').onclick=async()=>{
      const b=$('#v100Create'),s=$('#v100NewStatus');
      try{
        const name=$('#v100Name').value.trim(),muscle=$('#v100Muscle').value.trim(),equipment=$('#v100Equipment').value.trim(),pattern=$('#v100Pattern').value.trim();
        if(!name||!muscle||!equipment||!pattern)throw Error('Completa nombre, músculo, equipamiento y patrón.');
        b.disabled=true;s.textContent='Creando solicitud…';
        const r=await rpc('resolve_exercise_library_gap_v100',{p_actor_id:me.id,p_name:name,p_primary_muscle:muscle,p_equipment:equipment,p_movement_pattern:pattern,p_prescription_unit:$('#v100Unit').value,p_reason:$('#v100Reason').value.trim()||'Solicitud manual desde Assets V100',p_program_id:null});
        if(r?.ready){$('#modal').innerHTML='';toast('Ya existe un ejercicio listo en biblioteca');return}
        if(!r?.request_id)throw Error('El backend no devolvió request_id.');
        const out=await req('/functions/v1/generate-exercise-asset-v100',{method:'POST',body:JSON.stringify({request_id:r.request_id})});
        $('#modal').innerHTML='';toast(out?.status==='pending_review'?'Ejercicio generado · pendiente de QA':'Solicitud creada');await renderAssets();
      }catch(e){s.textContent='No se pudo crear: '+String(e?.message||e);b.disabled=false}
    };
  }

  function requestCard(r,itemMap){
    const item=itemMap.get(r.exercise_id)||{},name=requestName(r,itemMap),preview=r.generated_asset_url||item.delivery_url||item.image_path||'';
    const canGenerate=['queued','failed'].includes(r.status),canReview=r.status==='pending_review'&&r.exercise_id;
    return `<article class="card" style="border-color:${r.status==='pending_review'?'#62451f':'var(--b)'}"><div class="row"><div class="grow"><b>${esc(name)}</b><div class="muted">${esc(r.source||'system')} · ${new Date(r.created_at).toLocaleString('es-CL')}</div></div>${badge(statusLabel[r.status]||r.status,color(r.status))}</div>${r.request_reason?`<div class="muted" style="margin-top:8px">${esc(r.request_reason)}</div>`:''}${r.error_message?`<div class="muted" style="margin-top:8px;color:#ff93a1">${esc(r.error_message)}</div>`:''}${preview?`<img src="${esc(preview)}" loading="lazy" style="display:block;width:100%;max-height:360px;object-fit:contain;background:#080a0c;border:1px solid var(--b);border-radius:11px;margin-top:10px">`:''}<div class="row" style="margin-top:10px;flex-wrap:wrap">${canGenerate?`<button class="btn primary small v100Generate" data-id="${esc(r.id)}">GENERAR LÁMINA</button>`:''}${canReview?`<button class="btn good small v100Approve" data-ex="${esc(r.exercise_id)}">APROBAR</button><button class="btn small v100Reject" data-ex="${esc(r.exercise_id)}">RECHAZAR</button>`:''}</div></article>`;
  }

  async function renderAssets(){
    const root=$('#content');if(!root)return;root.innerHTML='<div class="card muted">Auditando biblioteca V100…</div>';
    try{
      const d=await center(),s=d.summary||{},items=arr(d.items),requests=arr(d.requests),map=new Map(items.map(x=>[x.exercise_id,x])),blocked=items.filter(x=>!['approved','external_verified'].includes(x.asset_status));
      root.innerHTML=`<div class="head"><div><div class="ey">V100 · EXERCISE ASSET GUARDRAIL</div><h1 class="title">Assets de ejercicios</h1><p class="sub">Toda rutina publicable debe tener una lámina verificada. Los gaps pueden generar un ejercicio/asset, pero requieren revisión humana antes de quedar activos.</p></div><div class="row"><button id="v100Refresh" class="btn">↻ ACTUALIZAR</button><button id="v100New" class="btn primary">+ NUEVO EJERCICIO</button></div></div><div class="kpis"><div class="kpi"><div class="l">Biblioteca</div><div class="n">${esc(s.total??items.length)}</div></div><div class="kpi"><div class="l">Listos</div><div class="n">${esc(s.ready??0)}</div></div><div class="kpi"><div class="l">Bloqueados</div><div class="n">${esc(s.blocked??0)}</div></div><div class="kpi"><div class="l">Solicitudes abiertas</div><div class="n">${esc(s.open_requests??0)}</div></div><div class="kpi"><div class="l">Auto-publicación</div><div class="n" style="font-size:18px">OFF</div></div></div><section><div class="row"><h2 class="grow">Cola de backfill / QA</h2><span class="muted">${requests.length} abiertas</span></div><div class="stack">${requests.length?requests.map(r=>requestCard(r,map)).join(''):'<div class="card muted">No hay solicitudes abiertas. La biblioteca está cubierta.</div>'}</div></section><section style="margin-top:20px"><div class="row"><h2 class="grow">Assets bloqueados</h2><span class="muted">${blocked.length}</span></div><div class="stack">${blocked.length?blocked.map(x=>`<div class="card"><div class="row"><div class="grow"><b>${esc(x.name)}</b><div class="muted">${esc(x.source_type)} · ${esc(statusLabel[x.asset_status]||x.asset_status)}</div></div>${badge(statusLabel[x.asset_status]||x.asset_status,color(x.asset_status))}<button class="btn small v100Backfill" data-ex="${esc(x.exercise_id)}">SOLICITAR BACKFILL</button></div></div>`).join(''):'<div class="card muted">Cero assets bloqueados.</div>'}</div></section><div class="card" style="margin-top:20px"><div class="ey">GUARDRAILS V100</div><div class="muted" style="margin-top:8px">Publicación exige asset approved/external_verified · library gap solo si no existe alternativa segura · máximo 3 gaps automáticos por generación · nuevo ejercicio inicia inactivo · generación queda pending_review · aprobación humana obligatoria · auto_publish OFF.</div></div>`;
      $('#v100Refresh').onclick=()=>renderAssets();$('#v100New').onclick=openNewExercise;
      $$('.v100Generate').forEach(b=>b.onclick=()=>generate(b.dataset.id,b));
      $$('.v100Approve').forEach(b=>b.onclick=()=>review(b.dataset.ex,'approve'));
      $$('.v100Reject').forEach(b=>b.onclick=()=>review(b.dataset.ex,'reject'));
      $$('.v100Backfill').forEach(b=>b.onclick=()=>requestBackfill(b.dataset.ex));
    }catch(e){root.innerHTML=`<div class="card" style="border-color:#64202b"><b>No se pudo cargar Assets V100</b><div class="muted">${esc(e?.message||e)}</div></div>`}
  }

  if(typeof render!=='function'||typeof setView!=='function'||typeof req!=='function'){console.error('CV Coach V100: host contract unavailable');return}
  const baseRender=render,baseSetView=setView;
  render=async function(){if(view===VIEW)return renderAssets();return baseRender()};
  setView=function(next){if(next!==VIEW)return baseSetView(next);clientDetailToken++;view=VIEW;$$('.nav button').forEach(b=>b.classList.toggle('on',b.dataset.v===VIEW));$('#topTitle').textContent='Assets V100';return render()};
  const nav=document.querySelector('.nav');if(nav&&!nav.querySelector(`[data-v="${VIEW}"]`)){const b=document.createElement('button');b.dataset.v=VIEW;b.textContent='🖼 Assets V100';const lib=nav.querySelector('[data-v="library"]');lib?lib.after(b):nav.appendChild(b);b.onclick=()=>setView(VIEW)}
  window.cvExerciseAssetsV100={render:renderAssets,version:'V100'};
  console.log(MARK);
})();
