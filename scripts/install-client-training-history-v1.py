from pathlib import Path

path=Path('client-portal/index.html')
text=path.read_text()

def replace_once(old,new,label):
    global text
    count=text.count(old)
    if count!=1:
        raise SystemExit(f'{label}: expected exactly one anchor, found {count}')
    text=text.replace(old,new,1)

css=r'''<style id="cv-training-history-v1-css">
.cvHistorySummary{display:grid;grid-template-columns:repeat(2,1fr);gap:8px;margin:12px 0}.cvHistoryMetric{border:1px solid #27333a;border-radius:13px;background:linear-gradient(155deg,#0d1418,#070b0d);padding:12px}.cvHistoryMetric small{display:block;font-size:8px;color:#909ba2;text-transform:uppercase;letter-spacing:.08em}.cvHistoryMetric b{display:block;margin-top:5px;font:800 25px 'Barlow Condensed';color:#fff}.cvHistoryList,.cvRecordGrid{display:grid;gap:9px}.cvHistorySession{padding:13px}.cvHistorySession .meta{font-size:9px;color:#8f9aa1;margin-top:4px}.cvHistoryFeedback{display:flex;gap:5px;flex-wrap:wrap;margin-top:8px}.cvHistoryChip{display:inline-flex;border:1px solid #33414a;border-radius:999px;padding:4px 7px;font-size:8px;font-weight:800;color:#c4cdd2}.cvHistoryChip.good{border-color:#31503e;color:#70eaaa}.cvHistoryChip.warn{border-color:#6c552b;color:#ffd38a}.cvHistoryChip.red{border-color:#6e2f38;color:#ff9aa5}.cvRecordCard{padding:13px}.cvRecordCard h3{font-size:21px}.cvRecordValues{display:grid;grid-template-columns:repeat(2,1fr);gap:7px;margin-top:9px}.cvRecordValue{background:#060b0e;border:1px solid #243038;border-radius:10px;padding:9px}.cvRecordValue small{display:block;font-size:7px;color:#8f9ba2;text-transform:uppercase}.cvRecordValue b{display:block;margin-top:4px;font:800 20px 'Barlow Condensed'}.cvHistoryUnavailable{border-color:#5d4828;color:#d9bd88}.cvProgressDivider{height:1px;background:#202a30;margin:16px 0}
@media(min-width:700px){.cvHistorySummary{grid-template-columns:repeat(4,1fr)}.cvRecordGrid{grid-template-columns:repeat(2,1fr)}}
</style>'''
replace_once('</head>',css+'\n</head>','history css')

replace_once(
"sessions:[]\n};",
"sessions:[],trainingHistory:{summary:{window_days:30,terminal_sessions:0,completed_sessions:0,partial_sessions:0,abandoned_sessions:0,total_volume:0,avg_completion:null,last_workout_at:null},sessions:[],records:[]}\n};",
'demo training history'
)

replace_once(
"const [p,cp,cv,pr,hab,mis,nt,sessions]=await Promise.all([",
"const [p,cp,cv,pr,hab,mis,nt,sessions,history]=await Promise.all([",
'loadReal destructuring'
)
replace_once(
"sb.from('workout_sessions').select('*').eq('client_id',id).order('started_at',{ascending:false}).limit(10)\n ]);",
"sb.from('workout_sessions').select('*').eq('client_id',id).order('started_at',{ascending:false}).limit(10),\n  sb.rpc('get_client_training_history',{p_limit:20})\n ]);",
'history rpc load'
)
replace_once(
"data={profile:p.data,cp:cp.data,cv:cv.data,program,days,exercises,habits:(hab.data||[]).map(h=>({...h,name:h.habit_definitions?.name,unit:h.habit_definitions?.unit,input_type:h.habit_definitions?.input_type,target:h.target_value??h.frequency_target})),missions:mis.data||[],nutrition:nt.data,sessions:sessions.data||[]};",
"data={profile:p.data,cp:cp.data,cv:cv.data,program,days,exercises,habits:(hab.data||[]).map(h=>({...h,name:h.habit_definitions?.name,unit:h.habit_definitions?.unit,input_type:h.habit_definitions?.input_type,target:h.target_value??h.frequency_target})),missions:mis.data||[],nutrition:nt.data,sessions:sessions.data||[],trainingHistory:history.error?{error:'Historial no disponible temporalmente.',summary:{},sessions:[],records:[]}:(history.data||{summary:{},sessions:[],records:[]})};",
'history data assignment'
)

