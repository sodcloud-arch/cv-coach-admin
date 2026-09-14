from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
html=(ROOT/'index.html').read_text(encoding='utf-8')
js=(ROOT/'admin-assets'/'cv-coach-intelligence-admin-v86.js').read_text(encoding='utf-8')
sql=(ROOT/'supabase'/'migrations'/'202609140120_coach_intelligence_dashboard_v86.sql').read_text(encoding='utf-8')
checks={
  'html_marker':'<!-- cv-admin-coach-intelligence-v86 -->' in html,
  'nav':'data-v="intelligence"' in html,
  'render':"view==='intelligence'" in html and 'coachIntelligenceV86()' in html,
  'asset':'/admin-assets/cv-coach-intelligence-admin-v86.js' in html,
  'js_engine':'COACH_INTELLIGENCE_V86' in js and 'CV_ADMIN_COACH_INTELLIGENCE_V86_READY' in js,
  'js_guardrails':'Auto-publicación: OFF' in js and 'observed_only' in js,
  'js_modules':all(x in js for x in ['Necesitan atención','Bloques y deloads','Pilotos controlados','Progresiones pendientes','Alertas abiertas']),
  'sql_rpc':'get_coach_intelligence_dashboard_v86' in sql,
  'sql_pilots':'coach_intelligence_pilots' in sql and 'observed_only' in sql,
  'sql_guardrails':all(x in sql for x in ["'auto_publish',false","'auto_program_edit',false","'recommendation_only',true"]),
}
failed=[k for k,v in checks.items() if not v]
if failed: raise SystemExit('V86 contract failed: '+', '.join(failed))
print('CV_ADMIN_COACH_INTELLIGENCE_V86_OK')
