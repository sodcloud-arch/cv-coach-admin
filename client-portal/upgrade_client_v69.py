from pathlib import Path
import hashlib,json,re,subprocess

ROOT=Path(__file__).resolve().parent
HTML=ROOT/'stable'/'index.html'
BUILD=ROOT/'stable'/'build.json'
CSS=ROOT/'assets'/'cv-rank-stability-v69.css'
JS=ROOT/'assets'/'cv-runtime-stability-v69.js'
RANK_STATE_JS=ROOT/'assets'/'cv-rank-state-guard-v70.js'
STYLE_ID='cv-rank-stability-v69-css'
SCRIPT_ID='cv-runtime-stability-v69-js'
RANK_STATE_ID='cv-rank-state-guard-v70-js'
MARKER='<!-- cv-runtime-stability-v69: visual-master-rankup + bounded-workout-start + premium-backdrop -->'
RANK_STATE_MARKER='<!-- cv-rank-state-guard-v70: no-zero-fallback + cached-real-dashboard + derived-next-level -->'

for p in [HTML,CSS,JS,RANK_STATE_JS]:
    if not p.exists() or p.stat().st_size<300:
        raise SystemExit(f'CV V69/V70 source missing: {p}')
subprocess.run(['node','--check',str(JS)],check=True)
subprocess.run(['node','--check',str(RANK_STATE_JS)],check=True)
css=CSS.read_text(encoding='utf-8')
js=JS.read_text(encoding='utf-8')
rank_state_js=RANK_STATE_JS.read_text(encoding='utf-8')
for token in ['cv69Final','cv69Backdrop','cv69EnergyCore','cv69Starting']:
    if token not in css: raise SystemExit(f'V69 CSS token missing: {token}')
for token in ["version:'v69'",'RANK_IMPACT_MS=2480','RANK_FAILSAFE_MS=5200','START_TIMEOUT_MS=11000','recoverActiveWorkout','installStartGuard','cv69Managed']:
    if token not in js: raise SystemExit(f'V69 JS token missing: {token}')
for token in ['CVRankStateGuardV70','get_client_rank_dashboard_v61','cv_rank_dashboard_v70_','Sincronizando progreso']:
    if token not in rank_state_js: raise SystemExit(f'V70 JS token missing: {token}')

text=HTML.read_text(encoding='utf-8')
text=re.sub(r'<style id="cv-rank-stability-v69-css">.*?</style>','',text,flags=re.S)
text=re.sub(r'<script id="cv-runtime-stability-v69-js">.*?</script>','',text,flags=re.S)
text=re.sub(r'<script id="cv-rank-state-guard-v70-js">.*?</script>','',text,flags=re.S)
text=text.replace(MARKER,'').replace(RANK_STATE_MARKER,'')
if '</head>' not in text or '</body>' not in text:
    raise SystemExit('V69 HTML anchors missing')
text=text.replace('</head>',f'<style id="{STYLE_ID}">\n{css}\n</style>\n</head>',1)
text=text.replace('</body>',f'<script id="{SCRIPT_ID}">\n{js}\n</script>\n{MARKER}\n<script id="{RANK_STATE_ID}">\n{rank_state_js}\n</script>\n{RANK_STATE_MARKER}\n</body>',1)
for token in [STYLE_ID,SCRIPT_ID,MARKER,"version:'v69'",'RANK_FAILSAFE_MS=5200','START_TIMEOUT_MS=11000','cv69Backdrop',RANK_STATE_ID,RANK_STATE_MARKER,'CVRankStateGuardV70','Sincronizando progreso']:
    if token not in text: raise SystemExit(f'V69/V70 final token missing: {token}')
HTML.write_text(text,encoding='utf-8')
sha=hashlib.sha256(text.encode()).hexdigest()
meta={}
if BUILD.exists():
    try:meta=json.loads(BUILD.read_text(encoding='utf-8'))
    except Exception:meta={}
meta['bytes']=len(text.encode());meta['sha256']=sha
patches=list(meta.get('patches') or [])
for patch in ['Rank Up visual-master watchdog v69','Rank Up hard final-state failsafe v69','Premium energy backdrop v69','Bounded workout-start guard + active-session recovery v69','Real rank dashboard state guard + zero fallback repair v70']:
    if patch not in patches:patches.append(patch)
meta['patches']=patches
BUILD.write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'sha256':sha,'bytes':meta['bytes'],'patches':patches[-5:]},ensure_ascii=False))
