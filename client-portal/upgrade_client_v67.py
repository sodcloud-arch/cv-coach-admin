from pathlib import Path
import base64, hashlib, json, re, subprocess

ROOT=Path(__file__).resolve().parent
HTML=ROOT/'stable'/'index.html'
BUILD=ROOT/'stable'/'build.json'
CSS=ROOT/'assets'/'cv-rank-celebration-v67.css'
JS=ROOT/'assets'/'cv-rank-celebration-v66.js'
SOUNDS=ROOT/'assets'/'sounds'
PARTS=[SOUNDS/f'cv-rank-up-v67.part{i}.b64' for i in range(1,5)]
AUDIO=SOUNDS/'cv-rank-up-v67.mp3'
EXPECTED_AUDIO_SHA='ea7bdb79a6230c0fa00c42d0e51bccd9c23fee61a9db94b6afcd8fdaaa92358f'
MARKER='<!-- cv-rank-audio-sync-v67: extracted-rankup-audio + 3.36s-impact-lock -->'
STYLE_ID='cv-rank-celebration-v67-css'

for p in [CSS,JS,*PARTS]:
    if not p.exists() or p.stat().st_size<100:
        raise SystemExit(f'CV Rank V67 source missing: {p}')

raw_b64=''.join(p.read_text(encoding='utf-8').strip() for p in PARTS)
try:
    raw=base64.b64decode(raw_b64,validate=True)
except Exception as exc:
    raise SystemExit(f'CV Rank V67 audio base64 invalid: {exc}')
audio_sha=hashlib.sha256(raw).hexdigest()
if len(raw)<12000 or not raw.startswith(b'ID3') or audio_sha!=EXPECTED_AUDIO_SHA:
    raise SystemExit(f'CV Rank V67 decoded audio contract failed: bytes={len(raw)} sha={audio_sha}')
AUDIO.write_bytes(raw)

subprocess.run(['node','--check',str(JS)],check=True)
css=CSS.read_text(encoding='utf-8')
js=JS.read_text(encoding='utf-8')
for token in ['RANK_UP_AUDIO','cv66Impact','cv-rank-up-v67.mp3']:
    if token not in js:
        raise SystemExit(f'CV Rank V67 JS contract missing: {token}')
if 'RANK_UP_IMPACT=3.36' not in js and 'RANK_UP_IMPACT_SOURCE=3.36' not in js:
    raise SystemExit('CV Rank V67 impact anchor contract missing')
for token in ['cv67OldCharge','cv67OldBurst','cv67NewReveal','cv67ImpactFlash']:
    if token not in css:
        raise SystemExit(f'CV Rank V67 CSS contract missing: {token}')

text=HTML.read_text(encoding='utf-8')
text=re.sub(r'<style id="cv-rank-celebration-v67-css">.*?</style>','',text,flags=re.S)
text=text.replace(MARKER,'')
if '</head>' not in text or '</body>' not in text:
    raise SystemExit('CV Rank V67 HTML anchors missing')
text=text.replace('</head>',f'<style id="{STYLE_ID}">\n{css}\n</style>\n</head>',1)
text=text.replace('</body>',MARKER+'\n</body>',1)

for token in [STYLE_ID,MARKER,'cv-rank-up-v67.mp3','cv67NewReveal']:
    if token not in text:
        raise SystemExit(f'CV Rank V67 final contract missing: {token}')
if 'RANK_UP_IMPACT=3.36' not in text and 'RANK_UP_IMPACT_SOURCE=3.36' not in text:
    raise SystemExit('CV Rank V67 final impact anchor missing')

HTML.write_text(text,encoding='utf-8')
sha=hashlib.sha256(text.encode()).hexdigest()
meta={}
if BUILD.exists():
    try: meta=json.loads(BUILD.read_text(encoding='utf-8'))
    except Exception: meta={}
meta['bytes']=len(text.encode())
meta['sha256']=sha
patches=list(meta.get('patches') or [])
patch='Extracted rank-up sound + frame-locked 3.36s badge swap v67'
if patch not in patches: patches.append(patch)
meta['patches']=patches
BUILD.write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'sha256':sha,'bytes':meta['bytes'],'audio_bytes':AUDIO.stat().st_size,'audio_sha256':audio_sha,'impact_source_seconds':3.36,'patch':patch},ensure_ascii=False))
