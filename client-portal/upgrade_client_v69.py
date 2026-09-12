from pathlib import Path
import hashlib,json,re,subprocess

ROOT=Path(__file__).resolve().parent
HTML=ROOT/'stable'/'index.html'
BUILD=ROOT/'stable'/'build.json'
CSS=ROOT/'assets'/'cv-rank-stability-v69.css'
JS=ROOT/'assets'/'cv-runtime-stability-v69.js'
RANK_STATE_JS=ROOT/'assets'/'cv-rank-state-guard-v70.js'
WORKOUT_V71_JS=ROOT/'assets'/'cv-workout-controller-v71.js'
KEYBOARD_V72_JS=ROOT/'assets'/'cv-ios-keyboard-v72.js'
STYLE_ID='cv-rank-stability-v69-css'
SCRIPT_ID='cv-runtime-stability-v69-js'
RANK_STATE_ID='cv-rank-state-guard-v70-js'
WORKOUT_V71_ID='cv-workout-controller-v71-js'
KEYBOARD_V72_ID='cv-ios-keyboard-v72-js'
MARKER='<!-- cv-runtime-stability-v69: visual-master-rankup + bounded-workout-start + premium-backdrop -->'
RANK_STATE_MARKER='<!-- cv-rank-state-guard-v70: no-zero-fallback + cached-real-dashboard + derived-next-level -->'
WORKOUT_V71_MARKER='<!-- cv-workout-controller-v71: authoritative-start + demo-safe + input-preservation -->'
KEYBOARD_V72_MARKER='<!-- cv-ios-keyboard-v72: sole-workout-viewport-owner + preserve-scroll + done-key-restore -->'

for p in [HTML,CSS,JS,RANK_STATE_JS,WORKOUT_V71_JS,KEYBOARD_V72_JS]:
    if not p.exists() or p.stat().st_size<300:
        raise SystemExit(f'CV V69-V72 source missing: {p}')
subprocess.run(['node','--check',str(JS)],check=True)
subprocess.run(['node','--check',str(RANK_STATE_JS)],check=True)
subprocess.run(['node','--check',str(WORKOUT_V71_JS)],check=True)
subprocess.run(['node','--check',str(KEYBOARD_V72_JS)],check=True)
css=CSS.read_text(encoding='utf-8')
js=JS.read_text(encoding='utf-8')
rank_state_js=RANK_STATE_JS.read_text(encoding='utf-8')
workout_v71_js=WORKOUT_V71_JS.read_text(encoding='utf-8')
keyboard_v72_js=KEYBOARD_V72_JS.read_text(encoding='utf-8')
for token in ['cv69Final','cv69Backdrop','cv69EnergyCore','cv69Starting']:
    if token not in css: raise SystemExit(f'V69 CSS token missing: {token}')
for token in ["version:'v69'",'RANK_IMPACT_MS=2480','RANK_FAILSAFE_MS=5200','START_TIMEOUT_MS=11000','recoverActiveWorkout','installStartGuard','cv69Managed']:
    if token not in js: raise SystemExit(f'V69 JS token missing: {token}')
for token in ['CVRankStateGuardV70','get_client_rank_dashboard_v61','cv_rank_dashboard_v70_','Sincronizando progreso']:
    if token not in rank_state_js: raise SystemExit(f'V70 JS token missing: {token}')
for token in ['CVWorkoutControllerV71','window.startWorkout=canonicalStart','snapshotInputs','applySnapshot','ensureAuth',"version:'v71'"]:
    if token not in workout_v71_js: raise SystemExit(f'V71 JS token missing: {token}')
# V71 may not own input viewport behavior anymore. V72 is the single owner.
for forbidden in ['cvKeyboardEditingV71',"addEventListener('focusin'",'window.scrollBy({top:dy']:
    if forbidden in workout_v71_js: raise SystemExit(f'V71 competing keyboard policy still present: {forbidden}')
for token in ['CVIOSKeyboardV72',"version:'v72'",'cvKeyboardEditingV72','multiRestore','enterkeyhint']:
    if token not in keyboard_v72_js: raise SystemExit(f'V72 JS token missing: {token}')

text=HTML.read_text(encoding='utf-8')
text=re.sub(r'<style id="cv-rank-stability-v69-css">.*?</style>','',text,flags=re.S)
text=re.sub(r'<script id="cv-runtime-stability-v69-js">.*?</script>','',text,flags=re.S)
text=re.sub(r'<script id="cv-rank-state-guard-v70-js">.*?</script>','',text,flags=re.S)
text=re.sub(r'<script id="cv-workout-controller-v71-js">.*?</script>','',text,flags=re.S)
text=re.sub(r'<script id="cv-ios-keyboard-v72-js">.*?</script>','',text,flags=re.S)
text=text.replace('<!-- cv-workout-controller-v71: authoritative-start + demo-safe + ios-input-stability -->','')
text=text.replace('<!-- cv-ios-keyboard-v72: preserve-scroll + done-key-restore + visual-viewport-stability -->','')
text=text.replace(MARKER,'').replace(RANK_STATE_MARKER,'').replace(WORKOUT_V71_MARKER,'').replace(KEYBOARD_V72_MARKER,'')

