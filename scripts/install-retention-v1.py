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
    "let sess=null,me=null,view='dashboard',cache={},clientDetailToken=0,reportClientId=null;",
    "let sess=null,me=null,view='dashboard',cache={},clientDetailToken=0,reportClientId=null,attentionQueueLastError=null;",
    'global attention error state'
)

replace_once(
    "async function attentionQueue(){try{let r=await req('/rest/v1/rpc/get_coach_attention_queue',{method:'POST',body:JSON.stringify({})});return Array.isArray(r)?r:Array.isArray(r?.data)?r.data:[]}catch(e){return null}}",
    "async function attentionQueue(){try{let r=await req('/rest/v1/rpc/get_coach_attention_queue',{method:'POST',body:JSON.stringify({})});attentionQueueLastError=null;return Array.isArray(r)?r:Array.isArray(r?.data)?r.data:[]}catch(e){attentionQueueLastError=e;return null}}",
    'attention queue error capture'
)

replace_once(
    '<button data-v="reports">📊 Informes</button><button data-v="library">▤ Biblioteca</button>',
    '<button data-v="reports">📊 Informes</button><button data-v="retention">🛡 Retención</button><button data-v="library">▤ Biblioteca</button>',
    'retention navigation'
)

replace_once(
    "reports:'Informes avanzados',library:'Biblioteca'",
    "reports:'Informes avanzados',retention:'Retención',library:'Biblioteca'",
    'retention title mapping'
)

replace_once(
    "if(view==='reports')await reports();if(view==='library')await library();",
    "if(view==='reports')await reports();if(view==='retention')await retention();if(view==='library')await library();",
    'retention render dispatch'
)

