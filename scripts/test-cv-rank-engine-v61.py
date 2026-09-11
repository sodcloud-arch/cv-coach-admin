from pathlib import Path
import subprocess
root=Path(__file__).resolve().parents[1]
html=root/'client-portal'/'stable'/'index.html'
js=root/'client-portal'/'assets'/'cv-rank-v61.js'
css=root/'client-portal'/'assets'/'cv-rank-v61.css'
migration=root/'supabase'/'migrations'/'20260911175937_cv_rank_competitive_engine_v61.sql'
for p in [html,js,css,migration]:
    if not p.exists(): raise SystemExit(f'V61 missing file: {p}')
h=html.read_text(encoding='utf-8');j=js.read_text(encoding='utf-8');s=migration.read_text(encoding='utf-8')
for x in ['cv-rank-engine-v61: tutorial-empty + 5-level leagues + legend + global-ranking + challenges','./assets/cv-rank-v61.css','./assets/cv-rank-v61.js']:
    if x not in h: raise SystemExit(f'V61 HTML contract missing: {x}')
for x in ['get_client_rank_dashboard_v61','get_cv_ranking_v61','get_client_challenges_v61','ack_rank_tutorial_v61','AÚN <b>SIN RANGO</b>','BRONCE','PLATA','ORO','PLATINO','DIAMANTE','LEYENDA','cv-rank-bronze-v61.webp','cv-rank-legend-v61.webp']:
    if x not in j: raise SystemExit(f'V61 JS contract missing: {x}')
for forbidden in ['cv-rank-system-v60-js','cv-rank-system-v60-css','MAESTRO','GRAN MAESTRO']:
    if forbidden in h or forbidden in j: raise SystemExit(f'Retired rank contract active: {forbidden}')
for name in ['bronze','silver','gold','platinum','diamond','legend']:
    p=root/'client-portal'/'assets'/'ranks'/f'cv-rank-{name}-v61.webp'
    if not p.exists() or p.stat().st_size<1000: raise SystemExit(f'Badge missing: {p}')
for x in ['client_competitive_rank_v61','cv_rank_rules_v61','cv_rank_level_thresholds_v61','cv_rank_weekly_snapshots_v61','cv_rank_rating_ledger_v61','cv_rank_transitions_v61','cv_seasons_v61','cv_challenges_v61','get_client_rank_dashboard_v61','get_cv_ranking_v61','get_client_challenges_v61','process_due_rank_weeks_v61']:
    if x not in s: raise SystemExit(f'V61 backend contract missing: {x}')
compact=s.replace(' ','').replace('\n','')
for x in ["'bronze','BRONCE',1,1,5","'silver','PLATA',2,6,10","'gold','ORO',3,11,15","'platinum','PLATINO',4,16,20","'diamond','DIAMANTE',5,21,25","'legend','LEYENDA',6,26,26"]:
    if x not in compact: raise SystemExit(f'V61 league range missing: {x}')
check=subprocess.run(['node','--check',str(js)],capture_output=True,text=True)
if check.returncode: raise SystemExit('V61 JS syntax failed:\n'+check.stderr)
for forbidden in ["from('set_logs').update",'cvSetToggleLocksV48=','cvPersistSetLogV51=']:
    if forbidden in j: raise SystemExit(f'V61 illegally owns workout persistence: {forbidden}')
print('CV_RANK_ENGINE_V61_OK')
