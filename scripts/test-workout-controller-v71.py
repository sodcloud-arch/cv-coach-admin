from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[1]
HTML=ROOT/'client-portal'/'stable'/'index.html'
JS=ROOT/'client-portal'/'assets'/'cv-workout-controller-v71.js'
V73=ROOT/'client-portal'/'assets'/'cv-workout-numpad-v73.js'
V73CSS=ROOT/'client-portal'/'assets'/'cv-workout-numpad-v73.css'

subprocess.run(['node','--check',str(JS)],check=True)
subprocess.run(['node','--check',str(V73)],check=True)
js=JS.read_text(encoding='utf-8')
v73=V73.read_text(encoding='utf-8')
v73css=V73CSS.read_text(encoding='utf-8')
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
for token in ['CVWorkoutNumpadV73',"version:'v73'",'readOnly=true',"setAttribute('inputmode','none')",'LISTO ✓','dispatchEvent(new Event(\'change\',{bubbles:true}))']:
    if token not in v73: raise SystemExit(f'V73 numpad contract missing: {token}')
for token in ['cvNumpadV73','cvPadSheetV73','cvPadDoneV73','cvPadEditingV73']:
    if token not in v73css: raise SystemExit(f'V73 CSS contract missing: {token}')
required_html=[
    'cv-workout-controller-v71-js',
    'cv-workout-controller-v71: authoritative-start + demo-safe + input-preservation',
    "window.startWorkout=canonicalStart",
    'CVWorkoutControllerV71',
    'cv-workout-numpad-v73-js',
    'cv-workout-numpad-v73-css',
    'cv-workout-numpad-v73: native-keyboard-retired + custom-editor + deterministic-save',
    'CVWorkoutNumpadV73',
]
for token in required_html:
    if token not in html: raise SystemExit(f'V71/V73 missing built contract: {token}')
for forbidden in [
    "el.scrollIntoView({behavior:'smooth',block:'center'})},180);",
    'CVIOSKeyboardV72',
    'cvKeyboardEditingV72',
    "x.classList.add('cvInputActive')"
]:
    if forbidden in html: raise SystemExit(f'Retired native-keyboard policy survived final build: {forbidden}')
# V71 must be injected after legacy wrappers so it owns the final global start handler.
pos_v71=html.rfind("window.startWorkout=canonicalStart")
pos_any=max(html.rfind("window.startWorkout=async function"),html.rfind("window.startWorkout=async()=>"),html.rfind("window.startWorkout=guarded"))
if pos_v71 <= pos_any:
    raise SystemExit(f'V71 is not authoritative: v71={pos_v71} legacy={pos_any}')
# V73 must be later than V71 and is the only workout numeric editor.
if html.rfind('CVWorkoutNumpadV73') <= html.rfind('CVWorkoutControllerV71'):
    raise SystemExit('V73 was not injected after V71')
print('CV_WORKOUT_CONTROLLER_V71_V73_OK')