# Remove the legacy V40 focus policy at build time. It centered workout inputs on every
# focus and could fight iOS visualViewport while the numeric keyboard opened/closed.
# V72 is the only workout keyboard viewport owner after this point.
legacy_focus="""  document.addEventListener('focusin',event=>{\n    const el=event.target;if(!(el instanceof HTMLInputElement)||!/^cv[wr]_/.test(el.id))return;\n    setTimeout(()=>{const viewport=window.visualViewport?.height||window.innerHeight,rect=el.getBoundingClientRect();if(rect.bottom>viewport-118||rect.top<138)el.scrollIntoView({behavior:'smooth',block:'center'})},180);\n  },true);\n"""
legacy_count=text.count(legacy_focus)
if legacy_count!=1:
    raise SystemExit(f'Expected exactly one legacy workout focus scroll policy, got {legacy_count}')
text=text.replace(legacy_focus,'',1)

if '</head>' not in text or '</body>' not in text:
    raise SystemExit('V69-V72 HTML anchors missing')
text=text.replace('</head>',f'<style id="{STYLE_ID}">\n{css}\n</style>\n</head>',1)
text=text.replace('</body>',f'<script id="{SCRIPT_ID}">\n{js}\n</script>\n{MARKER}\n<script id="{RANK_STATE_ID}">\n{rank_state_js}\n</script>\n{RANK_STATE_MARKER}\n<script id="{WORKOUT_V71_ID}">\n{workout_v71_js}\n</script>\n{WORKOUT_V71_MARKER}\n<script id="{KEYBOARD_V72_ID}">\n{keyboard_v72_js}\n</script>\n{KEYBOARD_V72_MARKER}\n</body>',1)
for token in [STYLE_ID,SCRIPT_ID,MARKER,"version:'v69'",'RANK_FAILSAFE_MS=5200','START_TIMEOUT_MS=11000','cv69Backdrop',RANK_STATE_ID,RANK_STATE_MARKER,'CVRankStateGuardV70','Sincronizando progreso',WORKOUT_V71_ID,WORKOUT_V71_MARKER,'CVWorkoutControllerV71','window.startWorkout=canonicalStart',KEYBOARD_V72_ID,KEYBOARD_V72_MARKER,'CVIOSKeyboardV72',"version:'v72'"]:
    if token not in text: raise SystemExit(f'V69-V72 final token missing: {token}')
if "el.scrollIntoView({behavior:'smooth',block:'center'})},180);" in text:
    raise SystemExit('Legacy workout center-scroll policy still present after V72 build')
# V71 must remain the last authoritative start assignment in the built artifact.
pos_v71=text.rfind('window.startWorkout=canonicalStart')
pos_legacy=max(text.rfind('window.startWorkout=async function'),text.rfind('window.startWorkout=async()=>'),text.rfind('window.startWorkout=guarded'))
if pos_v71<=pos_legacy: raise SystemExit(f'V71 start controller is not authoritative: v71={pos_v71} legacy={pos_legacy}')
# V72 must be injected after V71 so its keyboard restoration is the last input viewport policy.
if text.rfind('CVIOSKeyboardV72')<=text.rfind('CVWorkoutControllerV71'): raise SystemExit('V72 is not injected after V71')
HTML.write_text(text,encoding='utf-8')
sha=hashlib.sha256(text.encode()).hexdigest()
meta={}
if BUILD.exists():
    try:meta=json.loads(BUILD.read_text(encoding='utf-8'))
    except Exception:meta={}
meta['bytes']=len(text.encode());meta['sha256']=sha
patches=list(meta.get('patches') or [])
for patch in ['Rank Up visual-master watchdog v69','Rank Up hard final-state failsafe v69','Premium energy backdrop v69','Bounded workout-start guard + active-session recovery v69','Real rank dashboard state guard + zero fallback repair v70','Authoritative workout start controller + demo-safe start v71','Prestart input preservation v71','iOS Done-key scroll restoration + visual viewport guard v72','Retired legacy V40 input center-scroll policy v72','Retired competing V71 input viewport policy v72']:
    if patch not in patches:patches.append(patch)
meta['patches']=patches
BUILD.write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'sha256':sha,'bytes':meta['bytes'],'patches':patches[-10:]},ensure_ascii=False))