start=text.find('function progress(){return `')
end=text.find('\nasync function loadProgressPhotos()',start)
if start<0 or end<0:
    raise SystemExit('progress function boundaries not found')
new_progress=r'''function cvTrainingHistory(){const h=data?.trainingHistory||{};return {error:h.error||'',summary:h.summary||{},sessions:Array.isArray(h.sessions)?h.sessions:[],records:Array.isArray(h.records)?h.records:[]}}
function cvTrainingNum(value){const n=Number(value);return Number.isFinite(n)?n:null}
function cvTrainingDate(value){if(!value)return '—';const d=new Date(String(value));return Number.isNaN(d.getTime())?'—':d.toLocaleDateString('es-CL',{timeZone:'America/Santiago'})}
function cvTrainingStatus(value){const s=String(value||'');return s==='completed'?{label:'COMPLETADO',cls:'good'}:s==='partial'?{label:'PARCIAL',cls:'warn'}:s==='abandoned'?{label:'CERRADO',cls:'red'}:{label:s.toUpperCase()||'—',cls:''}}
function cvHistoryChip(label,value,kind=''){if(value==null||value==='')return '';const n=Number(value);let cls='';if(kind==='pain')cls=n>=7?'red':n>=4?'warn':n===0?'good':'';else if(kind==='high')cls=n>=8?'warn':n<=6?'good':'';return '<span class="cvHistoryChip '+cls+'">'+esc(label)+': '+esc(value)+'</span>'}
function cvTrainingSessionCard(s){const meta=cvTrainingStatus(s.status),completion=cvTrainingNum(s.completion_pct),volume=cvTrainingNum(s.total_volume),minutes=cvTrainingNum(s.duration_seconds);return '<article class="card cvHistorySession"><div class="row"><div class="grow"><b>'+esc(s.day_name||s.program_name||'Entrenamiento')+'</b><div class="meta">'+esc(cvTrainingDate(s.finished_at||s.started_at))+(s.day_number!=null?' · Día '+esc(s.day_number):'')+'</div></div><span class="cvHistoryChip '+meta.cls+'">'+esc(meta.label)+'</span></div><div class="cvHistoryFeedback"><span class="cvHistoryChip">Finalización: '+esc(completion==null?'—':completion.toFixed(completion%1?1:0)+'%')+'</span>'+(volume==null?'':'<span class="cvHistoryChip">Volumen: '+esc(Math.round(volume).toLocaleString('es-CL'))+' kg·reps</span>')+(minutes==null?'':'<span class="cvHistoryChip">Duración: '+esc(Math.max(0,Math.round(minutes/60)))+' min</span>')+cvHistoryChip('RPE',s.client_effort,'high')+cvHistoryChip('Fatiga',s.fatigue_score,'high')+cvHistoryChip('Dolor',s.pain_score,'pain')+'</div>'+(s.pain_notes?'<div class="hint" style="margin-top:8px">Molestia: '+esc(s.pain_notes)+'</div>':'')+(s.session_notes?'<div class="hint" style="margin-top:5px">Comentario: '+esc(s.session_notes)+'</div>':'')+'</article>'}
function cvTrainingRecordCard(r){const weight=cvTrainingNum(r.best_weight_kg),bestReps=cvTrainingNum(r.reps_at_best_weight),maxReps=cvTrainingNum(r.max_reps);return '<article class="card cvRecordCard"><h3>'+esc(r.exercise_name||'Ejercicio')+'</h3><div class="meta hint">Última ejecución: '+esc(cvTrainingDate(r.last_performed_at))+'</div><div class="cvRecordValues"><div class="cvRecordValue"><small>Mejor carga real</small><b>'+(weight==null?'—':esc(weight.toLocaleString('es-CL',{maximumFractionDigits:2}))+' kg')+'</b><div class="hint">'+(weight==null?'Sin carga externa registrada':esc(bestReps??'—')+' reps · '+esc(cvTrainingDate(r.best_weight_at)))+'</div></div><div class="cvRecordValue"><small>Máximo de reps</small><b>'+(maxReps==null?'—':esc(maxReps))+'</b><div class="hint">Series completadas: '+esc(r.completed_sets??0)+'</div></div></div></article>'}
function progress(){const h=cvTrainingHistory(),s=h.summary||{},volume=cvTrainingNum(s.total_volume),avg=cvTrainingNum(s.avg_completion);return `<div class="ey">SEGUIMIENTO</div><h1 style="font-size:39px;margin:5px 0">TU PROGRESO</h1><div class="sub">Historial real de entrenamiento, marcas registradas, logros y progreso visual.</div>${h.error?`<section class="section"><div class="card cvHistoryUnavailable">${esc(h.error)}</div></section>`:`<div class="cvHistorySummary"><div class="cvHistoryMetric"><small>Sesiones · 30 días</small><b>${esc(s.terminal_sessions??0)}</b></div><div class="cvHistoryMetric"><small>Completadas</small><b>${esc(s.completed_sessions??0)}</b></div><div class="cvHistoryMetric"><small>Completion promedio</small><b>${avg==null?'—':esc(avg.toFixed(1))+'%'}</b></div><div class="cvHistoryMetric"><small>Volumen · 30 días</small><b>${volume==null?'—':esc(Math.round(volume).toLocaleString('es-CL'))}</b><div class="hint">kg·reps</div></div></div><section class="section"><div class="sectionHead"><h2>HISTORIAL DE ENTRENAMIENTOS</h2></div><div class="cvHistoryList">${h.sessions.length?h.sessions.slice(0,10).map(cvTrainingSessionCard).join(''):'<div class="card empty">Todavía no tienes sesiones cerradas.</div>'}</div></section><section class="section"><div class="sectionHead"><h2>RÉCORDS PERSONALES</h2></div><div class="hint" style="margin-bottom:9px">Solo se muestran marcas de series que realmente registraste como completadas. No se estima 1RM.</div><div class="cvRecordGrid">${h.records.length?h.records.map(cvTrainingRecordCard).join(''):'<div class="card empty">Completa series para comenzar a construir tus marcas.</div>'}</div></section>`}<div class="cvProgressDivider"></div><section class="section"><div class="card"><div class="ey">CENTRO CV12</div><h2>LOGROS</h2><div class="hint" style="margin:6px 0 12px">Revisa tus desbloqueos y los próximos hitos de tu proceso.</div><button class="btn primary" type="button" onclick="nav('achievements')">VER LOGROS</button></div></section><section class="section"><div class="sectionHead"><h2>PROGRESO VISUAL</h2></div><div class="card"><form id="progressPhotoForm" class="progressPhotoForm" onsubmit="uploadProgressPhoto(event)"><label for="progressPhotoType">Tipo de foto</label><select id="progressPhotoType" class="input" required><option value="front">Frontal</option><option value="side">Lateral</option><option value="back">Espalda</option><option value="other">Otra</option></select><label for="progressPhotoDate">Fecha de la foto</label><input id="progressPhotoDate" class="input" type="date" max="${today()}" required><label for="progressPhotoFile">Imagen JPEG, PNG o WebP · máximo 10 MB</label><input id="progressPhotoFile" class="input" type="file" accept="image/jpeg,image/png,image/webp" required><label class="progressVisibility"><input id="progressPhotoVisible" type="checkbox" checked> <span>Visible para tu coach. Esta opción está activada por defecto, pero puedes desmarcarla si no quieres compartir esta foto.</span></label><button id="progressPhotoSubmit" class="btn primary" type="submit">SUBIR FOTO</button><div id="progressPhotoStatus" class="progressPhotoStatus" role="status"></div></form></div></section><section class="section"><div class="sectionHead"><h2>TUS FOTOS</h2></div><div id="progressPhotoGallery" class="card"><div class="empty">Cargando tus fotos…</div></div></section>`}
'''
text=text[:start]+new_progress+text[end:]

required=['get_client_training_history','trainingHistory:history.error','function cvTrainingSessionCard','function cvTrainingRecordCard','HISTORIAL DE ENTRENAMIENTOS','RÉCORDS PERSONALES','No se estima 1RM','kg·reps','PROGRESO VISUAL']
missing=[x for x in required if x not in text]
if missing: raise SystemExit('Missing training history markers: '+', '.join(missing))
path.write_text(text)
