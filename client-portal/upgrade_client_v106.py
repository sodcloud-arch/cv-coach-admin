from pathlib import Path
import re
import subprocess

ROOT=Path(__file__).resolve().parent
HTML=ROOT/'stable'/'index.html'
ASSET=ROOT/'assets'/'cv-finish-guard-v106.js'
MARKER='<!-- cv-finish-guard-v106: incomplete-session close protection -->'
START='<!-- cv-finish-guard-v106-inline-start -->'
END='<!-- cv-finish-guard-v106-inline-end -->'

for path in [HTML,ASSET]:
    if not path.exists() or path.stat().st_size<500:
        raise SystemExit(f'CV V106 source missing: {path}')

subprocess.run(['node','--check',str(ASSET)],check=True)
asset=ASSET.read_text(encoding='utf-8').strip()
text=HTML.read_text(encoding='utf-8')

text=re.sub(rf'\s*{re.escape(START)}.*?{re.escape(END)}\s*','\n',text,flags=re.S)
text=text.replace(MARKER,'')

for token in [
    'CV_GUIDED_SET_LOGGING_V105_READY',
    'CVGuidedSetLoggingV105',
    'cvWorkoutActiveV40',
    'cvSetRow',
]:
    if token not in text:
        raise SystemExit(f'V106 base contract missing: {token}')

for token in [
    'CV_FINISH_GUARD_V106_READY',
    "const VERSION='106'",
    'cvFinishGuardV106',
    'cvFinishGuardContinueV106',
    'cvFinishGuardConfirmV106',
    'FINALIZAR IGUAL',
]:
    if token not in asset:
        raise SystemExit(f'V106 asset contract missing: {token}')

payload=f'\n{MARKER}\n{START}\n<script>\n{asset}\n</script>\n{END}\n'
if '</body>' not in text:
    raise SystemExit('V106 body injection target missing')
text=text.replace('</body>',payload+'</body>',1)

for token in [MARKER,START,END,'CV_FINISH_GUARD_V106_READY','CVFinishGuardV106']:
    if token not in text:
        raise SystemExit(f'V106 client contract missing: {token}')
if text.count(START)!=1 or text.count(END)!=1:
    raise SystemExit('V106 runtime must be injected exactly once')

HTML.write_text(text,encoding='utf-8')
print('CV_CLIENT_FINISH_GUARD_V106_PATCHED')
