from pathlib import Path

path=Path('index.html')
text=path.read_text()

def replace_once(old,new,label):
    global text
    count=text.count(old)
    if count!=1:
        raise SystemExit(f'{label}: expected exactly one anchor, found {count}')
    text=text.replace(old,new,1)

helper=r'''function workoutFeedbackPill(label,value,kind){if(value==null||value==='')return '<span class="pill blue">'+esc(label)+': —</span>';let n=Number(value),cls='blue';if(kind==='pain')cls=n>=7?'red':n>=4?'warn':n===0?'green':'blue';else if(kind==='fatigue')cls=n>=8?'warn':n<=4?'green':'blue';else if(kind==='effort')cls=n>=9?'warn':n<=7?'green':'blue';return '<span class="pill '+cls+'">'+esc(label)+': '+esc(Number.isFinite(n)?n:value)+'</span>'}
function workoutSessionFeedbackHtml(x){let title=x.status==='completed'?'✓ Entrenamiento completado':x.status==='partial'?'Sesión parcial':x.status==='abandoned'?'Sesión cerrada':'Sesión '+esc(x.status),date=x.started_at?new Date(x.started_at).toLocaleDateString('es-CL'):'—',hasFeedback=[x.client_effort,x.fatigue_score,x.pain_score,x.session_notes,x.pain_notes].some(v=>v!=null&&v!=='');let feedback=hasFeedback?'<div class="row" style="margin-top:9px;flex-wrap:wrap">'+workoutFeedbackPill('RPE',x.client_effort,'effort')+workoutFeedbackPill('Fatiga',x.fatigue_score,'fatigue')+workoutFeedbackPill('Dolor',x.pain_score,'pain')+'</div>':'<div class="muted" style="margin-top:8px">Sin feedback post-entrenamiento.</div>';let notes=x.session_notes?'<div class="muted" style="margin-top:7px"><b>Comentario:</b> '+esc(x.session_notes)+'</div>':'',pain=x.pain_notes?'<div class="muted" style="margin-top:5px"><b>Molestia:</b> '+esc(x.pain_notes)+'</div>':'';return '<div class="card"><b>'+title+'</b><div class="muted">'+esc(date)+' · '+esc(x.completion_pct??0)+'%</div>'+feedback+pain+notes+'</div>'}
'''
replace_once('async function clientDetail(id){',helper+'async function clientDetail(id){','workout feedback helper insertion')
old="<h2>Sesiones</h2>${ws.map(x=>`<div class=\"card\"><b>${x.status==='completed'?'✓ Entrenamiento completado':'Sesión '+esc(x.status)}</b><div class=\"muted\">${x.started_at?new Date(x.started_at).toLocaleDateString('es-CL'):''} · ${x.completion_pct??0}%</div></div>`).join('')||'<div class=\"card muted\">Sin sesiones.</div>'}"
new="<h2>Sesiones</h2>${ws.map(workoutSessionFeedbackHtml).join('')||'<div class=\"card muted\">Sin sesiones.</div>'}"
replace_once(old,new,'Ficha 360 sessions renderer')
required=['function workoutSessionFeedbackHtml','RPE','Fatiga','Dolor','Sin feedback post-entrenamiento.','ws.map(workoutSessionFeedbackHtml)']
missing=[x for x in required if x not in text]
if missing: raise SystemExit('Missing workout feedback admin markers: '+', '.join(missing))
path.write_text(text)
