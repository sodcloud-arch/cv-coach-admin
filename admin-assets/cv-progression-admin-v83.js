/* CV Coach V83 — Adaptive Progression Center */
(function(){
  const stateMeta={
    progressing:['PROGRESANDO','green'],
    stable:['ESTABLE','blue'],
    stagnating:['ESTANCADO','warn'],
    recovery_limited:['RECUPERACIÓN LIMITADA','warn'],
    deload_recommended:['DELOAD RECOMENDADO','red']
  };
  const actionLabel={
    increase_load:'SUBIR CARGA',
    build_reps:'CONSTRUIR REPS',
    build_time:'AUMENTAR TIEMPO',
    maintain:'MANTENER',
    review:'REVISAR',
    collect_more_data:'RECOLECTAR DATOS'
  };
  function n(v,s=''){return v==null||v===''?'—':esc(v)+s}
  function statePill(v){
    const m=stateMeta[v]||[String(v||'—').toUpperCase(),'blue'];
    return '<span class="pill '+m[1]+'">'+esc(m[0])+'</span>';
  }
  function actionPill(v){
    const cls=v==='increase_load'||v==='build_reps'||v==='build_time'?'green':v==='review'?'warn':'blue';
    return '<span class="pill '+cls+'">'+esc(actionLabel[v]||String(v||'—').toUpperCase())+'</span>';
  }
  function suggestionTarget(s){
    if(s.prescription_unit==='seconds'){
      return 'Tiempo: '+n(s.previous_duration_seconds,' s')+' → '+n(s.suggested_duration_seconds,' s');
    }
    const before=[s.previous_load!=null?s.previous_load+' kg':null,s.previous_reps!=null?s.previous_reps+' reps':null].filter(Boolean).join(' · ')||'—';
    const reps=s.suggested_rep_min!=null||s.suggested_rep_max!=null
      ?(s.suggested_rep_min??'—')+'–'+(s.suggested_rep_max??'—')+' reps':'—';
    const after=[s.suggested_load!=null?s.suggested_load+' kg':null,reps].filter(Boolean).join(' · ');
    return before+' → '+after;
  }
  function adaptationReasonLabels(rows){
    const map={
      block_age_plus_accumulated_fatigue_or_stagnation:'Bloque avanzado + fatiga/estancamiento',
      recovery_signal_requires_review:'Recuperación requiere revisión',
      repeated_non_progressing_exposures:'Exposiciones repetidas sin progreso',
      productive_progression_signals:'Señales productivas de progresión',
      insufficient_recent_sessions:'Datos recientes insuficientes',
      stable_without_deload_signal:'Estable, sin señal de deload',
      recent_pain_feedback:'Dolor reciente reportado',
      repeated_high_effort:'Esfuerzo alto repetido',
      time_ceiling_reached:'Techo de tiempo alcanzado',
      data_gaps_present:'Faltan datos de ejecución'
    };
    return (Array.isArray(rows)?rows:[]).map(x=>map[x]||x).join(' · ')||'Sin alertas adaptativas';
  }
  async function centerData(clientId=null){
    return req('/rest/v1/rpc/get_progression_center_v83',{
      method:'POST',
      body:JSON.stringify({p_actor_id:me.id,p_client_id:clientId||null})
    });
  }
  async function reviewSuggestion(s,decision,values={}){
    const result=await req('/rest/v1/rpc/review_progression_suggestion_v83',{
      method:'POST',
      body:JSON.stringify({
        p_actor_id:me.id,
        p_suggestion_id:s.id,
        p_decision:decision,
        p_suggested_load:values.load??null,
        p_suggested_rep_min:values.repMin??null,
        p_suggested_rep_max:values.repMax??null,
        p_suggested_duration_seconds:values.duration??null,
        p_note:values.note??null
      })
    });
    cache={};
    return result;
  }
  async function afterSuggestionAction(clientId,message){
    toast(message);
    if(view==='progression') await progressionCenter();
    else if(clientId) await clientDetail(clientId);
  }
  function openModify(s){
    const ev=s.evidence&&typeof s.evidence==='object'?s.evidence:{};
    const unit=s.prescription_unit||ev.prescription_unit||ev.mode;
    $('#modal').innerHTML=`<div class="modal"><div class="card">
      <div class="row"><div class="grow"><div class="ey">V83 · MODIFICACIÓN CONSERVADORA</div><h2>${esc(s.exercise_name||'Progresión')}</h2></div><button id="v83CloseModify" class="btn small">✕</button></div>
      <p class="sub">Puedes hacer la recomendación más conservadora, nunca más agresiva que el techo calculado por V83.</p>
      ${unit==='seconds'
        ?`<label>Tiempo objetivo (segundos)</label><input id="v83Duration" class="input" type="number" min="1" step="1" value="${esc(s.suggested_duration_seconds??'')}"><div class="muted">Máximo V83: ${n(ev.suggested_duration_seconds??s.suggested_duration_seconds,' s')}</div>`
        :`<div class="grid"><div><label>Carga objetivo (kg)</label><input id="v83Load" class="input" type="number" min="0" step="0.01" value="${esc(s.suggested_load??'')}"></div><div><label>Reps objetivo mín.</label><input id="v83RepMin" class="input" type="number" min="1" step="1" value="${esc(s.suggested_rep_min??'')}"><label>Reps objetivo máx.</label><input id="v83RepMax" class="input" type="number" min="1" step="1" value="${esc(s.suggested_rep_max??'')}"></div></div><div class="muted">Techo V83: ${n(ev.suggested_load,' kg')} · ${n(ev.suggested_rep_min)}–${n(ev.suggested_rep_max)} reps</div>`}
      <label style="display:block;margin-top:12px">Nota del coach</label><textarea id="v83ModifyNote" class="input" rows="3" maxlength="1000"></textarea>
      <button id="v83SaveModify" class="btn primary" style="width:100%">GUARDAR MODIFICACIÓN</button>
      <div id="v83ModifyStatus" class="status muted"></div>
    </div></div>`;
    $('#v83CloseModify').onclick=()=>$('#modal').innerHTML='';
    $('#v83SaveModify').onclick=async()=>{
      const b=$('#v83SaveModify'),out=$('#v83ModifyStatus');
      try{
        b.disabled=true;out.textContent='Validando contra el techo V83…';
        const number=(id)=>{
          const el=$(id);if(!el)return null;
          const raw=el.value.trim();if(raw==='')return null;
          const v=Number(raw);if(!Number.isFinite(v)||v<0)throw Error('Valor numérico inválido.');
          return v;
        };
        await reviewSuggestion(s,'modified',{
          load:number('#v83Load'),
          repMin:number('#v83RepMin'),
          repMax:number('#v83RepMax'),
          duration:number('#v83Duration'),
          note:$('#v83ModifyNote').value.trim()||null
        });
        $('#modal').innerHTML='';
        await afterSuggestionAction(s.client_id,'Progresión modificada dentro de límites V83.');
      }catch(e){out.textContent='No se pudo modificar: '+String(e?.message||e);b.disabled=false}
    };
  }
  function suggestionCard(s,showClient=true){
    return `<article class="card v83SuggestionCard" data-suggestion="${esc(s.id)}">
      <div class="row"><div class="grow"><b>${showClient?esc((s.client_name||'Cliente')+' · '):''}${esc(s.exercise_name||'Ejercicio')}</b><div class="muted">${esc(s.program_name||'Programa')} · ${esc(s.prescription_unit==='seconds'?'Tiempo':'Carga / reps')}</div></div>${actionPill(s.action)}</div>
      <div class="metrics nutritionMetrics">
        <div class="metric"><span>Objetivo</span><b style="font-size:13px">${esc(suggestionTarget(s))}</b></div>
        <div class="metric"><span>Confianza</span><b>${n(s.confidence,'%')}</b><div class="muted">${esc(String(s.confidence_band||'—').toUpperCase())}</div></div>
        <div class="metric"><span>Evidencia</span><b>${n(s.evidence_sessions)}</b><div class="muted">sesiones</div></div>
        <div class="metric"><span>Motor</span><b style="font-size:11px">${esc(s.engine_version||'V83')}</b></div>
      </div>
      <div class="muted" style="margin-top:9px">${esc(s.reason_text||s.reason_code||'Sin motivo persistido')}</div>
      <div class="row" style="margin-top:10px;flex-wrap:wrap">
        <button class="btn good small v83Approve" data-id="${esc(s.id)}">APROBAR</button>
        <button class="btn small v83Modify" data-id="${esc(s.id)}">MODIFICAR</button>
        <button class="btn small v83Reject" data-id="${esc(s.id)}">RECHAZAR</button>
        ${showClient?`<button class="btn small v83Client" data-client="${esc(s.client_id)}">FICHA 360</button>`:''}
      </div>
    </article>`;
  }
  function adaptationCard(a,showClient=true){
    const completion=a.average_completion_pct==null?'—':Number(a.average_completion_pct).toFixed(1)+'%';
    return `<article class="card v83AdaptationCard" data-review="${esc(a.id)}" style="${a.deload_recommended?'border-color:#64202b':''}">
      <div class="row"><div class="grow"><b>${showClient?esc((a.client_name||'Cliente')+' · '):''}${esc(a.program_name||'Programa')}</b><div class="muted">Bloque · semana ${esc(a.block_week??'—')}</div></div>${statePill(a.state)}</div>
      <div class="metrics">
        <div class="metric"><span>Sesiones recientes</span><b>${n(a.recent_sessions)}</b></div>
        <div class="metric"><span>Progreso</span><b>${n(a.progress_signals)}</b></div>
        <div class="metric"><span>Estancamiento</span><b>${n(a.stagnation_signals)}</b></div>
        <div class="metric"><span>Completitud</span><b>${esc(completion)}</b></div>
      </div>
      <div class="muted" style="margin-top:9px">${esc(adaptationReasonLabels(a.reason_codes))}</div>
      ${a.deload_recommended?'<div class="card" style="margin-top:9px;border-color:#64202b"><b>DELOAD RECOMENDADO PARA REVISIÓN</b><div class="muted">V83 no cambia la rutina: prepara una decisión para el coach.</div></div>':''}
      <div class="row" style="margin-top:10px;flex-wrap:wrap">
        ${a.status==='pending'?`<button class="btn good small v83AdaptReviewed" data-id="${esc(a.id)}">REVISADA</button><button class="btn small v83AdaptDismiss" data-id="${esc(a.id)}">DESCARTAR</button>`:''}
        ${showClient?`<button class="btn small v83Client" data-client="${esc(a.client_id)}">FICHA 360</button>`:''}
      </div>
    </article>`;
  }
  function wire(container,data,clientContext=null){
    const suggestions=new Map((data.suggestions||[]).map(x=>[x.id,x]));
    container.querySelectorAll('.v83Approve').forEach(b=>b.onclick=async()=>{
      const s=suggestions.get(b.dataset.id);if(!s)return;
      try{b.disabled=true;await reviewSuggestion(s,'approved');await afterSuggestionAction(clientContext||s.client_id,'Progresión aprobada para la próxima sesión.')}catch(e){toast('No se pudo aprobar: '+String(e?.message||e));b.disabled=false}
    });
    container.querySelectorAll('.v83Reject').forEach(b=>b.onclick=async()=>{
      const s=suggestions.get(b.dataset.id);if(!s)return;
      try{b.disabled=true;await reviewSuggestion(s,'rejected');await afterSuggestionAction(clientContext||s.client_id,'Progresión rechazada.')}catch(e){toast('No se pudo rechazar: '+String(e?.message||e));b.disabled=false}
    });
    container.querySelectorAll('.v83Modify').forEach(b=>b.onclick=()=>{const s=suggestions.get(b.dataset.id);if(s)openModify(s)});
    container.querySelectorAll('.v83Client').forEach(b=>b.onclick=()=>clientDetail(b.dataset.client));
    const reviewAdapt=async(b,decision)=>{
      try{
        b.disabled=true;
        await req('/rest/v1/rpc/review_training_adaptation_v83',{method:'POST',body:JSON.stringify({p_actor_id:me.id,p_review_id:b.dataset.id,p_decision:decision,p_note:null})});
        cache={};toast(decision==='reviewed'?'Estado adaptativo revisado.':'Recomendación adaptativa descartada.');
        if(view==='progression')await progressionCenter();else if(clientContext)await clientDetail(clientContext);
      }catch(e){toast('No se pudo actualizar: '+String(e?.message||e));b.disabled=false}
    };
    container.querySelectorAll('.v83AdaptReviewed').forEach(b=>b.onclick=()=>reviewAdapt(b,'reviewed'));
    container.querySelectorAll('.v83AdaptDismiss').forEach(b=>b.onclick=()=>reviewAdapt(b,'dismissed'));
  }
  window.progressionCenter=async function(){
    const c=$('#content');
    c.innerHTML='<div class="card muted">Cargando motor adaptativo V83…</div>';
    const data=await centerData();
    const suggestions=Array.isArray(data?.suggestions)?data.suggestions:[];
    const adaptations=Array.isArray(data?.adaptations)?data.adaptations:[];
    c.innerHTML=`<div class="head"><div><div class="ey">V83 · PROGRESIÓN ADAPTATIVA</div><h1 class="title">Centro de Progresión</h1><p class="sub">Carga, repeticiones, tiempo, estancamiento y deload. Toda decisión estructural sigue bajo control del coach.</p></div></div>
      <div class="kpis">
        <div class="kpi"><div class="l">Pendientes</div><div class="n">${esc(data?.summary?.pending_suggestions??suggestions.length)}</div></div>
        <div class="kpi"><div class="l">Clientes evaluados</div><div class="n">${esc(data?.summary?.clients_with_adaptation_state??adaptations.length)}</div></div>
        <div class="kpi"><div class="l">Deload recomendado</div><div class="n">${esc(data?.summary?.deload_recommended??adaptations.filter(x=>x.deload_recommended).length)}</div></div>
      </div>
      <input id="v83Search" class="input" style="max-width:420px" placeholder="Buscar cliente, ejercicio o programa…">
      <section><div class="row"><h2 class="grow">Estado adaptativo del bloque</h2><span class="muted">No modifica programas automáticamente</span></div><div id="v83Adaptations" class="clients"></div></section>
      <section style="margin-top:18px"><div class="row"><h2 class="grow">Progresiones pendientes</h2><span class="muted">V83 safe ceiling</span></div><div id="v83Suggestions" class="clients"></div></section>`;
    const draw=()=>{
      const q=($('#v83Search')?.value||'').toLowerCase().trim();
      const a=adaptations.filter(x=>(`${x.client_name||''} ${x.program_name||''} ${x.state||''}`).toLowerCase().includes(q));
      const s=suggestions.filter(x=>(`${x.client_name||''} ${x.exercise_name||''} ${x.program_name||''} ${x.action||''}`).toLowerCase().includes(q));
      $('#v83Adaptations').innerHTML=a.length?a.map(x=>adaptationCard(x,true)).join(''):'<div class="card muted">Sin estados adaptativos para este filtro.</div>';
      $('#v83Suggestions').innerHTML=s.length?s.map(x=>suggestionCard(x,true)).join(''):'<div class="card muted">No hay progresiones pendientes.</div>';
      wire(c,{suggestions:s,adaptations:a});
    };
    $('#v83Search').oninput=draw;draw();
  };
  async function enhanceClient(clientId){
    try{
      const data=await centerData(clientId);
      const suggestions=Array.isArray(data?.suggestions)?data.suggestions:[];
      const adaptations=Array.isArray(data?.adaptations)?data.adaptations:[];
      const headings=[...document.querySelectorAll('#content h2')];
      const progressionHeading=headings.find(h=>h.textContent.trim()==='Progresiones sugeridas');
      if(!progressionHeading)return;
      const section=document.createElement('section');
      section.id='v83ClientAdaptation';
      section.style.margin='18px 0';
      section.innerHTML='<div class="row"><h2 class="grow">Estado adaptativo V83</h2><button class="btn small" id="v83OpenCenter">CENTRO DE PROGRESIÓN</button></div>'+
        (adaptations.length?adaptations.map(x=>adaptationCard(x,false)).join(''):'<div class="card muted">Aún no hay suficiente historial para un estado adaptativo.</div>');
      progressionHeading.parentNode.insertBefore(section,progressionHeading);
      $('#v83OpenCenter').onclick=()=>setView('progression');

      const map=new Map(suggestions.map(x=>[x.id,x]));
      document.querySelectorAll('#content .progressionAction').forEach(b=>{
        const s=map.get(b.dataset.id);if(!s)return;
        b.onclick=async()=>{
          const decision=b.dataset.status==='approved'?'approved':'rejected';
          try{b.disabled=true;await reviewSuggestion(s,decision);await afterSuggestionAction(clientId,decision==='approved'?'Progresión aprobada para la próxima sesión.':'Progresión rechazada.')}catch(e){toast('No se pudo actualizar: '+String(e?.message||e));b.disabled=false}
        };
        const card=b.closest('.card');
        if(card&&!card.querySelector('.v83InlineMeta')){
          const meta=document.createElement('div');meta.className='v83InlineMeta muted';meta.style.marginTop='8px';
          meta.textContent=(actionLabel[s.action]||s.action||'V83')+' · '+(s.confidence??'—')+'% · '+(s.evidence_sessions??0)+' sesiones de evidencia'+(s.prescription_unit==='seconds'?' · objetivo '+(s.suggested_duration_seconds??'—')+' s':'');
          card.insertBefore(meta,card.querySelector('.row:last-child'));
          const row=card.querySelector('.row:last-child');
          if(row&&!row.querySelector('.v83ModifyInline')){
            const mb=document.createElement('button');mb.className='btn small v83ModifyInline';mb.textContent='Modificar';mb.onclick=()=>openModify(s);row.insertBefore(mb,row.children[1]||null);
          }
        }
      });
      wire(section,data,clientId);
    }catch(e){
      console.warn('CV V83 client enhancement unavailable',e);
    }
  }
  if(typeof clientDetail==='function'){
    const previousClientDetail=clientDetail;
    clientDetail=async function(id){
      await previousClientDetail(id);
      await enhanceClient(id);
    };
    window.clientDetail=clientDetail;
  }
  console.log('CV_ADMIN_PROGRESSION_V83_READY');
})();
