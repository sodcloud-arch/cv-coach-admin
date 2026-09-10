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
"reportOptional('plans','select=id,name')]);",
"reportOptional('weekly_checkins','client_id=eq.'+qId+'&select=*&order=week_start.desc&limit=20'),\nreportOptional('plans','select=id,name')]);",
'reports weekly source')

old_money=",money=n=>'$'+Number(n||0).toLocaleString('es-CL')+' CLP';"
new_money=",weekSrc=src('weekly_checkins'),weekly=weekSrc.rows.filter(x=>within(x,['week_start','submitted_at'])).sort((a,b)=>String(b.week_start||b.submitted_at||'').localeCompare(String(a.week_start||a.submitted_at||''))),latestWeekly=weekly[0]||null,money=n=>'$'+Number(n||0).toLocaleString('es-CL')+' CLP';"
replace_once(old_money,new_money,'reports weekly variables')

weekly_expr="latestWeekly?'<div class=\"metrics nutritionMetrics\">'+reportMetric('Check-ins del periodo',weekly.length)+reportMetric('Semana',reportDateLocal(latestWeekly.week_start)||'—')+reportMetric('Sueño promedio',latestWeekly.sleep_hours_avg==null?'—':latestWeekly.sleep_hours_avg+' h')+reportMetric('Calidad sueño',latestWeekly.sleep_quality==null?'—':latestWeekly.sleep_quality+' / 5')+reportMetric('Energía',latestWeekly.energy_level==null?'—':latestWeekly.energy_level+' / 5')+reportMetric('Estrés',latestWeekly.stress_level==null?'—':latestWeekly.stress_level+' / 5')+reportMetric('Rigidez',latestWeekly.soreness_score==null?'—':latestWeekly.soreness_score+' / 10')+reportMetric('Dolor',latestWeekly.pain_score==null?'—':latestWeekly.pain_score+' / 10')+reportMetric('Motivación',latestWeekly.motivation_level==null?'—':latestWeekly.motivation_level+' / 5')+reportMetric('Días disponibles',latestWeekly.available_days_next_week==null?'—':latestWeekly.available_days_next_week+' / 7')+reportMetric('Workouts · snapshot 7d',latestWeekly.workouts_completed_7d??'—')+reportMetric('Hábitos · snapshot 7d',latestWeekly.habit_completion_pct_7d==null?'—':Number(latestWeekly.habit_completion_pct_7d).toFixed(1)+'%')+reportMetric('Nutrición · snapshot 7d',latestWeekly.nutrition_adherence_pct_7d==null?'—':Number(latestWeekly.nutrition_adherence_pct_7d).toFixed(1)+'%')+'</div>'+(latestWeekly.pain_notes?'<div class=\"muted\" style=\"margin-top:8px\"><b>Molestia semanal:</b> '+esc(latestWeekly.pain_notes)+'</div>':'')+(latestWeekly.notes?'<div class=\"muted\" style=\"margin-top:5px\"><b>Comentario semanal:</b> '+esc(latestWeekly.notes)+'</div>':''):'<div class=\"muted\">Sin check-ins semanales dentro del periodo seleccionado.</div>'"
replace_once("let trainingBody=",f"let weeklyBody={weekly_expr},trainingBody=",'weekly report body')

replace_once(
"'Nutrición: '+(avgAdherence==null?'Sin datos':avgAdherence.toFixed(1)+'%'),'Riesgo autoritativo: '",
"'Nutrición: '+(avgAdherence==null?'Sin datos':avgAdherence.toFixed(1)+'%'),'Check-ins semanales: '+weekly.length,'Último sueño semanal: '+(latestWeekly?.sleep_hours_avg==null?'Sin datos':latestWeekly.sleep_hours_avg+' h'),'Última energía semanal: '+(latestWeekly?.energy_level==null?'Sin datos':latestWeekly.energy_level+'/5'),'Último estrés semanal: '+(latestWeekly?.stress_level==null?'Sin datos':latestWeekly.stress_level+'/5'),'Último dolor semanal: '+(latestWeekly?.pain_score==null?'Sin datos':latestWeekly.pain_score+'/10'),'Riesgo autoritativo: '",
'weekly summary lines')

replace_once(
"+'</div><div class=\"grid\">'+reportSection('Riesgo y retención',reportRiskHtml(risk),riskSrc.ok)",
"+'</div>'+reportSection('Recuperación semanal',weeklyBody,weekSrc.ok)+'<div class=\"grid\">'+reportSection('Riesgo y retención',reportRiskHtml(risk),riskSrc.ok)",
'weekly report section')

required=["reportOptional('weekly_checkins'","weekSrc=src('weekly_checkins')",'Recuperación semanal','Check-ins del periodo','Molestia semanal:','Check-ins semanales: '+"'"+'+weekly.length']
missing=[x for x in required if x not in text]
if missing: raise SystemExit('Missing weekly reports markers: '+', '.join(missing))
path.write_text(text)
