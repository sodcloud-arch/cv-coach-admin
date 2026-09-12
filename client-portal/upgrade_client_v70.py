from pathlib import Path
import hashlib,json,re,subprocess

ROOT=Path(__file__).resolve().parent
HTML=ROOT/'stable'/'index.html'
BUILD=ROOT/'stable'/'build.json'
JS=ROOT/'assets'/'cv-rank-state-guard-v70.js'
MARKER='<!-- cv-rank-state-guard-v70: no-zero-fallback + cached-real-dashboard + derived-next-level -->'
SCRIPT_ID='cv-rank-state-guard-v70-js'

for p in [HTML,JS]:
    if not p.exists() or p.stat().st_size<300:
        raise SystemExit(f'CV Rank V70 source missing: {p}')
subprocess.run(['node','--check',str(JS)],check=True)
js=JS.read_text(encoding='utf-8')
for token in ['CVRankStateGuardV70','get_client_rank_dashboard_v61','cv_rank_dashboard_v70_','Sincronizando progreso','rating_to_next_level']:
    if token not in js:
        raise SystemExit(f'CV Rank V70 JS contract missing: {token}')

text=HTML.read_text(encoding='utf-8')
text=re.sub(r'<script id="cv-rank-state-guard-v70-js">.*?</script>','',text,flags=re.S)
text=text.replace(MARKER,'')
if '</body>' not in text:
    raise SystemExit('CV Rank V70 body anchor missing')
text=text.replace('</body>',f'<script id="{SCRIPT_ID}">\n{js}\n</script>\n{MARKER}\n</body>',1)

for token in [SCRIPT_ID,MARKER,'CVRankStateGuardV70','get_client_rank_dashboard_v61','Sincronizando progreso']:
    if token not in text:
        raise SystemExit(f'CV Rank V70 final contract missing: {token}')
HTML.write_text(text,encoding='utf-8')
sha=hashlib.sha256(text.encode()).hexdigest()
meta={}
if BUILD.exists():
    try: meta=json.loads(BUILD.read_text(encoding='utf-8'))
    except Exception: meta={}
meta['bytes']=len(text.encode())
meta['sha256']=sha
patches=list(meta.get('patches') or [])
patch='Real rank dashboard state guard + zero fallback repair v70'
if patch not in patches: patches.append(patch)
meta['patches']=patches
BUILD.write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'sha256':sha,'bytes':meta['bytes'],'patch':patch},ensure_ascii=False))
