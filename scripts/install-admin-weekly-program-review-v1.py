from pathlib import Path

path=Path('index.html')
text=path.read_text()

def replace_once(old,new,label):
    global text
    count=text.count(old)
    if count!=1:
        raise SystemExit(f'{label}: expected exactly one anchor, found {count}')
    text=text.replace(old,new,1)

helper=r'''function weeklyProgramReviewReasonLabel(code){let map={AVAILABILITY_CONFLICT:'Disponibilidad menor que frecuencia programada',PAIN_SIGNAL:'Dolor relevante',LOW_SLEEP_LOW_ENERGY:'Sueño bajo + energía baja',HIGH_STRESS_LOW_ENERGY:'Estrés alto + energía baja',HIGH_SORENESS_LOW_ENERGY:'Rigidez alta + energía baja',LOW_TRAINING_ADHERENCE:'Adherencia reciente de entrenamiento baja'};return map[String(code||'')]||String(code||'Señal de revisión')}function weeklyProgramReviewStatusLabel(status){let map={pending:'Pendiente',reviewed:'Revisada',dismissed:'Descartada',cleared:'Resuelta por evidencia nueva'};return map[String(status||'')]||String(status||'—')}function weeklyProgramReviewHtml(rows){let list=Array.isArray(rows)?rows:[];if(!list.length)return '<section style="margin:18px 0"><div class="row"><h2 class="grow">Revisión semanal del programa</h2><span class="muted">Control del coach</span></div><div class="card muted">No hay revisiones semanales del programa.</div></section>';return '<section style="margin:18px 0"><div class="row"><h2 class="grow">Revisión semanal del programa</h2><span class="muted">No modifica la rutina automáticamente</span></div><div class="stack">'+list.slice(0,5).map(r=>{let priority=String(r.priority||'MEDIUM').toUpperCase(),cls=priority==='CRITICAL'?'red':priority==='HIGH'?'warn':'blue',status=String(r.status||'pending'),statusCls=status==='pending'?'warn':status==='reviewed'?'green':status==='cleared'?'blue':'blue',reasons=Array.isArray(r.reason_codes)?r.reason_codes:[],e=r.evidence&&typeof r.evidence==='object'?r.evidence:{},availability=r.available_days_next_week==null?'—':r.available_days_next_week+' / '+r.programmed_days,training=e.training_adherence_pct_7d==null?'—':Number(e.training_adherence_pct_7d).toFixed(1)+'%';return '<div class="card"><div class="row"><div class="grow"><b>'+esc(r.summary||'Revisión semanal')+'</b><div class="muted">Semana '+esc(r.week_start||'—')+' · Programa V'+esc(e.program_version??'—')+'</div></div><span class="pill '+cls+'">'+esc(priority)+'</span><span class="pill '+statusCls+'">'+esc(weeklyProgramReviewStatusLabel(status))+'</span></div><div class="metrics nutritionMetrics"><div class="metric"><span>Días disponibles / programados</span><b>'+esc(availability)+'</b></div><div class="metric"><span>Adherencia training · 7d</span><b>'+esc(training)+'</b></div><div class="metric"><span>Dolor</span><b>'+esc(e.pain_score??'—')+'</b></div><div class="metric"><span>Sueño</span><b>'+esc(e.sleep_hours_avg==null?'—':e.sleep_hours_avg+' h')+'</b></div></div>'+(reasons.length?'<div class="muted" style="margin-top:10px"><b>Motivos:</b> '+reasons.map(x=>esc(weeklyProgramReviewReasonLabel(x?.code))).join(' · ')+'</div>':'')+(r.coach_notes?'<div class="muted" style="margin-top:7px"><b>Nota coach:</b> '+esc(r.coach_notes)+'</div>':'')+(status==='pending'?'<textarea class="input weeklyProgramReviewNote" data-id="'+esc(r.id)+'" rows="2" maxlength="1000" placeholder="Nota opcional del coach…"></textarea><div class="row"><button class="btn good small weeklyProgramReviewAction" data-id="'+esc(r.id)+'" data-decision="reviewed">REVISADA</button><button class="btn small weeklyProgramReviewAction" data-id="'+esc(r.id)+'" data-decision="dismissed">DESCARTADA</button></div>':'')+'</div>'}).join('')+'</div></section>'}'''
replace_once('async function clientDetail(id){',helper+'async function clientDetail(id){','review helper')
replace_once('billingRows,weeklyCheckins]=await Promise.all([','billingRows,weeklyCheckins,weeklyProgramReviews]=await Promise.all([','review destructuring')
old_query="table('weekly_checkins','client_id=eq.'+encodeURIComponent(id)+'&select=*&order=week_start.desc&limit=8').catch(()=>[]) ])"
new_query="table('weekly_checkins','client_id=eq.'+encodeURIComponent(id)+'&select=*&order=week_start.desc&limit=8').catch(()=>[]),table('weekly_program_reviews','client_id=eq.'+encodeURIComponent(id)+'&select=*&order=week_start.desc,updated_at.desc&limit=8').catch(()=>[]) ])"
replace_once(old_query,new_query,'review query')
replace_once('${weeklyRecoveryHtml(weeklyCheckins)}${progressPhotosHtml}','${weeklyRecoveryHtml(weeklyCheckins)}${weeklyProgramReviewHtml(weeklyProgramReviews)}${progressPhotosHtml}','review placement')
action=r'''$$('.weeklyProgramReviewAction').forEach(b=>b.onclick=async()=>{let noteEl=$('.weeklyProgramReviewNote[data-id="'+b.dataset.id+'"]'),note=noteEl?.value.trim()||'';try{b.disabled=true;if(note.length>1000)throw Error('La nota no puede superar 1000 caracteres.');await req('/rest/v1/rpc/review_weekly_program_review',{method:'POST',body:JSON.stringify({p_review_id:b.dataset.id,p_decision:b.dataset.decision,p_coach_notes:note||null})});cache={};toast(b.dataset.decision==='reviewed'?'Revisión registrada. La rutina no fue modificada automáticamente.':'Revisión descartada. La rutina no fue modificada.');await clientDetail(id)}catch(e){toast('No se pudo registrar la revisión: '+e.message)}finally{b.disabled=false}});'''
replace_once("$$('.progressionAction').forEach(b=>b.onclick=async()=>{",action+"$$('.progressionAction').forEach(b=>b.onclick=async()=>{",'review actions')

required=['function weeklyProgramReviewHtml(rows)','weeklyProgramReviews]=await Promise.all','weekly_program_reviews','review_weekly_program_review','Revisión semanal del programa','No modifica la rutina automáticamente','REVISADA','DESCARTADA']
missing=[x for x in required if x not in text]
if missing:
    raise SystemExit('Missing weekly program review markers: '+', '.join(missing))
block=text[text.index('function weeklyProgramReviewReasonLabel'):text.index('async function programs(){')]
forbidden=["weekly_program_reviews',{method:'POST'","weekly_program_reviews',{method:'PATCH'","weekly_program_reviews',{method:'DELETE'","service_role","SUPABASE_SERVICE_ROLE_KEY"]
found=[x for x in forbidden if x in block]
if found:
    raise SystemExit('Unsafe weekly program review frontend implementation: '+', '.join(found))
if block.count("/rest/v1/rpc/review_weekly_program_review")!=1:
    raise SystemExit('Weekly program review decision must use exactly one approved RPC path')
path.write_text(text)
