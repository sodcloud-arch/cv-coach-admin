from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
JS=ROOT/'client-portal'/'assets'/'cv-workout-optimistic-v71.js'
HTML=ROOT/'client-portal'/'stable'/'index.html'

src=JS.read_text(encoding='utf-8')
required=[
    'CVWorkoutOptimisticV71',
    '__cv71Optimistic',
    'pending.has(k)',
    'paint(i,j,target,true)',
    'await base.apply(this,arguments)',
    'pending.delete(k);settle(i,j)',
    "btn.disabled=!!isPending",
    "badge.textContent=complete?'COMPLETADO':current?'AHORA':'PENDIENTE'",
    'cvWorkoutProgressFill',
    'cvWorkoutProgressCopy',
    'No se confirmó la serie. Intenta nuevamente.'
]
for token in required:
    if token not in src:
        raise SystemExit(f'V71 token missing: {token}')

# Critical UX contract: optimistic paint must happen before the async base toggle.
if src.index('paint(i,j,target,true)') > src.index('await base.apply(this,arguments)'):
    raise SystemExit('V71 regression: optimistic feedback occurs after backend wait')

# Double-tap guard must execute before optimistic transition.
if src.index('pending.has(k)') > src.index('paint(i,j,target,true)'):
    raise SystemExit('V71 regression: duplicate-tap guard is too late')

# Final reconciliation must use the actual model state.
if 'const after=state(i,j),ok=after===target' not in src:
    raise SystemExit('V71 regression: missing model reconciliation')

if HTML.exists():
    html=HTML.read_text(encoding='utf-8')
    for token in ['cv-workout-optimistic-v71-js','CVWorkoutOptimisticV71','cv-workout-optimistic-v71: immediate-set-feedback']:
        if token not in html:
            raise SystemExit(f'V71 stable artifact missing: {token}')

print('CV_WORKOUT_OPTIMISTIC_V71_OK')
