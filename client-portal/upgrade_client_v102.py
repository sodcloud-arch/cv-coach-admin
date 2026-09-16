from pathlib import Path
import re
import subprocess

ROOT=Path(__file__).resolve().parent
HTML=ROOT/'stable'/'index.html'
ASSET=ROOT/'assets'/'cv-exercise-screen-v102.js'
MARKER='<!-- cv-exercise-screen-v102: opt-in-inline-media + mobile-fit + proximity-snap -->'
SCRIPT='<script src="./assets/cv-exercise-screen-v102.js"></script>'

for path in [HTML,ASSET]:
    if not path.exists() or path.stat().st_size < 300:
        raise SystemExit(f'CV V102 source missing: {path}')

subprocess.run(['node','--check',str(ASSET)],check=True)
text=HTML.read_text(encoding='utf-8')
text=re.sub(r'\s*<script src=["\']\./assets/cv-exercise-screen-v102\.js["\']></script>\s*','\n',text)
text=text.replace(MARKER,'')

required_source_tokens=[
    'cvHevyExercise',
    'exerciseMedia',
    'cvExecutionBtnV35',
    'cvFastWorkout',
    './assets/cv-push-v101.js'
]
for token in required_source_tokens:
    if token not in text:
        raise SystemExit(f'V102 source contract missing: {token}')

if '</body>' not in text:
    raise SystemExit('V102 body injection target missing')

payload=f'\n{MARKER}\n{SCRIPT}\n'
text=text.replace('</body>',payload+'</body>',1)

for token in [MARKER,SCRIPT,'cv-exercise-screen-v102.js']:
    if token not in text:
        raise SystemExit(f'V102 client contract missing: {token}')
if text.count('./assets/cv-exercise-screen-v102.js') != 1:
    raise SystemExit('V102 exercise asset must be injected exactly once')

HTML.write_text(text,encoding='utf-8')
print('CV_CLIENT_EXERCISE_SCREEN_V102_PATCHED')
