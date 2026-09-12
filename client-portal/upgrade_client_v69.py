from pathlib import Path
import hashlib,json,re,subprocess

ROOT=Path(__file__).resolve().parent
HTML=ROOT/'stable'/'index.html'
BUILD=ROOT/'stable'/'build.json'
CSS=ROOT/'assets'/'cv-rank-stability-v69.css'
JS=ROOT/'assets'/'cv-runtime-stability-v69.js'
RANK_STATE_JS=ROOT/'assets'/'cv-rank-state-guard-v70.js'
WORKOUT_V71_JS=ROOT/'assets'/'cv-workout-controller-v71.js'
NUMPAD_V73_JS=ROOT/'assets'/'cv-workout-numpad-v73.js'
NUMPAD_V73_CSS=ROOT/'assets'/'cv-workout-numpad-v73.css'
STYLE_ID='cv-rank-stability-v69-css'
SCRIPT_ID='cv-runtime-stability-v69-js'
RANK_STATE_ID='cv-rank-state-guard-v70-js'
WORKOUT_V71_ID='cv-workout-controller-v71-js'
NUMPAD_V73_JS_ID='cv-workout-numpad-v73-js'
NUMPAD_V73_CSS_ID='cv-workout-numpad-v73-css'
MARKER='<!-- cv-runtime-stability-v69: visual-master-rankup + bounded-workout-start + premium-backdrop -->'
RANK_STATE_MARKER='<!-- cv-rank-state-guard-v70: no-zero-fallback + cached-real-dashboard + derived-next-level -->'
WORKOUT_V71_MARKER='<!-- cv-workout-controller-v71: authoritative-start + demo-safe + input-preservation -->'
NUMPAD_V73_MARKER='<!-- cv-workout-numpad-v73: native-keyboard-retired + custom-editor + deterministic-save -->'

for p in [HTML,CSS,JS,RANK_STATE_JS,WORKOUT_V71_JS,NUMPAD_V73_JS,NUMPAD_V73_CSS]:
    if not p.exists() or p.stat().st_size<300:
        raise SystemExit(f'CV V69-V73 source missing: {p}')
subprocess.run(['node','--check',str(JS)],check=True)
subprocess.run(['node','--check',str(RANK_STATE_JS)],check=True)
subprocess.run(['node','--check',str(WORKOUT_V71_JS)],check=True)
subprocess.run(['node','--check',str(NUMPAD_V73_JS)],check=True)
css=CSS.read_text(encoding='utf-8')
js=JS.read_text(encoding='utf-8')
rank_state_js=RANK_STATE_JS.read_text(encoding='utf-8')
workout_v71_js=WORKOUT_V71_JS.read_text(encoding='utf-8')
numpad_v73_js=NUMPAD_V73_JS.read_text(encoding='utf-8')
numpad_v73_css=NUMPAD_V73_CSS.read_text(encoding='utf-8')
for token in ['cv69Final','cv69Backdrop','cv69EnergyCore','cv69Starting']:
    if token not in css: raise SystemExit(f'V69 CSS token missing: {token}')
for token in ["version:'v69'",'RANK_IMPACT_MS=2480','RANK_FAILSAFE_MS=5200','START_TIMEOUT_MS=11000','recoverActiveWorkout','installStartGuard','cv69Managed']:
    if token not in js: raise SystemExit(f'V69 JS token missing: {token}')
for token in ['CVRankStateGuardV70','get_client_rank_dashboard_v61','cv_rank_dashboard_v70_','Sincronizando progreso']:
    if token not in rank_state_js: raise SystemExit(f'V70 JS token missing: {token}')
for token in ['CVWorkoutControllerV71','window.startWorkout=canonicalStart','snapshotInputs','applySnapshot','ensureAuth',"version:'v71'"]:
    if token not in workout_v71_js: raise SystemExit(f'V71 JS token missing: {token}')
