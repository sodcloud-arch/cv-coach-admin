from pathlib import Path
import re
import subprocess
import sys

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

# Historical internal notification routing did not include /routine even though
# program_published notifications already use it. Align in-app and push routing.
old_routes="const routes={'/':'home','/progress':'progress','/progress/missions':'missions','/progress/achievements':'achievements'};"
new_routes="const routes={'/':'home','/routine':'routine','/progress':'progress','/progress/missions':'missions','/progress/achievements':'achievements'};"
if old_routes in text:
    text=text.replace(old_routes,new_routes,1)
elif new_routes not in text:
    raise SystemExit('V101 notification route map target missing')

if '</body>' not in text:
    raise SystemExit('V101 body injection target missing')
payload=f'\n{MARKER}\n{SCRIPT}\n'
text=text.replace('</body>',payload+'</body>',1)

for token in [MARKER,SCRIPT,'cvNotificationButton','serviceWorker',new_routes]:
    if token not in text:
        raise SystemExit(f'V101 client contract missing: {token}')
if text.count('./assets/cv-push-v101.js') != 1:
    raise SystemExit('V101 push asset must be injected exactly once')

HTML.write_text(text,encoding='utf-8')
print('CV_CLIENT_PUSH_V101_PATCHED')

# V102 is intentionally chained after V101 so the existing production build
# can carry the opt-in mobile exercise experiment without replacing older logic.
next_upgrade=ROOT/'upgrade_client_v102.py'
if next_upgrade.exists():
    subprocess.run([sys.executable,str(next_upgrade)],check=True)
