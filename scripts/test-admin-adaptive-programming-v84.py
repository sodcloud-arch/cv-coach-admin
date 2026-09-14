from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
html=(ROOT/'index.html').read_text(encoding='utf-8')
js=(ROOT/'admin-assets/cv-adaptive-programming-admin-v84.js').read_text(encoding='utf-8')

for marker in [
    'cv-admin-adaptive-programming-v84',
    '/admin-assets/cv-adaptive-programming-admin-v84.js',
    'id="openTrainingTrendsV84"',
    'TENDENCIAS V84',
    'openTrainingTrendsV84(id)',
]:
    if marker not in html:
        raise SystemExit(f'V84 admin HTML marker missing: {marker}')

for marker in [
    'CV_ADMIN_ADAPTIVE_PROGRAMMING_V84_READY',
    'get_adaptive_programming_center_v84',
    'get_client_training_trends_v84',
    'prepare_adaptive_program_draft_v84',
    'PREPARAR DELOAD',
    'PREPARAR SIGUIENTE BLOQUE',
    'ABRIR BORRADOR V84',
    'TENDENCIAS V84',
]:
    if marker not in js:
        raise SystemExit(f'V84 admin JS marker missing: {marker}')

print('CV_ADMIN_ADAPTIVE_PROGRAMMING_V84_OK')
