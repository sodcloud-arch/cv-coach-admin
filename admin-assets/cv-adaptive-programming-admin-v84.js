/* CV Coach V84 — Adaptive Programming OS */
(function(){
  const v83ProgressionCenter=window.progressionCenter;

  function val(v,s=''){return v==null||v===''?'—':esc(v)+s}
  function signed(v,s=''){
    if(v==null||v==='')return '—';
    const n=Number(v);if(!Number.isFinite(n))return esc(v);
    return (n>0?'+':'')+n.toFixed(Math.abs(n)%1?1:0)+s;
  }
  function safeDate(v){
    if(!v)return '—';const d=new Date(v);return Number.isNaN(d.getTime())?'—':d.toLocaleDateString('es-CL');
  }
  function pct(v){return v==null||v===''?'—':Number(v).toFixed(1)+'%'}
  function bar(value,max){
    const n=Number(value),m=Math.max(1,Number(max)||1),width=Number.isFinite(n)?Math.max(2,Math.min(100,(n/m)*100)):2;
    return '<div style="height:6px;background:#101214;border-radius:999px;overflow:hidden;margin-top:5px"><div style="height:100%;width:'+width+'%;background:currentColor;opacity:.65"></div></div>';
  }

  async function adaptiveCenter(clientId=null){
    return req('/rest/v1/rpc/get_adaptive_programming_center_v84',{
      method:'POST',body:JSON.stringify({p_actor_id:me.id,p_client_id:clientId||null})
    });
  }
  async function trends(clientId,weeks=12){
    return req('/rest/v1/rpc/get_client_training_trends_v84',{
      method:'POST',body:JSON.stringify({p_actor_id:me.id,p_client_id:clientId,p_weeks:weeks})
    });
  }

  function exerciseMetricLine(x){
    if(x.prescription_unit==='seconds'){
      return 'Tiempo medio: '+val(x.first_avg_duration_seconds,' s')+' → '+val(x.latest_avg_duration_seconds,' s')+
        ' · Pico '+val(x.peak_duration_seconds,' s');
    }
    return 'Carga: '+val(x.first_load,' kg')+' → '+val(x.latest_load,' kg')+
      ' ('+signed(x.load_delta,' kg')+') · Reps medias: '+val(x.first_avg_reps)+' → '+val(x.latest_avg_reps);
  }

  function trendExerciseCard(x){
    const loadDelta=Number(x.load_delta),cls=Number.isFinite(loadDelta)&&loadDelta>0?'green':Number.isFinite(loadDelta)&&loadDelta<0?'warn':'blue';
    return '<article class="card v84TrendExercise" data-exercise="'+esc(x.exercise_id)+'">'+
      '<div class="row"><div class="grow"><b>'+esc(x.exercise_name||'Ejercicio')+'</b><div class="muted">'+esc(x.prescription_unit==='seconds'?'TIEMPO':'CARGA / REPS')+' · '+esc(x.exposures||0)+' exposiciones</div></div><span class="pill '+cls+'">'+esc(x.prescription_unit==='seconds'?val(x.latest_avg_duration_seconds,' s'):signed(x.load_delta,' kg'))+'</span></div>'+
      '<div class="muted" style="margin-top:8px">'+esc(exerciseMetricLine(x))+'</div>'+
      '<div class="metrics nutritionMetrics" style="margin-top:8px"><div class="metric"><span>Pico volumen</span><b>'+val(x.peak_volume)+'</b></div><div class="metric"><span>RIR reciente</span><b>'+val(x.latest_avg_rir)+'</b></div></div>'+
      '<div class="muted" style="margin-top:7px">'+esc(safeDate(x.first_at))+' → '+esc(safeDate(x.last_at))+'</div></article>';
  }

  window.openTrainingTrendsV84=async function(clientId){
    $('#modal').innerHTML='<div class="modal"><div class="card"><div class="row"><div class="grow"><div class="ey">V84 · MEMORIA LONGITUDINAL</div><h2>Tendencias de entrenamiento</h2></div><button id="v84CloseTrends" class="btn small">✕</button></div><div class="muted">Cargando historial…</div></div></div>';
    $('#v84CloseTrends').onclick=()=>$('#modal').innerHTML='';
    try{
      const data=await trends(clientId,12),summary=data?.summary||{},sessions=Array.isArray(data?.sessions)?data.sessions:[],exercises=Array.isArray(data?.exercise_summary)?data.exercise_summary:[],history=Array.isArray(data?.exercise_history)?data.exercise_history:[],events=Array.isArray(data?.progression_events)?data.progression_events:[];
      const maxVolume=Math.max(1,...sessions.map(x=>Number(x.total_volume)||0));
      $('#modal').innerHTML=`<div class="modal"><div class="card" style="width:min(96vw,1180px);max-height:92vh;overflow:auto">
        <div class="row"><div class="grow"><div class="ey">V84 · MEMORIA LONGITUDINAL</div><h2 style="margin-bottom:4px">Tendencias de entrenamiento · 12 semanas</h2><div class="muted">Datos ejecutados, no estimaciones. Los picos aislados no se interpretan automáticamente como progreso.</div></div><button id="v84CloseTrends" class="btn small">✕</button></div>
        <div class="kpis">
          <div class="kpi"><div class="l">Sesiones · 28d</div><div class="n">${esc(summary.sessions_28d??0)}</div></div>
          <div class="kpi"><div class="l">Completitud · 28d</div><div class="n">${esc(pct(summary.average_completion_28d))}</div></div>
          <div class="kpi"><div class="l">Volumen · 28d</div><div class="n">${esc(summary.total_volume_28d??0)}</div></div>
          <div class="kpi"><div class="l">Esfuerzo · 28d</div><div class="n">${esc(summary.average_effort_28d??'—')}</div></div>
          <div class="kpi"><div class="l">Sesiones dolor ≥4</div><div class="n">${esc(summary.pain_sessions_28d??0)}</div></div>
        </div>
        <div class="row"><h3 class="grow">Evolución por ejercicio</h3><input id="v84TrendSearch" class="input" style="max-width:320px;margin:0" placeholder="Buscar ejercicio…"></div>
        <div id="v84ExerciseTrends" class="clients" style="margin-top:10px"></div>
        <h3>Sesiones recientes</h3>
        <div class="stack">${sessions.slice().reverse().slice(-24).map(s=>`<div class="card"><div class="row"><b class="grow">${esc(safeDate(s.date))} · ${esc(s.program_name||'Programa')}</b><span class="pill ${Number(s.pain||0)>=4?'red':Number(s.completion_pct||0)>=80?'green':'warn'}">${esc(pct(s.completion_pct))}</span></div><div class="muted">Volumen ${esc(s.total_volume??'—')} · ${esc(s.duration_minutes??'—')} min · RPE ${esc(s.effort??'—')} · Dolor ${esc(s.pain??'—')}</div>${bar(s.total_volume,maxVolume)}</div>`).join('')||'<div class="card muted">Sin sesiones ejecutadas en la ventana.</div>'}</div>
        <h3>Decisiones de progresión</h3>
        <div class="stack">${events.slice(0,20).map(e=>`<div class="card"><div class="row"><b class="grow">${esc(e.exercise_name||'Ejercicio')}</b><span class="pill ${e.status==='applied'?'green':e.status==='rejected'?'red':'blue'}">${esc(String(e.status||'—').toUpperCase())}</span></div><div class="muted">${esc(e.action||'—')} · ${esc(safeDate(e.reviewed_at||e.created_at))}${e.suggested_duration_seconds!=null?' · '+esc(e.suggested_duration_seconds)+' s':e.suggested_load!=null?' · '+esc(e.suggested_load)+' kg':''}</div></div>`).join('')||'<div class="card muted">Sin decisiones de progresión en la ventana.</div>'}</div>
        <details style="margin-top:12px"><summary class="btn small" style="display:inline-flex;align-items:center">HISTORIAL TÉCNICO (${esc(history.length)})</summary><div class="table" style="margin-top:8px"><table><thead><tr><th>Fecha</th><th>Ejercicio</th><th>Unidad</th><th>Carga</th><th>Reps</th><th>Tiempo</th><th>RIR</th><th>Volumen</th></tr></thead><tbody>${history.map(h=>`<tr><td>${esc(safeDate(h.date))}</td><td>${esc(h.exercise_name||'—')}</td><td>${esc(h.prescription_unit||'—')}</td><td>${esc(h.max_weight??'—')}</td><td>${esc(h.avg_reps??'—')}</td><td>${esc(h.avg_duration_seconds??'—')}</td><td>${esc(h.avg_rir??'—')}</td><td>${esc(h.volume??'—')}</td></tr>`).join('')}</tbody></table></div></details>
      </div></div>`;
      $('#v84CloseTrends').onclick=()=>$('#modal').innerHTML='';
      const draw=()=>{const q=($('#v84TrendSearch').value||'').toLowerCase();$('#v84ExerciseTrends').innerHTML=exercises.filter(x=>(x.exercise_name||'').toLowerCase().includes(q)).map(trendExerciseCard).join('')||'<div class="card muted">Sin ejercicios para este filtro.</div>'};
      $('#v84TrendSearch').oninput=draw;draw();
    }catch(e){
      const target=$('#modal .card');if(target)target.innerHTML='<div class="row"><div class="grow"><b>No se pudieron cargar Tendencias V84</b><div class="muted">'+esc(String(e?.message||e))+'</div></div><button id="v84CloseTrends" class="btn small">✕</button></div>';
      if($('#v84CloseTrends'))$('#v84CloseTrends').onclick=()=>$('#modal').innerHTML='';
    }
  };

  async function prepareDraft(button,plan){
    try{
      button.disabled=true;button.textContent='PREPARANDO…';
      const result=await req('/rest/v1/rpc/prepare_adaptive_program_draft_v84',{
        method:'POST',body:JSON.stringify({p_actor_id:me.id,p_review_id:plan.adaptation_review_id,p_mode:plan.recommended_mode})
      });
      cache={};
      if(!result?.program_id)throw Error('El backend no devolvió un borrador.');
      toast(result.status==='existing_draft'?'Ya existe un borrador. Abriéndolo.':'Borrador V84 preparado. El programa activo no cambió.');
      await programEditor(result.program_id);
    }catch(e){toast('No se pudo preparar V84: '+String(e?.message||e));button.disabled=false;button.textContent=plan.recommended_mode==='deload'?'PREPARAR DELOAD':'PREPARAR SIGUIENTE BLOQUE'}
  }

  async function enhanceProgressionCenterV84(){
    const data=await adaptiveCenter();
    const planning=Array.isArray(data?.planning)?data.planning:[];
    const byReview=new Map(planning.map(x=>[String(x.adaptation_review_id),x]));
    document.querySelectorAll('#v83Adaptations .v83AdaptationCard').forEach(card=>{
      const plan=byReview.get(String(card.dataset.review||''));if(!plan)return;
      let row=card.querySelector('.v84PlanningActions');
      if(!row){row=document.createElement('div');row.className='row v84PlanningActions';row.style.cssText='margin-top:10px;flex-wrap:wrap';card.appendChild(row)}
      row.innerHTML='';
      const trendsBtn=document.createElement('button');trendsBtn.className='btn small';trendsBtn.textContent='TENDENCIAS V84';trendsBtn.onclick=()=>openTrainingTrendsV84(plan.client_id);row.appendChild(trendsBtn);
      if(plan.draft?.program_id){
        const open=document.createElement('button');open.className='btn primary small';open.textContent='ABRIR BORRADOR V84';open.onclick=()=>programEditor(plan.draft.program_id);row.appendChild(open);
      }else if(plan.ready){
        const prepare=document.createElement('button');prepare.className=plan.recommended_mode==='deload'?'btn primary small':'btn good small';prepare.textContent=plan.recommended_mode==='deload'?'PREPARAR DELOAD':'PREPARAR SIGUIENTE BLOQUE';prepare.onclick=()=>prepareDraft(prepare,plan);row.appendChild(prepare);
      }
    });
    const head=document.querySelector('#content .head .ey');if(head)head.textContent='V84 · SISTEMA DE PROGRAMACIÓN ADAPTATIVA';
    const title=document.querySelector('#content .head .title');if(title)title.textContent='Centro de Progresión y Bloques';
  }

  if(typeof v83ProgressionCenter==='function'){
    window.progressionCenter=async function(){await v83ProgressionCenter();try{await enhanceProgressionCenterV84()}catch(e){console.warn('CV V84 progression enhancement unavailable',e)}};
    try{progressionCenter=window.progressionCenter}catch{}
  }
  console.log('CV_ADMIN_ADAPTIVE_PROGRAMMING_V84_READY');
})();
