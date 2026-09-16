from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parent
HTML = ROOT / 'stable' / 'index.html'
ASSET = ROOT / 'assets' / 'cv-exercise-details-v103.js'
MARKER = '<!-- cv-exercise-details-v103: explicit-link + structured-technique-sheet -->'
START = '<!-- cv-exercise-details-v103-inline-start -->'
END = '<!-- cv-exercise-details-v103-inline-end -->'

for path in [HTML, ASSET]:
    if not path.exists() or path.stat().st_size < 500:
        raise SystemExit(f'CV V103 source missing: {path}')

subprocess.run(['node', '--check', str(ASSET)], check=True)
asset = ASSET.read_text(encoding='utf-8').strip()
text = HTML.read_text(encoding='utf-8')

# Idempotent replacement.
text = re.sub(
    rf'\s*{re.escape(START)}.*?{re.escape(END)}\s*',
    '\n',
    text,
    flags=re.S,
)
text = text.replace(MARKER, '')

required_base_tokens = [
    'CV_EXERCISE_SCREEN_V102_READY',
    'V102.2_SELF_CONTAINED_FOCUS',
    'cvHevyExercise',
    'cvOpenTechnique',
    'data-tech-name',
]
for token in required_base_tokens:
    if token not in text:
        raise SystemExit(f'V103 base contract missing: {token}')

required_asset_tokens = [
    'CV_EXERCISE_DETAILS_V103_READY',
    "const VERSION='103'",
    'cvDetailsLinkV103',
    'Ver detalles',
    'get_exercise_technique_v103',
    'Tiempos de ejecución',
    'Agarre, separación y postura',
    'Ejecución paso a paso',
    'Errores frecuentes',
]
for token in required_asset_tokens:
    if token not in asset:
        raise SystemExit(f'V103 asset contract missing: {token}')

if '</body>' not in text:
    raise SystemExit('V103 body injection target missing')

payload = (
    f'\n{MARKER}\n'
    f'{START}\n'
    f'<script>\n{asset}\n</script>\n'
    f'{END}\n'
)
text = text.replace('</body>', payload + '</body>', 1)

for token in [MARKER, START, END, 'CV_EXERCISE_DETAILS_V103_READY', 'cvDetailsLinkV103', 'get_exercise_technique_v103']:
    if token not in text:
        raise SystemExit(f'V103 client contract missing: {token}')
if text.count(START) != 1 or text.count(END) != 1:
    raise SystemExit('V103 inline runtime must be injected exactly once')

HTML.write_text(text, encoding='utf-8')
print('CV_CLIENT_EXERCISE_DETAILS_V103_PATCHED')
