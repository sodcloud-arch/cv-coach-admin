from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
HTML=ROOT/'client-portal'/'stable'/'index.html'
JS=ROOT/'client-portal'/'assets'/'cv-rank-state-guard-v70.js'
UP=ROOT/'client-portal'/'upgrade_client_v70.py'

for p in [HTML,JS,UP]:
    if not p.exists() or p.stat().st_size<200:
        raise SystemExit(f'V70 artifact missing: {p}')
html=HTML.read_text(encoding='utf-8')
js=JS.read_text(encoding='utf-8')
checks=[
    'cv-rank-state-guard-v70',
    'CVRankStateGuardV70',
    'get_client_rank_dashboard_v61',
    'cv_rank_dashboard_v70_',
    'Sincronizando progreso',
    "if(!Number.isFinite(raw)||raw<=0)out.rating_to_next_level",
    'updateWorkout(d)',
    'updateHome(d)',
    'setHTMLIfChanged',
    'rankSurfaceAdded',
    'rankMountObserver',
]
for token in checks:
    if token not in html and token not in js:
        raise SystemExit(f'V70 contract missing: {token}')
legacy="new MutationObserver(()=>schedule(90)).observe(document.documentElement,{childList:true,subtree:true});"
if legacy in js or legacy in html:
    raise SystemExit('V70 global self-reactive MutationObserver returned')
for forbidden in ['meta.innerHTML=','state.innerHTML=','strong.innerHTML=','title.innerHTML=','next.innerHTML=']:
    if forbidden in js:
        raise SystemExit(f'V70 unconditional DOM write returned: {forbidden}')
if "rankMountObserver.observe(document.getElementById('content')||document.body,{childList:true,subtree:true});" not in js:
    raise SystemExit('V70 scoped rank mount observer missing')
if "state.dash=demo()" not in (ROOT/'client-portal'/'assets'/'cv-rank-v61.js').read_text(encoding='utf-8'):
    raise SystemExit('V70 expected legacy fallback signature changed; reassess guard')
print('CV_RANK_STATE_V70_OK')
print('CV_RANK_STATE_V70_MUTATION_LOOP_GUARD_OK')
