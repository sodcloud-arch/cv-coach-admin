from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
ASSET=ROOT/'client-portal'/'assets'/'cv-exercise-screen-v102.js'
HTML=ROOT/'client-portal'/'stable'/'index.html'

for path in [ASSET,HTML]:
    if not path.exists() or path.stat().st_size < 300:
        raise SystemExit(f'V102 required file missing: {path}')

asset=ASSET.read_text(encoding='utf-8')
html=HTML.read_text(encoding='utf-8')

asset_tokens=[
    'CV_EXERCISE_SCREEN_V102_READY',
    "QUERY_KEY='cv_v102'",
    "STORAGE_KEY='cv_v102_experiment'",
    'scroll-snap-type:y proximity',
    'height:min(240px,62vw)',
    "button.remove()",
    "top.insertAdjacentElement('afterend',media)",
    'cvExerciseLegacyMainV102',
    'MutationObserver',
]
for token in asset_tokens:
    if token not in asset:
        raise SystemExit(f'V102 asset contract missing: {token}')

html_tokens=[
    'cv-exercise-screen-v102: opt-in-inline-media + mobile-fit + proximity-snap',
    'cv-exercise-screen-v102-inline-start',
    'CV_EXERCISE_SCREEN_V102_READY',
    'cv-client-push-v101: explicit-consent + web-push + preferences',
    'CVWorkoutSetGuardV74',
    'cvExecutionBtnV35',
    'exerciseMedia',
]
for token in html_tokens:
    if token not in html:
        raise SystemExit(f'V102 stable contract missing: {token}')

if html.count('cv-exercise-screen-v102-inline-start') != 1:
    raise SystemExit('V102 runtime injected more than once')
if html.index('cv-client-push-v101: explicit-consent + web-push + preferences') > html.index('cv-exercise-screen-v102-inline-start'):
    raise SystemExit('V102 must load after V101')
if "localStorage.setItem(STORAGE_KEY,'1')" not in asset or "localStorage.removeItem(STORAGE_KEY)" not in asset:
    raise SystemExit('V102 opt-in/opt-out contract incomplete')
if 'body.cvFastWorkout .exerciseMedia,body.cvFastWorkout .cvTechnique{display:none!important}' not in html:
    raise SystemExit('Expected legacy hidden-media rule changed unexpectedly')
if 'body.${BODY_CLASS}.cvFastWorkout .${CARD_CLASS}>.exerciseMedia' not in asset:
    raise SystemExit('V102 must override media visibility only inside the experiment')

print('CV_MOBILE_EXERCISE_V102_OK')
