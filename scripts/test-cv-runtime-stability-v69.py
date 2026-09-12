from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
HTML=ROOT/'client-portal'/'stable'/'index.html'
CSS=ROOT/'client-portal'/'assets'/'cv-rank-stability-v69.css'
JS=ROOT/'client-portal'/'assets'/'cv-runtime-stability-v69.js'

for p in [HTML,CSS,JS]:
    if not p.exists() or p.stat().st_size<300:
        raise SystemExit(f'V69 artifact missing: {p}')
html=HTML.read_text(encoding='utf-8')
css=CSS.read_text(encoding='utf-8')
js=JS.read_text(encoding='utf-8')
checks={
    'marker':'cv-runtime-stability-v69',
    'script id':'cv-runtime-stability-v69-js',
    'style id':'cv-rank-stability-v69-css',
    'visual impact':'RANK_IMPACT_MS=2480',
    'rank failsafe':'RANK_FAILSAFE_MS=5200',
    'workout timeout':'START_TIMEOUT_MS=11000',
    'recovery':'recoverActiveWorkout',
    'start guard':'installStartGuard',
    'final state':'cv69Final',
    'premium backdrop':'cv69Backdrop',
}
for label,token in checks.items():
    if token not in html and token not in js and token not in css:
        raise SystemExit(f'V69 {label} missing: {token}')
if "node.classList.add('cv66Impact')" not in js:
    raise SystemExit('V69 visual master impact missing')
if "setTimeout(()=>forceRankFinal(node),RANK_FAILSAFE_MS)" not in js:
    raise SystemExit('V69 hard rank failsafe missing')
if "Promise.race([Promise.resolve(p),delayReject(ms,message)])" not in js:
    raise SystemExit('V69 bounded workout promise missing')
if "sb.from('workout_sessions')" not in js:
    raise SystemExit('V69 active session recovery query missing')
if '.cv66Ascend.rank_up.cv69Final .cv66Badge.to' not in css:
    raise SystemExit('V69 final new badge visibility contract missing')
if '.cvWorkoutStartV40.cv69Starting' not in css:
    raise SystemExit('V69 start button feedback contract missing')
print('CV_RUNTIME_STABILITY_V69_OK')
