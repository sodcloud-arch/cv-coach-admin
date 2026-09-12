from pathlib import Path
import hashlib,json,re,subprocess

ROOT=Path(__file__).resolve().parent
HTML=ROOT/'stable'/'index.html'
BUILD=ROOT/'stable'/'build.json'
JS=ROOT/'assets'/'cv-workout-controller-v71.js'
SCRIPT_ID='cv-workout-controller-v71-js'
MARKER='<!-- cv-workout-controller-v71: authoritative-start + demo-safe + ios-input-stability -->'

for p in [HTML,JS]:
    if not p.exists() or p.stat().st_size<500:
        raise SystemExit(f'CV V71 source missing: {p}')
subprocess.run(['node','--check',str(JS)],check=True)
js=JS.read_text(encoding='utf-8')
for token in ["version:'v71'",'window.startWorkout=canonicalStart','snapshotInputs','applySnapshot','ensureAuth','recover(dayId)','cvKeyboardEditingV71']:
    if token not in js: raise SystemExit(f'V71 JS token missing: {token}')

text=HTML.read_text(encoding='utf-8')
text=re.sub(r'<script id="cv-workout-controller-v71-js">.*?</script>','',text,flags=re.S)
text=text.replace(MARKER,'')
if '</body>' not in text: raise SystemExit('V71 HTML anchor missing')
text=text.replace('</body>',f'<script id="{SCRIPT_ID}">\n{js}\n</script>\n{MARKER}\n</body>',1)
for token in [SCRIPT_ID,MARKER,"version:'v71'",'window.startWorkout=canonicalStart','CVWorkoutControllerV71']:
    if token not in text: raise SystemExit(f'V71 final token missing: {token}')
HTML.write_text(text,encoding='utf-8')
sha=hashlib.sha256(text.encode()).hexdigest()
meta={}
if BUILD.exists():
    try:meta=json.loads(BUILD.read_text(encoding='utf-8'))
    except Exception:meta={}
meta['bytes']=len(text.encode());meta['sha256']=sha
patches=list(meta.get('patches') or [])
for patch in ['Authoritative workout start controller v71','Demo synchronous workout start v71','Prestart input snapshot preservation v71','iOS numeric-input viewport stabilization v71']:
    if patch not in patches:patches.append(patch)
meta['patches']=patches
BUILD.write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'sha256':sha,'bytes':meta['bytes'],'patches':patches[-4:]},ensure_ascii=False))
