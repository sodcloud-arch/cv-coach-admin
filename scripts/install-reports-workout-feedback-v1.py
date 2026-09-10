from pathlib import Path

path=Path('index.html')
text=path.read_text()

def replace_once(old,new,label):
    global text
    count=text.count(old)
    if count!=1:
        raise SystemExit(f'{label}: expected exactly one anchor, found {count}')
    text=text.replace(old,new,1)

replace_once(
"reportOptional('workout_sessions','client_id=eq.'+qId+'&select=id,status,started_at,finished_at,completion_pct,total_volume&order=finished_at.desc.nullslast&limit=200')",
"reportOptional('workout_sessions','client_id=eq.'+qId+'&select=id,status,started_at,finished_at,completion_pct,total_volume,client_effort,fatigue_score,pain_score,pain_notes,session_notes&order=finished_at.desc.nullslast&limit=200')",
'report workout select'
)

replace_once(
"workoutSrc=src('workout_sessions'),workouts=workoutSrc.rows.filter(x=>x.status==='completed'&&within(x,['finished_at','started_at'])),completion=",
"workoutSrc=src('workout_sessions'),workouts=workoutSrc.rows.filter(x=>x.status==='completed'&&within(x,['finished_at','started_at'])),feedbackSessions=workoutSrc.rows.filter(x=>['completed','partial','abandoned'].includes(x.status)&&within(x,['finished_at','started_at'])&&[x.client_effort,x.fatigue_score,x.pain_score,x.session_notes,x.pain_notes].some(v=>v!=null&&v!=='')),effortFeedback=feedbackSessions.map(x=>reportNum(x.client_effort)).filter(x=>x!=null),fatigueFeedback=feedbackSessions.map(x=>reportNum(x.fatigue_score)).filter(x=>x!=null),painFeedback=feedbackSessions.map(x=>reportNum(x.pain_score)).filter(x=>x!=null),lastFeedback=feedbackSessions[0]||null,completion=",
'feedback aggregates'
)

anchor="reportMetric('Volumen acumulado',totalVolume==null?'—':totalVolume.toFixed(1))+'</div>',cvBody="
replacement="reportMetric('Volumen acumulado',totalVolume==null?'—':totalVolume.toFixed(1))+'</div><div style=\"margin-top:14px\"><b>Feedback post-entrenamiento</b><div class=\"metrics nutritionMetrics\">'+reportMetric('Sesiones con feedback',feedbackSessions.length||'—')+reportMetric('RPE promedio',effortFeedback.length?(effortFeedback.reduce((a,b)=>a+b,0)/effortFeedback.length).toFixed(1):'—')+reportMetric('Fatiga promedio',fatigueFeedback.length?(fatigueFeedback.reduce((a,b)=>a+b,0)/fatigueFeedback.length).toFixed(1):'—')+reportMetric('Dolor máximo',painFeedback.length?Math.max(...painFeedback):'—')+'</div>'+(lastFeedback?.pain_notes?'<div class=\"muted\" style=\"margin-top:8px\"><b>Última molestia:</b> '+esc(lastFeedback.pain_notes)+'</div>':'')+(lastFeedback?.session_notes?'<div class=\"muted\" style=\"margin-top:5px\"><b>Último comentario:</b> '+esc(lastFeedback.session_notes)+'</div>':'')+'</div>',cvBody="
replace_once(anchor,replacement,'training feedback block')

replace_once(
"'Completion promedio: '+(avgCompletion==null?'Sin datos':avgCompletion.toFixed(1)+'%'),'CV12 score actual: '",
"'Completion promedio: '+(avgCompletion==null?'Sin datos':avgCompletion.toFixed(1)+'%'),'Sesiones con feedback: '+feedbackSessions.length,'RPE promedio: '+(effortFeedback.length?(effortFeedback.reduce((a,b)=>a+b,0)/effortFeedback.length).toFixed(1):'Sin datos'),'Fatiga promedio: '+(fatigueFeedback.length?(fatigueFeedback.reduce((a,b)=>a+b,0)/fatigueFeedback.length).toFixed(1):'Sin datos'),'Dolor máximo: '+(painFeedback.length?Math.max(...painFeedback):'Sin datos'),'CV12 score actual: '",
'report summary feedback lines'
)

required=['client_effort,fatigue_score,pain_score,pain_notes,session_notes','feedbackSessions=','Feedback post-entrenamiento','RPE promedio','Fatiga promedio','Dolor máximo','esc(lastFeedback.pain_notes)','esc(lastFeedback.session_notes)']
missing=[x for x in required if x not in text]
if missing: raise SystemExit('Missing report feedback markers: '+', '.join(missing))
path.write_text(text)
