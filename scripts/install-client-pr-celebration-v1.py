from pathlib import Path

path=Path('client-portal/index.html')
text=path.read_text()

def replace_once(old,new,label):
    global text
    count=text.count(old)
    if count!=1:
        raise SystemExit(f'{label}: expected exactly one anchor, found {count}')
    text=text.replace(old,new,1)

helper=r'''function cvPersonalRecordResultHTML(result){const rows=Array.isArray(result?.personal_records)?result.personal_records:[];return rows.map(r=>{const marks=[];if(r?.load_pr===true&&r?.new_best_weight_kg!=null){let copy='Carga: '+Number(r.new_best_weight_kg).toLocaleString('es-CL',{maximumFractionDigits:2})+' kg';if(r.reps_at_new_best_weight!=null)copy+=' × '+r.reps_at_new_best_weight+' reps';if(r.previous_best_weight_kg!=null)copy+=' · anterior '+Number(r.previous_best_weight_kg).toLocaleString('es-CL',{maximumFractionDigits:2})+' kg';marks.push(copy)}if(r?.reps_pr===true&&r?.new_max_reps!=null){let copy='Repeticiones: '+r.new_max_reps;if(r.previous_max_reps!=null)copy+=' · anterior '+r.previous_max_reps;marks.push(copy)}if(!marks.length)return '';return '<div class="cvResultItem">⚡ <b>'+esc(r.exercise_name||'Ejercicio')+'</b><div class="hint" style="margin-top:4px">'+marks.map(esc).join(' · ')+'</div></div>'}).filter(Boolean).join('')}
'''
replace_once('function cvShowWorkoutResult(result){',helper+'function cvShowWorkoutResult(result){','PR result helper')

replace_once(
"  const achievementHtml=achievements.map(a=>'<div class=\"cvResultItem\">🏆 '+esc(a?.title||'Logro desbloqueado')+(a?.rarity?' · '+esc(String(a.rarity)):'')+'</div>').join('');",
"  const achievementHtml=achievements.map(a=>'<div class=\"cvResultItem\">🏆 '+esc(a?.title||'Logro desbloqueado')+(a?.rarity?' · '+esc(String(a.rarity)):'')+'</div>').join('');\n  const personalRecordHtml=cvPersonalRecordResultHTML(result);",
'PR HTML variable'
)

old="    (achievementHtml?'<div class=\"section\" style=\"margin-top:12px\"><div class=\"ey\">NUEVOS LOGROS</div><div class=\"cvResultList\">'+achievementHtml+'</div></div>':'')+\n    '<div class=\"hint\" style=\"margin-top:10px\">El análisis de progresión y riesgo continúa en segundo plano. Las recomendaciones se basarán en tus registros reales.</div><button id=\"cvWorkoutResultClose\" class=\"btn primary cvResultClose\" type=\"button\">CONTINUAR</button></div>';"
new="    (achievementHtml?'<div class=\"section\" style=\"margin-top:12px\"><div class=\"ey\">NUEVOS LOGROS</div><div class=\"cvResultList\">'+achievementHtml+'</div></div>':'')+\n    (personalRecordHtml?'<div class=\"section\" style=\"margin-top:12px\"><div class=\"ey\">NUEVOS RÉCORDS PERSONALES</div><div class=\"cvResultList\">'+personalRecordHtml+'</div><div class=\"hint\" style=\"margin-top:7px\">Solo se comparan series realmente completadas. La primera marca de un ejercicio se considera baseline.</div></div>':'')+\n    '<div class=\"hint\" style=\"margin-top:10px\">El análisis de progresión y riesgo continúa en segundo plano. Las recomendaciones se basarán en tus registros reales.</div><button id=\"cvWorkoutResultClose\" class=\"btn primary cvResultClose\" type=\"button\">CONTINUAR</button></div>';"
replace_once(old,new,'PR result section')

required=['function cvPersonalRecordResultHTML','personal_records','NUEVOS RÉCORDS PERSONALES','primera marca de un ejercicio se considera baseline','previous_best_weight_kg','new_best_weight_kg','previous_max_reps','new_max_reps']
missing=[x for x in required if x not in text]
if missing: raise SystemExit('Missing PR celebration markers: '+', '.join(missing))
path.write_text(text)
