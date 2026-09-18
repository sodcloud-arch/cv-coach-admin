from pathlib import Path
import re
import subprocess

ROOT=Path(__file__).resolve().parent
HTML=ROOT/'stable'/'index.html'
ASSET=ROOT/'assets'/'cv-guided-set-logging-v105.js'
MARKER='<!-- cv-guided-set-logging-v105: current-row + keyboard-flow + readability -->'
START='<!-- cv-guided-set-logging-v105-inline-start -->'
END='<!-- cv-guided-set-logging-v105-inline-end -->'

for path in [HTML,ASSET]:
    if not path.exists() or path.stat().st_size<500:
        raise SystemExit(f'CV V105 source missing: {path}')

subprocess.run(['node','--check',str(ASSET)],check=True)
asset=ASSET.read_text(encoding='utf-8').strip()
text=HTML.read_text(encoding='utf-8')

text=re.sub(rf'\s*{re.escape(START)}.*?{re.escape(END)}\s*','\n',text,flags=re.S)
text=text.replace(MARKER,'')

for token in [
    'CV_INLINE_SET_ENTRY_V104_READY',
    'CV_EXERCISE_DETAILS_V103_READY',
    'cvSetRow',
    'cvSetCheck',
    'cvw_',
    'cvr_',
]:
    if token not in text:
        raise SystemExit(f'V105 base contract missing: {token}')

for token in [
    'CV_GUIDED_SET_LOGGING_V105_READY',
    "const VERSION='105'",
    'cvV105Next',
    'cvV105Active',
    'data-cv-guided-set-logging',
    'aria-label',
    "event.key!=='Enter'",
]:
    if token not in asset:
        raise SystemExit(f'V105 asset contract missing: {token}')

payload=f'\n{MARKER}\n{START}\n<script>\n{asset}\n</script>\n{END}\n'
if '</body>' not in text:
    raise SystemExit('V105 body injection target missing')
text=text.replace('</body>',payload+'</body>',1)

for token in [MARKER,START,END,'CV_GUIDED_SET_LOGGING_V105_READY','CVGuidedSetLoggingV105']:
    if token not in text:
        raise SystemExit(f'V105 client contract missing: {token}')
if text.count(START)!=1 or text.count(END)!=1:
    raise SystemExit('V105 runtime must be injected exactly once')

HTML.write_text(text,encoding='utf-8')
print('CV_CLIENT_GUIDED_SET_LOGGING_V105_PATCHED')
