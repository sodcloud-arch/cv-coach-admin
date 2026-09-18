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
    "CONTRACT_REVISION='V102.2_SELF_CONTAINED_FOCUS'",
    "PREVIOUS_CONTRACT_REVISION='V102.1_ACTIVE_FOCUS'",
    "QUERY_KEY='cv_v102'",
    "STORAGE_KEY='cv_v102_experiment'",
    "READY_CLASS='cvV102WorkoutReady'",
    'scroll-snap-type:y proximity',
    "EXPANDED_CLASS='cvV102Expanded'",
    "COLLAPSED_CLASS='cvV102Collapsed'",
    'height:min(244px,63vw)',
    "card.getAttribute('data-tech-img')",
    "media.dataset.cvV102Generated='1'",
    "top.parentElement===card",
    "top.after(media)",
    "card.appendChild(media)",
    "card.setAttribute('aria-expanded'",
    "scrollIntoView({behavior,block:'start'})",
    "attributes:true,attributeFilter:['class']",
    "document.body.dataset.cvV102='102.2'",
    "document.body.classList.contains('cvFastWorkout')&&cards.length>0",
    'cvExerciseLegacyMainV102',
    'MutationObserver',
]
for token in asset_tokens:
    if token not in asset:
        raise SystemExit(f'V102.2 asset contract missing: {token}')

html_tokens=[
    'cv-exercise-screen-v102: opt-in-inline-media + mobile-fit + proximity-snap',
    'cv-exercise-screen-v102-inline-start',
    'CV_EXERCISE_SCREEN_V102_READY',
    'cv-client-push-v101: explicit-consent + web-push + preferences',
    'CVWorkoutSetGuardV74',
    'cvExecutionBtnV35',
    'data-tech-img',
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
if 'body.${BODY_CLASS}.${READY_CLASS} .${CARD_CLASS}.${EXPANDED_CLASS}>.exerciseMedia' not in asset:
    raise SystemExit('V102.2 must override media visibility for the focused exercise')
if 'body.${BODY_CLASS}.${READY_CLASS} .${CARD_CLASS}.${COLLAPSED_CLASS}>.cvSetRows' not in asset:
    raise SystemExit('V102.2 must collapse non-current exercise logging rows')
if "document.body.classList.add(READY_CLASS)" not in asset:
    raise SystemExit('V102.2 must own its workout-ready visual state')
if "version:'102.2'" not in asset:
    raise SystemExit('V102.2 runtime version missing')
if "top.insertAdjacentElement('afterend',media)" in asset:
    raise SystemExit('V102.2 must not reintroduce race-prone insertAdjacentElement media placement')
if "card.insertBefore(media" in asset:
    raise SystemExit('V102.2 must not use a stale reference-node insertBefore for media placement')
if "if(!document.body.classList.contains('cvFastWorkout'))return;" in asset:
    raise SystemExit('V102.2 must not silently return before establishing its own ready state')
if "return document.body?.classList.contains('cvWorkoutActiveV40')===true" in asset:
    raise SystemExit('V102.2 must not depend on legacy V40 session-start state')

print('CV_MOBILE_EXERCISE_V102_2_OK')