for forbidden in ['cvKeyboardEditingV71',"addEventListener('focusin'",'window.scrollBy({top:dy']:
    if forbidden in workout_v71_js: raise SystemExit(f'V71 competing keyboard policy still present: {forbidden}')
for token in ['CVWorkoutNumpadV73',"version:'v73'",'native-keyboard-retired','readonly','inputmode','LISTO ✓']:
    if token not in (numpad_v73_js+'\n'+NUMPAD_V73_MARKER): raise SystemExit(f'V73 numpad contract missing: {token}')
for token in ['cvNumpadV73','cvPadSheetV73','cvPadDoneV73','cvPadEditingV73']:
    if token not in numpad_v73_css: raise SystemExit(f'V73 CSS contract missing: {token}')

text=HTML.read_text(encoding='utf-8')
for pattern in [
    r'<style id="cv-rank-stability-v69-css">.*?</style>',
    r'<script id="cv-runtime-stability-v69-js">.*?</script>',
    r'<script id="cv-rank-state-guard-v70-js">.*?</script>',
    r'<script id="cv-workout-controller-v71-js">.*?</script>',
    r'<script id="cv-ios-keyboard-v72-js">.*?</script>',
    r'<style id="cv-workout-numpad-v73-css">.*?</style>',
    r'<script id="cv-workout-numpad-v73-js">.*?</script>'
]:
    text=re.sub(pattern,'',text,flags=re.S)
for old_marker in [
    '<!-- cv-workout-controller-v71: authoritative-start + demo-safe + ios-input-stability -->',
    '<!-- cv-ios-keyboard-v72: preserve-scroll + done-key-restore + visual-viewport-stability -->',
    '<!-- cv-ios-keyboard-v72: sole-workout-viewport-owner + preserve-scroll + done-key-restore -->'
]:
    text=text.replace(old_marker,'')
text=text.replace(MARKER,'').replace(RANK_STATE_MARKER,'').replace(WORKOUT_V71_MARKER,'').replace(NUMPAD_V73_MARKER,'')

# Retire historical workout-input focus/keyboard policies. V73 never summons the iOS
# keyboard: workout numeric cells are readonly buttons backed by a custom deterministic pad.
legacy_focus="""  document.addEventListener('focusin',event=>{\n    const el=event.target;if(!(el instanceof HTMLInputElement)||!/^cv[wr]_/.test(el.id))return;\n    setTimeout(()=>{const viewport=window.visualViewport?.height||window.innerHeight,rect=el.getBoundingClientRect();if(rect.bottom>viewport-118||rect.top<138)el.scrollIntoView({behavior:'smooth',block:'center'})},180);\n  },true);\n"""
if legacy_focus in text:text=text.replace(legacy_focus,'',1)
# Retire the older v21 workout input focus/Enter navigation handler that can force native focus.
text=re.sub(r"\n\s*document\.addEventListener\('focusin',e=>\{\n\s*const x=e\.target;if\(!\(x instanceof HTMLInputElement\)\|\|!\/\^cv\[wr\]_\/\.test\(x\.id\)\)return;\n\s*x\.classList\.add\('cvInputActive'\);\n\s*setTimeout\(\(\)=>\{try\{x\.select\(\)\}catch\(_\)\{\}\},20\);\n\s*\},true\);\n\s*document\.addEventListener\('focusout',e=>\{\n\s*const x=e\.target;if\(x instanceof HTMLInputElement&&\/\^cv\[wr\]_\/\.test\(x\.id\)\)x\.classList\.remove\('cvInputActive'\);\n\s*\},true\);\n\s*document\.addEventListener\('keydown',e=>\{\n\s*const x=e\.target;if\(!\(x instanceof HTMLInputElement\)\|\|!\/\^cv\[wr\]_\/\.test\(x\.id\)\|\|e\.key!==\'Enter\'\)return;\n\s*e\.preventDefault\(\); const n=nextField\(x\); if\(n\)\{n\.focus\(\);setTimeout\(\(\)=>\{try\{n\.select\(\)\}catch\(_\)\{\}\},20\)\}else\{x\.blur\(\)\}\n\s*\},true\);",'\n',text,flags=re.S)

