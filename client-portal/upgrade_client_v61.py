from pathlib import Path
import hashlib,json,re

ROOT=Path(__file__).resolve().parent
HTML=ROOT/'stable'/'index.html'
BUILD=ROOT/'stable'/'build.json'
V63_CSS_FILE=ROOT/'assets'/'cv-rank-real-ui-v63.css'
V63_JS_FILE=ROOT/'assets'/'cv-rank-real-ui-v63.js'
MARKER='<!-- cv-rank-engine-v61: tutorial-empty + 5-level leagues + legend + global-ranking + challenges -->'
V63='<!-- cv-rank-real-ui-v63: approved-transparent-badges + premium-home + rank-state + challenge-teaser -->'

for asset in [V63_CSS_FILE,V63_JS_FILE]:
    if not asset.exists() or asset.stat().st_size<200:
        raise SystemExit(f'CV Rank V63 source asset missing: {asset}')

css=V63_CSS_FILE.read_text(encoding='utf-8')
js=V63_JS_FILE.read_text(encoding='utf-8')
text=HTML.read_text(encoding='utf-8')
text=re.sub(r'<style id="cv-rank-system-v60-css">.*?</style>','',text,flags=re.S)
text=re.sub(r'<script id="cv-rank-system-v60-js">.*?</script>','',text,flags=re.S)
text=re.sub(r'<style id="cv-rank-real-ui-v63-css">.*?</style>','',text,flags=re.S)
text=re.sub(r'<script id="cv-rank-real-ui-v63-js">.*?</script>','',text,flags=re.S)
text=re.sub(r'<link[^>]+cv-rank-real-ui-v63\.css[^>]*>','',text,flags=re.I)
text=re.sub(r'<script[^>]+cv-rank-real-ui-v63\.js[^>]*></script>','',text,flags=re.I)
text=text.replace(V63,'')

if MARKER not in text:
    for prerequisite in ['cv-rank-system-v60','cv-client-e2e-v58','cv-coach-client-loop-v59']:
        if prerequisite not in text:
            raise SystemExit(f'CV Rank V61 prerequisite missing: {prerequisite}')
    if '</head>' not in text or '</body>' not in text:
        raise SystemExit('CV Rank V61 HTML anchors missing')
    text=text.replace('</head>','<link rel="stylesheet" href="./assets/cv-rank-v61.css">\n</head>',1)
    text=text.replace('</body>','<script src="./assets/cv-rank-v61.js"></script>\n'+MARKER+'\n</body>',1)

if '</head>' not in text or '</body>' not in text:
    raise SystemExit('CV Rank V63 HTML anchors missing')
text=text.replace('</head>',f'<style id="cv-rank-real-ui-v63-css">\n{css}\n</style>\n</head>',1)
text=text.replace('</body>',f'<script id="cv-rank-real-ui-v63-js">\n{js}\n</script>\n{V63}\n</body>',1)

required=[
    MARKER,
    './assets/cv-rank-v61.css',
    './assets/cv-rank-v61.js',
    V63,
    'cv-rank-real-ui-v63-css',
    'cv-rank-real-ui-v63-js',
    'cv-rank-tutorial-v61.webp'
]
for item in required:
    if item not in text:
        raise SystemExit(f'CV Rank contract missing: {item}')
if 'cv-rank-system-v60-js' in text or 'cv-rank-system-v60-css' in text:
    raise SystemExit('CV Rank V61 failed to retire active V60 runtime')

HTML.write_text(text,encoding='utf-8')
sha=hashlib.sha256(text.encode()).hexdigest()
meta={}
if BUILD.exists():
    try:
        meta=json.loads(BUILD.read_text(encoding='utf-8'))
    except Exception:
        meta={}
meta['bytes']=len(text.encode())
meta['sha256']=sha
patches=list(meta.get('patches') or [])
for patch in [
    'CV Rank Engine v61',
    'Tutorial empty badge slot v61',
    '5-level leagues + Legend v61',
    'Global/league/season ranking UI v61',
    'Challenges + Trophy Room client UI v61',
    'Approved transparent rank badge assets v63',
    'Premium real rank UI v63'
]:
    if patch not in patches:
        patches.append(patch)
meta['patches']=patches
BUILD.write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'sha256':sha,'bytes':meta['bytes'],'patches':patches[-7:]},ensure_ascii=False))
