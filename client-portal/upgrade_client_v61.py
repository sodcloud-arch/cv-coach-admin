from pathlib import Path
import hashlib,json,re

ROOT=Path(__file__).resolve().parent
HTML=ROOT/'stable'/'index.html'
BUILD=ROOT/'stable'/'build.json'
V64_CSS_FILE=ROOT/'assets'/'cv-rank-real-ui-v64.css'
V64_HOTFIX_CSS_FILE=ROOT/'assets'/'cv-rank-real-ui-v64-hotfix.css'
V64_JS_FILE=ROOT/'assets'/'cv-rank-real-ui-v64.js'
V65_CSS_FILE=ROOT/'assets'/'cv-rank-real-ui-v65.css'
V65_JS_FILE=ROOT/'assets'/'cv-rank-real-ui-v65.js'
V66_CSS_FILE=ROOT/'assets'/'cv-rank-celebration-v66.css'
V66_JS_FILE=ROOT/'assets'/'cv-rank-celebration-v66.js'
MARKER='<!-- cv-rank-engine-v61: tutorial-empty + 5-level leagues + legend + global-ranking + challenges -->'
V64='<!-- cv-rank-real-ui-v64: cache-fresh-transparent-badges + next-rank-visibility + routine-rank-hud -->'
V65='<!-- cv-rank-real-ui-v65: uniform-seven-slot-track + empty-tutorial + compact-rank-card -->'
V66='<!-- cv-rank-celebration-v66: one-shot cinematic-level-up + rank-up + legend-unlock -->'

for asset in [V64_CSS_FILE,V64_HOTFIX_CSS_FILE,V64_JS_FILE,V65_CSS_FILE,V65_JS_FILE,V66_CSS_FILE,V66_JS_FILE]:
    if not asset.exists() or asset.stat().st_size<200:
        raise SystemExit(f'CV Rank UI source asset missing: {asset}')

css64=V64_CSS_FILE.read_text(encoding='utf-8')+'\n'+V64_HOTFIX_CSS_FILE.read_text(encoding='utf-8')
js64=V64_JS_FILE.read_text(encoding='utf-8')
css65=V65_CSS_FILE.read_text(encoding='utf-8')
js65=V65_JS_FILE.read_text(encoding='utf-8')
css66=V66_CSS_FILE.read_text(encoding='utf-8')
js66=V66_JS_FILE.read_text(encoding='utf-8')
text=HTML.read_text(encoding='utf-8')
text=re.sub(r'<style id="cv-rank-system-v60-css">.*?</style>','',text,flags=re.S)
text=re.sub(r'<script id="cv-rank-system-v60-js">.*?</script>','',text,flags=re.S)
text=re.sub(r'<style id="cv-rank-real-ui-v63-css">.*?</style>','',text,flags=re.S)
text=re.sub(r'<script id="cv-rank-real-ui-v63-js">.*?</script>','',text,flags=re.S)
text=re.sub(r'<style id="cv-rank-real-ui-v64-css">.*?</style>','',text,flags=re.S)
text=re.sub(r'<script id="cv-rank-real-ui-v64-js">.*?</script>','',text,flags=re.S)
text=re.sub(r'<style id="cv-rank-real-ui-v65-css">.*?</style>','',text,flags=re.S)
text=re.sub(r'<script id="cv-rank-real-ui-v65-js">.*?</script>','',text,flags=re.S)
text=re.sub(r'<style id="cv-rank-celebration-v66-css">.*?</style>','',text,flags=re.S)
text=re.sub(r'<script id="cv-rank-celebration-v66-js">.*?</script>','',text,flags=re.S)
text=re.sub(r'<link[^>]+cv-rank-real-ui-v(?:63|64|65)\.css[^>]*>','',text,flags=re.I)
text=re.sub(r'<script[^>]+cv-rank-real-ui-v(?:63|64|65)\.js[^>]*></script>','',text,flags=re.I)
text=text.replace('<!-- cv-rank-real-ui-v63: approved-transparent-badges + premium-home + rank-state + challenge-teaser -->','')
text=text.replace(V64,'')
text=text.replace(V65,'')
text=text.replace(V66,'')

if MARKER not in text:
    for prerequisite in ['cv-rank-system-v60','cv-client-e2e-v58','cv-coach-client-loop-v59']:
        if prerequisite not in text:
            raise SystemExit(f'CV Rank V61 prerequisite missing: {prerequisite}')
    if '</head>' not in text or '</body>' not in text:
        raise SystemExit('CV Rank V61 HTML anchors missing')
    text=text.replace('</head>','<link rel="stylesheet" href="./assets/cv-rank-v61.css">\n</head>',1)
    text=text.replace('</body>','<script src="./assets/cv-rank-v61.js"></script>\n'+MARKER+'\n</body>',1)

if '</head>' not in text or '</body>' not in text:
    raise SystemExit('CV Rank UI HTML anchors missing')
text=text.replace('</head>',f'<style id="cv-rank-real-ui-v64-css">\n{css64}\n</style>\n<style id="cv-rank-real-ui-v65-css">\n{css65}\n</style>\n<style id="cv-rank-celebration-v66-css">\n{css66}\n</style>\n</head>',1)
text=text.replace('</body>',f'<script id="cv-rank-real-ui-v64-js">\n{js64}\n</script>\n{V64}\n<script id="cv-rank-real-ui-v65-js">\n{js65}\n</script>\n{V65}\n<script id="cv-rank-celebration-v66-js">\n{js66}\n</script>\n{V66}\n</body>',1)

required=[
    MARKER,
    './assets/cv-rank-v61.css',
    './assets/cv-rank-v61.js',
    V64,
    V65,
    V66,
    'cv-rank-real-ui-v64-css',
    'cv-rank-real-ui-v64-js',
    'cv-rank-real-ui-v65-css',
    'cv-rank-real-ui-v65-js',
    'cv-rank-celebration-v66-css',
    'cv-rank-celebration-v66-js',
    'cv-rank-tutorial-v61.webp',
    'cv64WorkoutRankHud',
    'cv65LeagueProgress',
    'CVRankCelebrationV66',
    'get_pending_rank_transition_v66',
    'ack_rank_transition_v66',
    'legend_unlock',
    '?v=64',
    '.cv64CompactPath .cv64Step.next:after'
]
for item in required:
    if item not in text:
        raise SystemExit(f'CV Rank contract missing: {item}')
if 'cv-rank-system-v60-js' in text or 'cv-rank-system-v60-css' in text:
    raise SystemExit('CV Rank V61 failed to retire active V60 runtime')
if 'cv-rank-real-ui-v63-js' in text or 'cv-rank-real-ui-v63-css' in text:
    raise SystemExit('CV Rank UI failed to retire active V63 layer')

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
    'Rank UI polish + routine rank HUD v64',
    'V64 next-rank CSS collision hotfix',
    'Uniform seven-slot rank track + compact rank card v65',
    'Cinematic one-shot Level Up + Rank Up + Legend overlay v66'
]:
    if patch not in patches:
        patches.append(patch)
meta['patches']=patches
BUILD.write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'sha256':sha,'bytes':meta['bytes'],'patches':patches[-10:]},ensure_ascii=False))
