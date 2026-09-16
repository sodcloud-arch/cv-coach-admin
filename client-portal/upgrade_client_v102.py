from pathlib import Path
import re
import subprocess

ROOT=Path(__file__).resolve().parent
HTML=ROOT/'stable'/'index.html'
ASSET=ROOT/'assets'/'cv-exercise-screen-v102.js'
MARKER='<!-- cv-exercise-screen-v102: opt-in-inline-media + mobile-fit + proximity-snap -->'
START='<!-- cv-exercise-screen-v102-inline-start -->'
END='<!-- cv-exercise-screen-v102-inline-end -->'

for path in [HTML,ASSET]:
    if not path.exists() or path.stat().st_size < 300:
        raise SystemExit(f'CV V102 source missing: {path}')

subprocess.run(['node','--check',str(ASSET)],check=True)
asset=ASSET.read_text(encoding='utf-8').strip()
text=HTML.read_text(encoding='utf-8')
text=re.sub(
    rf'\s*{re.escape(START)}.*?{re.escape(END)}\s*',
    '\n',
    text,
    flags=re.S,
)
text=text.replace(MARKER,'')

required_source_tokens=[
    'cvHevyExercise',
    'exerciseMedia',
    'cvExecutionBtnV35',
    'cvFastWorkout',
    'cvWorkoutActiveV40',
    './assets/cv-push-v101.js'
]
for token in required_source_tokens:
    if token not in text:
        raise SystemExit(f'V102 source contract missing: {token}')

required_asset_tokens=[
    'CV_EXERCISE_SCREEN_V102_READY',
    'V102.2_SELF_CONTAINED_FOCUS',
    "READY_CLASS='cvV102WorkoutReady'",
    "document.body.dataset.cvV102='102.2'",
    "document.body.classList.contains('cvFastWorkout')&&cards.length>0",
]
for token in required_asset_tokens:
    if token not in asset:
        raise SystemExit(f'V102.2 asset contract missing: {token}')

if '</body>' not in text:
    raise SystemExit('V102 body injection target missing')

payload=(
    f'\n{MARKER}\n'
    f'{START}\n'
    f'<script>\n{asset}\n</script>\n'
    f'{END}\n'
)
text=text.replace('</body>',payload+'</body>',1)

for token in [
    MARKER,
    START,
    END,
    'CV_EXERCISE_SCREEN_V102_READY',
    'V102.2_SELF_CONTAINED_FOCUS',
    "QUERY_KEY='cv_v102'",
    'scroll-snap-type:y proximity',
    'cvExecutionBtnV35',
    'cvV102Expanded',
    'cvV102Collapsed',
    'cvV102WorkoutReady',
]:
    if token not in text:
        raise SystemExit(f'V102.2 client contract missing: {token}')
if text.count(START) != 1 or text.count(END) != 1:
    raise SystemExit('V102 inline runtime must be injected exactly once')

HTML.write_text(text,encoding='utf-8')
print('CV_CLIENT_EXERCISE_SCREEN_V102_2_PATCHED')
