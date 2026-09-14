from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
HTML=ROOT/'index.html'
MARKER='<!-- cv-admin-mesocycle-intelligence-v85 -->'
text=HTML.read_text(encoding='utf-8')
if MARKER not in text:
    anchor='<script src="/admin-assets/cv-adaptive-programming-admin-v84.js"></script><!-- cv-admin-adaptive-programming-v84 -->'
    if anchor not in text:
        raise SystemExit('Admin V85 requires V84 asset anchor')
    text=text.replace(anchor,anchor+'<script src="/admin-assets/cv-mesocycle-intelligence-admin-v85.js"></script>'+MARKER,1)
for item in [MARKER,'/admin-assets/cv-mesocycle-intelligence-admin-v85.js']:
    if item not in text:
        raise SystemExit(f'Admin V85 contract missing: {item}')
HTML.write_text(text,encoding='utf-8')
print('CV_ADMIN_MESOCYCLE_INTELLIGENCE_V85_PATCHED')
