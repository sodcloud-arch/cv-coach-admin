from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[1]
HTML=ROOT/'client-portal'/'stable'/'index.html'
JS=ROOT/'client-portal'/'assets'/'cv-workout-controller-v71.js'
V72=ROOT/'client-portal'/'assets'/'cv-ios-keyboard-v72.js'

subprocess.run(['node','--check',str(JS)],check=True)
subprocess.run(['node','--check',str(V72)],check=True)
js=JS.read_text(encoding='utf-8')
v72=V72.read_text(encoding='utf-8')
html=HTML.read_text(encoding='utf-8')
required_js=[
    "window.startWorkout=canonicalStart",
    "if(isDemo())",
    "target.sessionId='demo'",
    "snapshotInputs()",
    "applySnapshot(target.liveExercises,snap)",
    "sb.auth.getSession()",
    "sb.auth.refreshSession()",
    "sb.functions.invoke('start-workout'",
    "recover(requestedDay)",
    "version:'v71'",
]
for token in required_js:
    if token not in js: raise SystemExit(f'V71 missing JS contract: {token}')
for forbidden in ['cvKeyboardEditingV71',"addEventListener('focusin'",'window.scrollBy({top:dy']:
    if forbidden in js: raise SystemExit(f'V71 competing keyboard contract present: {forbidden}')
for token in ['CVIOSKeyboardV72',"version:'v72'",'multiRestore','enterkeyhint','cvKeyboardEditingV72']:
    if token not in v72: raise SystemExit(f'V72 keyboard contract missing: {token}')
required_html=[
    'cv-workout-controller-v71-js',
    'cv-workout-controller-v71: authoritative-start + demo-safe + input-preservation',
    "window.startWorkout=canonicalStart",
    'CVWorkoutControllerV71',
    'cv-ios-keyboard-v72-js',
    'cv-ios-keyboard-v72: sole-workout-viewport-owner + preserve-scroll + done-key-restore',
    'CVIOSKeyboardV72',
]
for token in required_html:
    if token not in html: raise SystemExit(f'V71/V72 missing built contract: {token}')
if "el.scrollIntoView({behavior:'smooth',block:'center'})},180);" in html:
    raise SystemExit('Legacy V40 center-scroll policy survived final build')
# V71 must be injected after legacy wrappers so it owns the final global start handler.
pos_v71=html.rfind("window.startWorkout=canonicalStart")
pos_any=max(html.rfind("window.startWorkout=async function"),html.rfind("window.startWorkout=async()=>"),html.rfind("window.startWorkout=guarded"))
if pos_v71 <= pos_any:
    raise SystemExit(f'V71 is not authoritative: v71={pos_v71} legacy={pos_any}')
# V72 must be later than V71 and must be the only modern workout viewport policy.
if html.rfind('CVIOSKeyboardV72') <= html.rfind('CVWorkoutControllerV71'):
    raise SystemExit('V72 was not injected after V71')
print('CV_WORKOUT_CONTROLLER_V71_V72_OK')
