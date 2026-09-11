from pathlib import Path
import re
import subprocess
import tempfile

html_path = Path('client-portal/stable/index.html')
migration_path = Path('supabase/migrations/202609111650_cv_rank_system_v60.sql')
if not html_path.exists():
    raise SystemExit('V60 stable client artifact missing; build before rank guard')
if not migration_path.exists():
    raise SystemExit('V60 rank migration missing')

html = html_path.read_text(encoding='utf-8')
sql = migration_path.read_text(encoding='utf-8')

required_html = [
    'cv-rank-system-v60: bronze-to-legend HUD + profile + progression feedback',
    'cv-rank-system-v60-css',
    'cv-rank-system-v60-js',
    "rank_up:'Nuevo rango'",
    'get_client_rank_state_backend',
    'CV RANK SYSTEM',
    'VER MI EVOLUCIÓN',
    'cvRankShieldV60',
    'cvRankProfileV60',
    'cvWorkoutRankChipV60',
    'RANK UP',
    'LEVEL UP',
    "window.CVRankV60={version:'v60'",
]
for item in required_html:
    if item not in html:
        raise SystemExit(f'V60 client contract missing: {item}')

for rank in ['BRONCE','PLATA','ORO','DIAMANTE','MAESTRO','GRAN MAESTRO','LEYENDA']:
    if rank not in html:
        raise SystemExit(f'V60 client rank missing: {rank}')
    if rank not in sql:
        raise SystemExit(f'V60 backend rank missing: {rank}')

required_sql = [
    'client_rank_history',
    'track_cv_rank_from_level_history',
    'get_client_rank_state_backend',
    "'bronze'",
    "'silver'",
    "'gold'",
    "'diamond'",
    "'master'",
    "'grandmaster'",
    "'legend'",
    '(41,21860)',
    '(49,32420)',
    "select 50,c.id,33920,'LEYENDA'",
    "'rank_up'",
]
for item in required_sql:
    if item not in sql:
        raise SystemExit(f'V60 backend contract missing: {item}')

# Existing XP curve must not be rewritten by V60; 41-50 are additive only.
if 'update public.cv_levels l set xp_required_total' in sql.lower():
    raise SystemExit('V60 must not rewrite existing XP thresholds')

# Rank history is monotonic and client-readable only through RLS.
for item in [
    'unique(client_id,class_id)',
    'alter table public.client_rank_history enable row level security',
    'private.can_view_client(client_rank_history.client_id)',
]:
    if item not in sql:
        raise SystemExit(f'V60 rank history safety contract missing: {item}')

# Backend projection must expose the fields used by the HUD/profile.
for field in [
    "'current_level'", "'total_xp'", "'rank'", "'next_rank'",
    "'xp_to_next_level'", "'level_progress_pct'", "'xp_to_next_rank'",
    "'rank_progress_pct'", "'pillar_xp'"
]:
    if field not in sql:
        raise SystemExit(f'V60 rank-state field missing: {field}')

# Syntax-check the exact injected V60 browser script.
match = re.search(r'<script id="cv-rank-system-v60-js">(.*?)</script>', html, flags=re.S)
if not match:
    raise SystemExit('V60 browser script extraction failed')
with tempfile.NamedTemporaryFile('w', suffix='.js', encoding='utf-8', delete=False) as tmp:
    tmp.write(match.group(1))
    js_path = tmp.name
check = subprocess.run(['node', '--check', js_path], text=True, capture_output=True)
Path(js_path).unlink(missing_ok=True)
if check.returncode != 0:
    raise SystemExit('V60 browser JavaScript syntax failed:\n' + check.stderr)

# V60 must not re-own workout persistence. It may only decorate workout state.
v60_js = match.group(1)
for forbidden in ["from('set_logs').update", 'cvSetToggleLocksV48=', 'cvPersistSetLogV51=']:
    if forbidden in v60_js:
        raise SystemExit(f'V60 illegally re-owned workout persistence: {forbidden}')

print('CV_RANK_SYSTEM_V60_OK')
