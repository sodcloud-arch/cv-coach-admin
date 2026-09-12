from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
HTML=ROOT/'client-portal'/'stable'/'index.html'
JS=ROOT/'client-portal'/'assets'/'cv-rank-celebration-v66.js'
CSS=ROOT/'client-portal'/'assets'/'cv-rank-celebration-v68.css'

for p in [HTML,JS,CSS]:
    if not p.exists() or p.stat().st_size<200:
        raise SystemExit(f'V68 artifact missing: {p}')

html=HTML.read_text(encoding='utf-8')
js=JS.read_text(encoding='utf-8')
css=CSS.read_text(encoding='utf-8')

checks={
    'html marker':'cv-rank-cinematic-v68',
    'runtime version':"version:'v68'",
    'reference audio':'cv-rank-up-v67.mp3',
    'source seek':'RANK_UP_START_AT=0.50',
    'playback rate':'RANK_UP_RATE=1.15',
    'source impact':'RANK_UP_IMPACT_SOURCE=3.36',
    'hybrid impact':'cinematicImpact',
    'audio start class':"classList.add('cv66AudioPlaying')",
}
for label,token in checks.items():
    if token not in html and token not in js:
        raise SystemExit(f'V68 {label} contract missing: {token}')

for token in [
    '.cv66Ascend.rank_up .cv66Brand',
    'display:none!important',
    'cv68OldCharge',
    'cv68CoreBurst',
    'cv68NewReveal',
    'cv68ImpactFlash'
]:
    if token not in css or token not in html:
        raise SystemExit(f'V68 visual contract missing: {token}')

if 'brightness(4.5)' in css:
    raise SystemExit('V68 must not reintroduce blown-out badge filter')

print('CV_RANK_CINEMATIC_V68_OK')
