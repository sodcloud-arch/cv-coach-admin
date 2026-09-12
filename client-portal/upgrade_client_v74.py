from pathlib import Path
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parent
HTML = ROOT / 'stable' / 'index.html'
BUILD = ROOT / 'stable' / 'build.json'
JS = ROOT / 'assets' / 'cv-workout-interaction-v74.js'
SCRIPT_ID = 'cv-workout-interaction-v74-js'
MARKER = '<!-- cv-workout-interaction-v74: immediate-feedback + per-set-lock + canonical-null-data-render-guard -->'
RENDER_ANCHOR = "function render(){const c=$('#content');"
RENDER_GUARDED = "function render(){if(typeof data==='undefined'||data===null)return false;/* cv74 canonical render null guard */const c=$('#content');"
PRESTART_ANCHOR = "  function cvPrestartExercises(){\n    const d=data.days.find(x=>x.id===workout.dayId);const raw=data.exercises[d.id]||[];"
PRESTART_GUARDED = "  function cvPrestartExercises(){\n    if(!data||!Array.isArray(data.days)||!data.exercises||!workout?.dayId)return [];/* cv74 prestart null guard */\n    const d=data.days.find(x=>x.id===workout.dayId);if(!d)return [];const raw=data.exercises[d.id]||[];"

for path in [HTML, JS]:
    if not path.exists() or path.stat().st_size < 500:
        raise SystemExit(f'CV V74 source missing: {path}')

subprocess.run(['node', '--check', str(JS)], check=True)
js = JS.read_text(encoding='utf-8')

required_js = [
    "version:VERSION",
    "pending.has(k)",
    "paint(i,j,target,true)",
    "btn.disabled=true",
    "btn.setAttribute('aria-busy','true')",
    "await base.apply(this,arguments)",
    "after!==target",
    "__cv74Interaction",
    "CVWorkoutInteractionV74",
]
for token in required_js:
    if token not in js:
        raise SystemExit(f'V74 JS contract missing: {token}')

text = HTML.read_text(encoding='utf-8')
text = re.sub(r'<script id="cv-workout-interaction-v74-js">.*?</script>', '', text, flags=re.S)
text = text.replace(MARKER, '')

# The historical portal can call render() before V74's late runtime wrapper is loaded.
# Guard the canonical render function itself so null-data startup is safe from first definition.
if '/* cv74 canonical render null guard */' not in text:
    count = text.count(RENDER_ANCHOR)
    if count != 1:
        raise SystemExit(f'V74 canonical render anchor mismatch: expected 1, got {count}')
    text = text.replace(RENDER_ANCHOR, RENDER_GUARDED, 1)

# Startup decorators can call cvExercises() before client data/workout state exists.
# Make the canonical prestart exercise factory safe at its source instead of masking callers.
if '/* cv74 prestart null guard */' not in text:
    count = text.count(PRESTART_ANCHOR)
    if count != 1:
        raise SystemExit(f'V74 prestart anchor mismatch: expected 1, got {count}')
    text = text.replace(PRESTART_ANCHOR, PRESTART_GUARDED, 1)

if 'CVWorkoutNumpadV73' not in text:
    raise SystemExit('V74 requires built V73 runtime')
if '</body>' not in text:
    raise SystemExit('V74 HTML anchor missing')

text = text.replace(
    '</body>',
    f'<script id="{SCRIPT_ID}">\n{js}\n</script>\n{MARKER}\n</body>',
    1,
)

for token in [
    SCRIPT_ID,
    MARKER,
    'CVWorkoutInteractionV74',
    '__cv74Interaction',
    '/* cv74 canonical render null guard */',
    '/* cv74 prestart null guard */',
]:
    if token not in text:
        raise SystemExit(f'V74 final token missing: {token}')

if text.rfind('CVWorkoutInteractionV74') <= text.rfind('CVWorkoutNumpadV73'):
    raise SystemExit('V74 must be injected after V73')

HTML.write_text(text, encoding='utf-8')
sha = hashlib.sha256(text.encode('utf-8')).hexdigest()
metadata = {}
if BUILD.exists():
    try:
        metadata = json.loads(BUILD.read_text(encoding='utf-8'))
    except Exception:
        metadata = {}
metadata['bytes'] = len(text.encode('utf-8'))
metadata['sha256'] = sha
patches = list(metadata.get('patches') or [])
for patch in [
    'Immediate first-touch set feedback v74',
    'Per-set concurrent toggle lock v74',
    'Canonical null-data render race guard v74',
    'Prestart exercise null-data guard v74',
]:
    if patch not in patches:
        patches.append(patch)
metadata['patches'] = patches
BUILD.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'sha256': sha, 'bytes': metadata['bytes'], 'patches': patches[-4:]}, ensure_ascii=False))
