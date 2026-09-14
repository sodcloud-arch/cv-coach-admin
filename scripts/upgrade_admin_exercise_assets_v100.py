from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
HTML=ROOT/'index.html'
MARKER='<!-- cv-admin-exercise-assets-v100 -->'
ASSET='<script src="/admin-assets/cv-exercise-assets-v100.js"></script>'+MARKER

text=HTML.read_text(encoding='utf-8')
if MARKER not in text:
    anchor='</body>'
    if anchor not in text:
        raise SystemExit('Admin V100 requires </body> anchor')
    text=text.replace(anchor,ASSET+anchor,1)

for item in [MARKER,'/admin-assets/cv-exercise-assets-v100.js']:
    if item not in text:
        raise SystemExit(f'Admin V100 contract missing: {item}')

HTML.write_text(text,encoding='utf-8')
print('CV_ADMIN_EXERCISE_ASSETS_V100_PATCHED')
