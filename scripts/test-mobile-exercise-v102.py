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
    "CONTRACT_REVISION='V102.1_ACTIVE_FOCUS'",
    "QUERY_KEY='cv_v102'",
    "STORAGE_KEY='cv_v102_experiment'",
    'scroll-snap-type:y proximity',
    'cvWorkoutActiveV40',
    "EXPANDED_CLASS='cvV102Expanded'",
    "COLLAPSED_CLASS='cvV102Collapsed'",
    'height:min(244px,63vw)',
    "card.getAttribute('data-tech-img')",
    "media.dataset.cvV102Generated='1'",
    "top.insertAdjacentElement('afterend',media)",
    "card.setAttribute('aria-expanded'",
    "scrollIntoView({behavior,block:'start'})",
    "attributes:true,attributeFilter:['class']",
    'cvExerciseLegacyMainV102',
    'MutationObserver',
]
for token in asset_tokens:
    if token not in asset:
        raise SystemExit(f'V102.1 asset contract missing: {token}')

html_tokens=[
    'cv-exercise-screen-v102: opt-in-inline-media + mobile-fit + proximity-snap',
    'cv-exercise-screen-v102-inline-start',
    'CV_EXERCISE_SCREEN_V102_READY',
    'cv-client-push-v101: explicit-consent + web-push + preferences',
    'CVWorkoutSetGuardV74',
    'cvExecutionBtnV35',
    'data-tech-img',
    'cvWorkoutActiveV40',
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
if 'body.${BODY_CLASS}.cvWorkoutActiveV40 .${CARD_CLASS}.${EXPANDED_CLASS}>.exerciseMedia' not in asset:
    raise SystemExit('V102.1 must override media visibility only for the active exercise')
if 'body.${BODY_CLASS}.cvWorkoutActiveV40 .${CARD_CLASS}.${COLLAPSED_CLASS}>.cvSetRows' not in asset:
    raise SystemExit('V102.1 must collapse non-current exercise logging rows')
if "if(!isWorkoutActive()){\n    clearFocusState(cards);\n    return;\n  }" not in asset:
    raise SystemExit('V102.1 must not alter pre-start exercise cards')
if "version:'102.1'" not in asset:
    raise SystemExit('V102.1 runtime version missing')

print('CV_MOBILE_EXERCISE_V102_1_OK')
