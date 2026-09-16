from pathlib import Path
import re
import subprocess

ROOT=Path(__file__).resolve().parent
HTML=ROOT/'stable'/'index.html'
ASSET=ROOT/'assets'/'cv-push-v101.js'
MARKER='<!-- cv-client-push-v101: explicit-consent + web-push + preferences -->'
SCRIPT='<script src="./assets/cv-push-v101.js"></script>'

for path in [HTML,ASSET]:
    if not path.exists() or path.stat().st_size < 300:
        raise SystemExit(f'CV V101 source missing: {path}')

subprocess.run(['node','--check',str(ASSET)],check=True)
text=HTML.read_text(encoding='utf-8')
text=re.sub(r'\s*<script src=["\']\./assets/cv-push-v101\.js["\']></script>\s*','\n',text)
text=text.replace(MARKER,'')
if '</body>' not in text:
    raise SystemExit('V101 body injection target missing')
payload=f'\n{MARKER}\n{SCRIPT}\n'
text=text.replace('</body>',payload+'</body>',1)

for token in [MARKER,SCRIPT,'cvNotificationButton','serviceWorker']:
    if token not in text:
        raise SystemExit(f'V101 client contract missing: {token}')
if text.count('./assets/cv-push-v101.js') != 1:
    raise SystemExit('V101 push asset must be injected exactly once')

HTML.write_text(text,encoding='utf-8')
print('CV_CLIENT_PUSH_V101_PATCHED')
