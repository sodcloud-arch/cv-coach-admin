from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
HTML=ROOT/'index.html'
MARKER='<!-- cv-admin-communications-adherence-v98 -->'
ASSET='<script src="/admin-assets/cv-communications-adherence-v98.js"></script>'+MARKER

text=HTML.read_text(encoding='utf-8')
if MARKER not in text:
    anchor='</body>'
    if anchor not in text:
        raise SystemExit('Admin V98 requires </body> anchor')
    text=text.replace(anchor,ASSET+anchor,1)

for item in [MARKER,'/admin-assets/cv-communications-adherence-v98.js']:
    if item not in text:
        raise SystemExit(f'Admin V98 contract missing: {item}')

HTML.write_text(text,encoding='utf-8')
print('CV_ADMIN_COMMUNICATIONS_ADHERENCE_V98_PATCHED')
