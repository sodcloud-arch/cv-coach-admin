from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
html=(ROOT/'index.html').read_text(encoding='utf-8')
js=(ROOT/'admin-assets/cv-mesocycle-intelligence-admin-v85.js').read_text(encoding='utf-8')
sql=(ROOT/'supabase/migrations/202609140345_mesocycle_intelligence_v85.sql').read_text(encoding='utf-8')
patch=(ROOT/'scripts/upgrade_generate_ai_program_v85.py').read_text(encoding='utf-8')
checks={
 'html_marker':'cv-admin-mesocycle-intelligence-v85' in html,
 'asset':'cv-mesocycle-intelligence-admin-v85.js' in html,
 'trends_rpc':'get_client_training_trends_v85' in js,
 'pilot_rpc':'get_v85_pilot_readiness' in js,
 'charts':'svgSeries' in js and 'blockComparison' in js,
 'memory_rpc':'get_mesocycle_intelligence_v85' in sql,
 'prepare_ai_v85':"'mesocycle_intelligence'" in sql and "'cv-coach-ai-program-v85'" in sql,
 'pilot_observed':'observed_only' in sql and 'auto_publish' in sql,
 'patch_marker':'MESOCYCLE_INTELLIGENCE_V85_CONTEXT' in patch,
 'prompt_guardrail':'single_peak_is_not_progress' in patch or 'pico aislado' in patch,
}
failed=[k for k,v in checks.items() if not v]
if failed: raise SystemExit('CV V85 contract failed: '+', '.join(failed))
print('CV_ADMIN_MESOCYCLE_INTELLIGENCE_V85_OK')
