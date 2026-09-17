from pathlib import Path
import re
import subprocess

ROOT=Path(__file__).resolve().parent
HTML=ROOT/'stable'/'index.html'
ASSET=ROOT/'assets'/'cv-inline-set-entry-v104.js'
MARKER='<!-- cv-inline-set-entry-v104: direct-row-editing -->'
START='<!-- cv-inline-set-entry-v104-inline-start -->'
END='<!-- cv-inline-set-entry-v104-inline-end -->'
V73_MARKER='<!-- cv-workout-numpad-v73: native-keyboard-retired + custom-editor + deterministic-save -->'

for path in [HTML,ASSET]:
    if not path.exists() or path.stat().st_size<500:
        raise SystemExit(f'CV V104 source missing: {path}')

subprocess.run(['node','--check',str(ASSET)],check=True)
asset=ASSET.read_text(encoding='utf-8').strip()
text=HTML.read_text(encoding='utf-8')
text=re.sub(rf'\s*{re.escape(START)}.*?{re.escape(END)}\s*','\n',text,flags=re.S)
text=text.replace(MARKER,'')

for token in ['CV_EXERCISE_DETAILS_V103_READY','V102.2_SELF_CONTAINED_FOCUS','cvw_','cvr_','cvSetRow','CVWorkoutNumpadV73']:
    if token not in text:
        raise SystemExit(f'V104 base contract missing: {token}')
for token in ['CV_INLINE_SET_ENTRY_V104_READY',"const VERSION='104'",'data-cv-inline-set-entry','inputmode','stopPropagation']:
    if token not in asset:
        raise SystemExit(f'V104 asset contract missing: {token}')

# V104 intentionally retires the V73 custom workout editor. The underlying set inputs,
# IDs, change handlers and persistence remain untouched; only the competing keypad
# runtime/CSS is removed so the browser keyboard can edit the existing row directly.
text,n_js=re.subn(r'\s*<script id="cv-workout-numpad-v73-js">.*?</script>\s*','\n',text,count=1,flags=re.S)
text,n_css=re.subn(r'\s*<style id="cv-workout-numpad-v73-css">.*?</style>\s*','\n',text,count=1,flags=re.S)
text=text.replace(V73_MARKER,'')
if n_js!=1 or n_css!=1:
    raise SystemExit(f'V104 could not retire V73 editor cleanly: js={n_js} css={n_css}')
for forbidden in ['CVWorkoutNumpadV73','data-cv-pad-v73','cvPadSheetV73','aria-haspopup=\'dialog\'']:
    if forbidden in text:
        raise SystemExit(f'V73 workout editor survived V104 build: {forbidden}')

payload=f'\n{MARKER}\n{START}\n<script>\n{asset}\n</script>\n{END}\n'
if '</body>' not in text: raise SystemExit('V104 body injection target missing')
text=text.replace('</body>',payload+'</body>',1)
for token in [MARKER,START,END,'CV_INLINE_SET_ENTRY_V104_READY','CVInlineSetEntryV104']:
    if token not in text: raise SystemExit(f'V104 client contract missing: {token}')
if text.count(START)!=1 or text.count(END)!=1: raise SystemExit('V104 runtime must be injected exactly once')
HTML.write_text(text,encoding='utf-8')
print('CV_CLIENT_INLINE_SET_ENTRY_V104_PATCHED')
