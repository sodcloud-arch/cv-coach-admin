from pathlib import Path
import hashlib,json,re,subprocess

ROOT=Path(__file__).resolve().parent
HTML=ROOT/'stable'/'index.html'
BUILD=ROOT/'stable'/'build.json'
CSS=ROOT/'assets'/'cv-rank-celebration-v68.css'
JS=ROOT/'assets'/'cv-rank-celebration-v66.js'
MARKER='<!-- cv-rank-cinematic-v68: clean-stage + hybrid-premium-audio + source-clock-impact -->'
STYLE_ID='cv-rank-celebration-v68-css'

for p in [HTML,CSS,JS]:
    if not p.exists() or p.stat().st_size<200:
        raise SystemExit(f'CV Rank V68 source missing: {p}')

subprocess.run(['node','--check',str(JS)],check=True)
css=CSS.read_text(encoding='utf-8')
js=JS.read_text(encoding='utf-8')
for token in [
    "version:'v68'",
    'RANK_UP_START_AT=0.50',
    'RANK_UP_RATE=1.15',
    'RANK_UP_IMPACT_SOURCE=3.36',
    'startCinematicRise',
    'cinematicImpact',
    "classList.add('cv66Impact')"
]:
    if token not in js:
        raise SystemExit(f'CV Rank V68 JS contract missing: {token}')
for token in [
    '.cv66Ascend.rank_up .cv66Brand',
    'display:none!important',
    'cv68OldCharge',
    'cv68CoreBurst',
    'cv68NewReveal',
    'cv68ImpactFlash'
]:
    if token not in css:
        raise SystemExit(f'CV Rank V68 CSS contract missing: {token}')

text=HTML.read_text(encoding='utf-8')
text=re.sub(r'<style id="cv-rank-celebration-v68-css">.*?</style>','',text,flags=re.S)
text=text.replace(MARKER,'')
if '</head>' not in text or '</body>' not in text:
    raise SystemExit('CV Rank V68 HTML anchors missing')
text=text.replace('</head>',f'<style id="{STYLE_ID}">\n{css}\n</style>\n</head>',1)
text=text.replace('</body>',MARKER+'\n</body>',1)

for token in [STYLE_ID,MARKER,"version:'v68'",'RANK_UP_START_AT=0.50','cv68NewReveal']:
    if token not in text:
        raise SystemExit(f'CV Rank V68 final contract missing: {token}')

HTML.write_text(text,encoding='utf-8')
sha=hashlib.sha256(text.encode()).hexdigest()
meta={}
if BUILD.exists():
    try: meta=json.loads(BUILD.read_text(encoding='utf-8'))
    except Exception: meta={}
meta['bytes']=len(text.encode())
meta['sha256']=sha
patches=list(meta.get('patches') or [])
patch='Premium clean Rank Up cinematic + hybrid audio v68'
if patch not in patches: patches.append(patch)
meta['patches']=patches
BUILD.write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'sha256':sha,'bytes':meta['bytes'],'patch':patch},ensure_ascii=False))