if '</head>' not in text or '</body>' not in text:
    raise SystemExit('V69-V73 HTML anchors missing')
text=text.replace('</head>',f'<style id="{STYLE_ID}">\n{css}\n</style>\n<style id="{NUMPAD_V73_CSS_ID}">\n{numpad_v73_css}\n</style>\n</head>',1)
text=text.replace('</body>',f'<script id="{SCRIPT_ID}">\n{js}\n</script>\n{MARKER}\n<script id="{RANK_STATE_ID}">\n{rank_state_js}\n</script>\n{RANK_STATE_MARKER}\n<script id="{WORKOUT_V71_ID}">\n{workout_v71_js}\n</script>\n{WORKOUT_V71_MARKER}\n<script id="{NUMPAD_V73_JS_ID}">\n{numpad_v73_js}\n</script>\n{NUMPAD_V73_MARKER}\n</body>',1)
for token in [STYLE_ID,SCRIPT_ID,MARKER,"version:'v69'",'RANK_FAILSAFE_MS=5200','START_TIMEOUT_MS=11000','cv69Backdrop',RANK_STATE_ID,RANK_STATE_MARKER,'CVRankStateGuardV70','Sincronizando progreso',WORKOUT_V71_ID,WORKOUT_V71_MARKER,'CVWorkoutControllerV71','window.startWorkout=canonicalStart',NUMPAD_V73_JS_ID,NUMPAD_V73_CSS_ID,NUMPAD_V73_MARKER,'CVWorkoutNumpadV73',"version:'v73'"]:
    if token not in text: raise SystemExit(f'V69-V73 final token missing: {token}')
for forbidden in [
    "el.scrollIntoView({behavior:'smooth',block:'center'})},180);",
    'CVIOSKeyboardV72',
    'cvKeyboardEditingV72',
    "x.classList.add('cvInputActive')"
]:
    if forbidden in text: raise SystemExit(f'Retired native-keyboard policy survived V73 build: {forbidden}')
# V71 owns start; V73 is injected after it and owns all workout numeric editing.
pos_v71=text.rfind('window.startWorkout=canonicalStart')
pos_legacy=max(text.rfind('window.startWorkout=async function'),text.rfind('window.startWorkout=async()=>'),text.rfind('window.startWorkout=guarded'))
if pos_v71<=pos_legacy: raise SystemExit(f'V71 start controller is not authoritative: v71={pos_v71} legacy={pos_legacy}')
if text.rfind('CVWorkoutNumpadV73')<=text.rfind('CVWorkoutControllerV71'): raise SystemExit('V73 was not injected after V71')
HTML.write_text(text,encoding='utf-8')
sha=hashlib.sha256(text.encode()).hexdigest()
meta={}
if BUILD.exists():
    try:meta=json.loads(BUILD.read_text(encoding='utf-8'))
    except Exception:meta={}
meta['bytes']=len(text.encode());meta['sha256']=sha
patches=list(meta.get('patches') or [])
for patch in ['Rank Up visual-master watchdog v69','Rank Up hard final-state failsafe v69','Premium energy backdrop v69','Bounded workout-start guard + active-session recovery v69','Real rank dashboard state guard + zero fallback repair v70','Authoritative workout start controller + demo-safe start v71','Prestart input preservation v71','Native iOS workout keyboard retired v73','Deterministic custom workout number editor v73','Workout numeric edit/save flow isolation v73']:
    if patch not in patches:patches.append(patch)
meta['patches']=patches
BUILD.write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'sha256':sha,'bytes':meta['bytes'],'patches':patches[-10:]},ensure_ascii=False))