retention_js = r'''
function retentionMoney(value){
  let n=Number(value||0);
  return '$'+(Number.isFinite(n)?n:0).toLocaleString('es-CL')+' CLP';
}
function retentionDate(value){
  if(!value)return '—';
  let raw=String(value),d=new Date(raw);
  if(Number.isNaN(d.getTime()))return '—';
  return d.toLocaleDateString('es-CL',{timeZone:'America/Santiago'});
}
function retentionName(row){
  let name=((row?.first_name||'')+' '+(row?.last_name||'')).trim();
  return name||'Cliente sin nombre';
}
function retentionRiskPill(level){
  let value=String(level||'—').toUpperCase();
  let cls=value==='RED'?'red':value==='YELLOW'?'warn':value==='GREEN'?'green':'blue';
  return '<span class="pill '+cls+'">'+esc(value)+'</span>';
}
function retentionPriorityPill(priority){
  let value=String(priority||'NORMAL').toUpperCase();
  let cls=value==='CRITICAL'?'red':value==='HIGH'?'warn':value==='MEDIUM'?'blue':'green';
  return '<span class="pill '+cls+'">'+esc(value)+'</span>';
}
async function retentionOptional(name,query){
  try{return {name,ok:true,auth:false,rows:await table(name,query),error:null}}
  catch(error){return {name,ok:false,auth:reportAuthError(error),rows:[],error:String(error?.message||error)}}
}
async function retention(){
  let queue=await attentionQueue();
  if(queue===null){
    $('#content').innerHTML='<div class="ey">SEGUIMIENTO</div><h1 class="title">Retención</h1><div class="card" style="border-color:#64202b"><b>Cola de retención no disponible temporalmente</b><div class="muted" style="margin-top:6px">'+esc(attentionQueueLastError?.message||'No se pudo leer la cola bajo la sesión actual.')+'</div></div>';
    return;
  }
  if(!queue.length){
    $('#content').innerHTML='<div class="ey">SEGUIMIENTO</div><h1 class="title">Retención</h1><div class="card"><b>Estado saludable</b><div class="muted" style="margin-top:6px">No hay clientes activos en la cola de atención actual.</div></div>';
    return;
  }

  let commercialSources=await Promise.all([
    retentionOptional('client_subscriptions','select=id,client_id,plan_id,status,started_at,renews_at,ended_at,created_at'),
    retentionOptional('subscription_billing_records','select=id,client_id,status,amount_clp,due_at,created_at'),
    retentionOptional('plans','select=id,name')
  ]);
  let source=name=>commercialSources.find(x=>x.name===name)||{ok:false,auth:false,rows:[],error:'Fuente no disponible'};
  let subscriptionsSource=source('client_subscriptions'),billingSource=source('subscription_billing_records'),plansSource=source('plans');
  let commercialAvailable=subscriptionsSource.ok&&billingSource.ok&&plansSource.ok;
  let commercialAuthIssue=commercialSources.find(x=>x.auth);
  let statusOrder=['active','trialing','past_due','pending'];

  function commercialFor(clientId){
    if(!commercialAvailable)return {available:false};
    let rows=subscriptionsSource.rows.filter(x=>x.client_id===clientId);
    let open=rows.filter(x=>statusOrder.includes(x.status));
    let pool=(open.length?open:rows).slice().sort((a,b)=>{
      let ai=statusOrder.indexOf(a.status),bi=statusOrder.indexOf(b.status);
      ai=ai<0?99:ai;bi=bi<0?99:bi;
      if(ai!==bi)return ai-bi;
      return new Date(b.created_at||0)-new Date(a.created_at||0);
    });
    let subscription=pool[0]||null;
    let plan=plansSource.rows.find(x=>x.id===subscription?.plan_id)||null;
    let records=billingSource.rows.filter(x=>x.client_id===clientId);
    let pending=records.filter(x=>x.status==='pending').reduce((sum,x)=>sum+(Number(x.amount_clp)||0),0);
    let overdue=records.filter(x=>x.status==='overdue').reduce((sum,x)=>sum+(Number(x.amount_clp)||0),0);
    return {available:true,subscription,plan,pending,overdue};
  }

  function followupText(row,commercial){
    return [
      'Seguimiento de retención',
      'Cliente: '+retentionName(row),
      'Prioridad del motor existente: '+String(row.priority||'NORMAL').toUpperCase()+' · Attention score: '+(row.attention_score??'—'),
      'Riesgo autoritativo: '+String(row.risk_level||'—').toUpperCase()+' · Risk score: '+(row.risk_score??'—'),
      'Motivo persistido: '+(row.risk_reason||'Sin motivo persistido'),
      'Requiere coach: '+(row.requires_coach?'Sí':'No'),
      'Último entrenamiento: '+retentionDate(row.last_workout_at)+' · Días desde entrenamiento: '+(row.days_since_workout??'—'),
      'Alertas abiertas: '+(row.open_alerts??0)+' · Críticas: '+(row.critical_alerts??0)+' · Advertencias: '+(row.warning_alerts??0),
      'Progresiones pendientes: '+(row.pending_progressions??0),
      'Próxima acción persistida: '+(row.next_action||'Sin acción prioritaria'),
      'Suscripción: '+(commercial.available?(commercial.subscription?((commercial.subscription.status||'—')+' · '+(commercial.plan?.name||'Plan no disponible')):'Sin suscripción'):'No disponible'),
      'Próxima renovación: '+(commercial.available?retentionDate(commercial.subscription?.renews_at):'No disponible'),
      'Deuda pendiente: '+(commercial.available?retentionMoney(commercial.pending):'No disponible'),
      'Deuda vencida: '+(commercial.available?retentionMoney(commercial.overdue):'No disponible')
    ].join('\n');
  }

  $('#content').innerHTML='<div class="head"><div><div class="ey">SEGUIMIENTO</div><h1 class="title">Retención</h1><p class="sub">Cola operativa priorizada por el motor existente. Riesgo y prioridad no se recalculan en esta vista.</p></div></div>'+
    '<div class="kpis">'+
      '<div class="kpi"><div class="l">Clientes activos en cola</div><div class="n">'+esc(queue.length)+'</div></div>'+
      '<div class="kpi"><div class="l">RED</div><div class="n">'+esc(queue.filter(x=>String(x.risk_level||'').toUpperCase()==='RED').length)+'</div></div>'+
      '<div class="kpi"><div class="l">YELLOW</div><div class="n">'+esc(queue.filter(x=>String(x.risk_level||'').toUpperCase()==='YELLOW').length)+'</div></div>'+
      '<div class="kpi"><div class="l">Requieren coach</div><div class="n">'+esc(queue.filter(x=>x.requires_coach===true).length)+'</div></div>'+
      '<div class="kpi"><div class="l">CRITICAL / HIGH</div><div class="n">'+esc(queue.filter(x=>['CRITICAL','HIGH'].includes(String(x.priority||'').toUpperCase())).length)+'</div></div>'+
      '<div class="kpi"><div class="l">Alertas abiertas</div><div class="n">'+esc(queue.reduce((sum,x)=>sum+Number(x.open_alerts||0),0))+'</div></div>'+
    '</div>'+
    (commercialAuthIssue?'<div class="card" style="border-color:#62451f;margin-bottom:10px"><b>Señal comercial limitada por sesión/permisos</b><div class="muted">'+esc(commercialAuthIssue.error)+'</div></div>':(!commercialAvailable?'<div class="card muted" style="margin-bottom:10px">La señal comercial no está disponible temporalmente; la cola de retención sigue operativa.</div>':''))+
    '<div class="filters"><input id="retentionSearch" class="input" placeholder="Buscar cliente…"><select id="retentionPriority" class="input"><option value="">Todas las prioridades</option><option value="CRITICAL">CRITICAL</option><option value="HIGH">HIGH</option><option value="MEDIUM">MEDIUM</option><option value="NORMAL">NORMAL</option></select><select id="retentionRisk" class="input"><option value="">Todos los riesgos</option><option value="RED">RED</option><option value="YELLOW">YELLOW</option><option value="GREEN">GREEN</option></select></div><div id="retentionRows" class="clients"></div>';

  function draw(){
    let search=String($('#retentionSearch').value||'').trim().toLowerCase();
    let priority=$('#retentionPriority').value;
    let risk=$('#retentionRisk').value;
    let rows=queue.filter(row=>retentionName(row).toLowerCase().includes(search)&&(!priority||String(row.priority||'').toUpperCase()===priority)&&(!risk||String(row.risk_level||'').toUpperCase()===risk));
    $('#retentionRows').innerHTML=rows.map(row=>{
      let commercial=commercialFor(row.client_id);
      return '<article class="card retentionCard" data-id="'+esc(row.client_id)+'">'+
        '<div class="row"><div class="grow"><h3 style="margin:0">'+esc(retentionName(row))+'</h3><div class="muted">Riesgo autoritativo: '+esc(String(row.risk_level||'—').toUpperCase())+' · Risk score: '+esc(row.risk_score??'—')+'</div><div class="muted">Prioridad del motor: '+esc(String(row.priority||'NORMAL').toUpperCase())+' · Attention score: '+esc(row.attention_score??'—')+'</div></div>'+retentionRiskPill(row.risk_level)+' '+retentionPriorityPill(row.priority)+'</div>'+
        '<div class="muted" style="margin-top:10px">Motivo persistido: '+esc(row.risk_reason||'Sin motivo persistido')+'</div>'+
        '<div class="metrics"><div class="metric"><span>Requiere coach</span><b>'+esc(row.requires_coach?'Sí':'No')+'</b></div><div class="metric"><span>Alertas abiertas</span><b>'+esc(row.open_alerts??0)+'</b><div class="muted">Críticas: '+esc(row.critical_alerts??0)+' · Advertencias: '+esc(row.warning_alerts??0)+'</div></div><div class="metric"><span>Progresiones</span><b>'+esc(row.pending_progressions??0)+'</b></div><div class="metric"><span>Último entrenamiento</span><b>'+esc(retentionDate(row.last_workout_at))+'</b><div class="muted">Días: '+esc(row.days_since_workout??'—')+'</div></div></div>'+
        '<div class="card" style="margin-top:10px"><b>Próxima acción del motor</b><div class="muted" style="margin-top:5px">'+esc(row.next_action||'Sin acción prioritaria')+'</div></div>'+
        '<div class="card" style="margin-top:10px"><div class="row"><b class="grow">Comercial</b><span class="muted">Señal separada del riesgo</span></div>'+(commercial.available?'<div class="muted" style="margin-top:6px">Suscripción: '+esc(commercial.subscription?.status||'Sin suscripción')+' · Plan: '+esc(commercial.plan?.name||'—')+' · Renovación: '+esc(retentionDate(commercial.subscription?.renews_at))+'</div><div class="muted" style="margin-top:4px">Pendiente: '+esc(retentionMoney(commercial.pending))+' · Vencido: '+esc(retentionMoney(commercial.overdue))+'</div>':'<div class="muted" style="margin-top:6px">Comercial no disponible.</div>')+'</div>'+
        '<div class="row" style="margin-top:10px;flex-wrap:wrap"><button class="btn small retentionDetail" data-id="'+esc(row.client_id)+'">FICHA 360</button><button class="btn small retentionReport" data-id="'+esc(row.client_id)+'">VER INFORME</button><button class="btn small retentionCopy" data-id="'+esc(row.client_id)+'">COPIAR SEGUIMIENTO</button></div><div class="status muted retentionCopyStatus"></div></article>';
    }).join('')||'<div class="card muted">No hay clientes para los filtros seleccionados.</div>';

    $$('.retentionDetail').forEach(button=>button.onclick=()=>clientDetail(button.dataset.id));
    $$('.retentionReport').forEach(button=>button.onclick=()=>{reportClientId=button.dataset.id;setView('reports')});
    $$('.retentionCopy').forEach(button=>button.onclick=async()=>{
      let row=queue.find(x=>x.client_id===button.dataset.id);
      let card=button.closest('.retentionCard'),out=card?.querySelector('.retentionCopyStatus');
      try{
        if(!row)throw Error('El cliente ya no está disponible en la cola.');
        if(!navigator.clipboard||typeof navigator.clipboard.writeText!=='function')throw Error('El portapapeles no está disponible.');
        await navigator.clipboard.writeText(followupText(row,commercialFor(row.client_id)));
        if(out)out.textContent='Seguimiento copiado correctamente.';
      }catch(error){if(out)out.textContent='No se pudo copiar el seguimiento: '+String(error?.message||error)}
    });
  }

  $('#retentionSearch').oninput=draw;
  $('#retentionPriority').onchange=draw;
  $('#retentionRisk').onchange=draw;
  draw();
}
'''

replace_once('function subscriptionBlockHtml(rows,plans)', retention_js + '\nfunction subscriptionBlockHtml(rows,plans)', 'retention implementation')

required = [
    'data-v="retention"',
    "retention:'Retención'",
    "if(view==='retention')await retention();",
    'async function retention()',
    'attentionQueueLastError',
    'COPIAR SEGUIMIENTO',
    'Riesgo autoritativo',
    'Señal separada del riesgo'
]
missing = [item for item in required if item not in text]
if missing:
    raise SystemExit('Missing retention markers: ' + ', '.join(missing))

path.write_text(text)
