from pathlib import Path
import re,subprocess

ROOT=Path(__file__).resolve().parents[1]
HTML=ROOT/'client-portal'/'stable'/'index.html'
JS=ROOT/'client-portal'/'assets'/'cv-workout-controller-v71.js'

subprocess.run(['node','--check',str(JS)],check=True)
js=JS.read_text(encoding='utf-8')
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
    "cvKeyboardEditingV71",
    "version:'v71'",
]
for token in required_js:
    if token not in js: raise SystemExit(f'V71 missing JS contract: {token}')
required_html=[
    'cv-workout-controller-v71-js',
    'cv-workout-controller-v71: authoritative-start + demo-safe + ios-input-stability',
    "window.startWorkout=canonicalStart",
    'CVWorkoutControllerV71',
]
for token in required_html:
    if token not in html: raise SystemExit(f'V71 missing built contract: {token}')
# V71 must be injected after legacy wrappers so it owns the final global start handler.
pos_v71=html.rfind("window.startWorkout=canonicalStart")
pos_any=max(html.rfind("window.startWorkout=async function"),html.rfind("window.startWorkout=async()=>"),html.rfind("window.startWorkout=guarded"))
if pos_v71 <= pos_any:
    raise SystemExit(f'V71 is not authoritative: v71={pos_v71} legacy={pos_any}')
print('CV_WORKOUT_CONTROLLER_V71_OK')
