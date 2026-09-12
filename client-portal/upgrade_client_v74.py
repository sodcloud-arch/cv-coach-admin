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
MARKER = '<!-- cv-workout-interaction-v74: immediate-feedback + per-set-lock + null-data-render-guard -->'

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
    "if(!dataReady())return false",
    "await base.apply(this,arguments)",
    "after!==target",
    "__cv74Interaction",
    "__cv74RenderGuard",
    "CVWorkoutInteractionV74",
]
for token in required_js:
    if token not in js:
        raise SystemExit(f'V74 JS contract missing: {token}')

text = HTML.read_text(encoding='utf-8')
text = re.sub(r'<script id="cv-workout-interaction-v74-js">.*?</script>', '', text, flags=re.S)
text = text.replace(MARKER, '')

if 'CVWorkoutNumpadV73' not in text:
    raise SystemExit('V74 requires built V73 runtime')
if '</body>' not in text:
    raise SystemExit('V74 HTML anchor missing')

text = text.replace(
    '</body>',
    f'<script id="{SCRIPT_ID}">\n{js}\n</script>\n{MARKER}\n</body>',
    1,
)

for token in [SCRIPT_ID, MARKER, 'CVWorkoutInteractionV74', '__cv74Interaction', '__cv74RenderGuard']:
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
    'Null-data render race guard v74',
]:
    if patch not in patches:
        patches.append(patch)
metadata['patches'] = patches
BUILD.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'sha256': sha, 'bytes': metadata['bytes'], 'patches': patches[-3:]}, ensure_ascii=False))
