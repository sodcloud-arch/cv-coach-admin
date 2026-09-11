from pathlib import Path
import subprocess
root=Path(__file__).resolve().parents[1]
html=root/'index.html';js=root/'admin-assets'/'cv-rank-admin-v62.js';css=root/'admin-assets'/'cv-rank-admin-v62.css';sql=root/'supabase'/'migrations'/'202609111830_cv_rank_challenges_admin_v62.sql'
for p in [html,js,css,sql]:
    if not p.exists(): raise SystemExit(f'Admin V62 missing: {p}')
h=html.read_text(encoding='utf-8');j=js.read_text(encoding='utf-8');s=sql.read_text(encoding='utf-8')
for x in ['cv-admin-rank-v62','data-v="ranking"','Ranking y competencias',"view==='ranking'",'/admin-assets/cv-rank-admin-v62.js','/admin-assets/cv-rank-admin-v62.css']:
    if x not in h: raise SystemExit(f'Admin V62 HTML contract missing: {x}')
for x in ['get_coach_rank_dashboard_v61','get_coach_challenges_v62','get_coach_seasons_v62','create_cv_challenge_v62','set_cv_challenge_status_v62','set_cv_challenge_winner_v62','create_cv_season_v62','set_cv_season_status_v62','BRONCE','PLATA','ORO','PLATINO','DIAMANTE','LEYENDA']:
    if x not in j: raise SystemExit(f'Admin V62 JS contract missing: {x}')
for x in ['cv_challenge_progress_v62','refresh_cv_challenge_v62','create_cv_challenge_v62','set_cv_challenge_status_v62','set_cv_challenge_winner_v62','get_coach_challenges_v62','create_cv_season_v62','set_cv_season_status_v62','get_coach_seasons_v62']:
    if x not in s: raise SystemExit(f'Admin V62 SQL contract missing: {x}')
check=subprocess.run(['node','--check',str(js)],capture_output=True,text=True)
if check.returncode: raise SystemExit('Admin V62 JS syntax failed:\n'+check.stderr)
print('CV_RANK_ADMIN_V62_OK')
