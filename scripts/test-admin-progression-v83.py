from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
html=(ROOT/'index.html').read_text(encoding='utf-8')
js=(ROOT/'admin-assets/cv-progression-admin-v83.js').read_text(encoding='utf-8')

required_html=[
    'cv-admin-progression-v83',
    'data-v="progression"',
    "progression:'Centro de Progresión'",
    "view==='progression'",
    '/admin-assets/cv-progression-admin-v83.js',
]
for marker in required_html:
    if marker not in html:
        raise SystemExit(f'V83 admin HTML marker missing: {marker}')

required_js=[
    'CV_ADMIN_PROGRESSION_V83_READY',
    'get_progression_center_v83',
    'review_progression_suggestion_v83',
    'review_training_adaptation_v83',
    'AUMENTAR TIEMPO',
    'DELOAD RECOMENDADO',
    'GUARDAR MODIFICACIÓN',
]
for marker in required_js:
    if marker not in js:
        raise SystemExit(f'V83 admin JS marker missing: {marker}')

print('CV_ADMIN_PROGRESSION_V83_OK')
