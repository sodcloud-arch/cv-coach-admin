from pathlib import Path
import re
import subprocess
import tempfile

html = Path('client-portal/stable/index.html')
if not html.exists():
    raise SystemExit('stable client artifact missing; build before V56 set-toggle guard')
text = html.read_text(encoding='utf-8')

required = [
    'cv-set-toggle-runtime-v56',
    'cv-set-toggle-runtime-v56-js',
    "window.CVSetToggleRuntimeV56={version:'v56'",
    'window.cvSetToggleLocksV56',
    'const started=await window.startWorkout()',
    'function parseSet(i,j)',
    'function persistSet(ex,s,body)',
    'function primeDemoSession()',
    'workout.liveExercises=seed',
    "if(demoPrimed&&typeof window.render==='function')window.render()",
    ".update(body).eq('id',s.set_log_id).select('id').maybeSingle()",
    "throw new Error('set update was not confirmed')",
    "document.dispatchEvent(new CustomEvent('cv:set-state'",
]
for item in required:
    if item not in text:
        raise SystemExit(f'V56 set-toggle contract missing: {item}')

match = re.search(r'<script id="cv-set-toggle-runtime-v56-js">(.*?)</script>', text, flags=re.S)
if not match:
    raise SystemExit('V56 runtime script missing')
script = match.group(1)

handler_match = re.search(r'window\.cvToggleSet=async function\(i,j\)\{(.*?)\n  \};', script, flags=re.S)
if not handler_match:
    raise SystemExit('V56 canonical toggle handler missing')
handler = handler_match.group(1)
for forbidden in ['cvSetFromInputs(', 'cvPersistSetLogV51(', 'startRest(']:
    if forbidden in handler:
        raise SystemExit(f'V56 hidden-scope dependency remained: {forbidden}')

harness = r'''
const assert=(ok,msg)=>{if(!ok)throw new Error(msg)};
class CL{constructor(){this.s=new Set()}add(...x){x.forEach(v=>this.s.add(v))}remove(...x){x.forEach(v=>this.s.delete(v))}toggle(x,on){if(on===undefined){this.s.has(x)?this.s.delete(x):this.s.add(x);return this.s.has(x)}on?this.s.add(x):this.s.delete(x);return !!on}contains(x){return this.s.has(x)}}
const button={classList:new CL(),attrs:{},setAttribute(k,v){this.attrs[k]=v}};
const row={classList:new CL(),querySelector(sel){return sel==='.cvSetCheck'?button:null}};
const weight={value:'80',closest(){return row}},reps={value:'8',closest(){return row}};
const elements={'cvw_0_0':weight,'cvr_0_0':reps};
const events=[];
global.CustomEvent=class{constructor(type,init){this.type=type;this.detail=init?.detail}};
global.document={getElementById(id){return elements[id]||null},querySelectorAll(){return []},dispatchEvent(ev){events.push(ev);return true}};
global.navigator={};
const toasts=[];global.toast=m=>toasts.push(String(m));
let mode='demo';
let workout={dayId:'d1',sessionId:null,liveExercises:null,started:null};
function freshExercise(){return {session_exercise_id:'sx1',prescription_unit:'reps',rest_seconds:90,name:'Hip Thrust',sets:[{set_log_id:null,set_number:1,weight_kg:null,reps:null,duration_seconds:null,completed:false}]}}
let prestartCalls=0,startCalls=0,renderCalls=0;
global.window={
  cvExercises:()=>workout.liveExercises||(prestartCalls++,[freshExercise()]),
  startWorkout:async()=>{startCalls++;workout.sessionId='demo';workout.started=Date.now();workout.liveExercises=[freshExercise()];return true},
  render:()=>{renderCalls++;return true}
};
let savedBody=null,confirm=true;
global.sb={from(table){assert(table==='set_logs','wrong table');return {update(body){savedBody=body;return {eq(){return this},select(){return this},async maybeSingle(){return confirm?{data:{id:'set1'},error:null}:{data:null,error:null}}}},select(){return {eq(){return this},async maybeSingle(){return {data:{id:'set1'},error:null}}}}}}};
'''

node = harness + '\n' + script + r'''
(async()=>{
  let ok=await window.cvToggleSet(0,0);
  const demoSet=workout.liveExercises?.[0]?.sets?.[0];
  assert(ok===true,'demo toggle should succeed');
  assert(workout.sessionId==='demo','demo should be promoted to an active session');
  assert(startCalls===0,'demo set tap must not rebuild the session through async startWorkout');
  assert(prestartCalls===1,'demo prestart model must be captured exactly once');
  assert(renderCalls===1,'demo promotion should render once after the confirmed model mutation');
  assert(demoSet?.completed===true,'demo set should complete on the promoted live model');
  assert(demoSet?.weight_kg===80&&demoSet?.reps===8,'demo performed values should be applied');
  assert(events.at(-1)?.detail?.completed===true,'demo should emit confirmed set-state');
  assert(toasts.length===0,'demo should not show an error toast');

  ok=await window.cvToggleSet(0,0);
  assert(ok===true&&demoSet.completed===false,'demo uncheck should succeed');
  assert(events.at(-1)?.detail?.completed===false,'demo uncheck should emit set-state false');
  assert(renderCalls===1,'already-started demo should not need another promotion render');

  mode='real';workout={dayId:'d1',sessionId:'s-real',liveExercises:[freshExercise()]};const realSet=workout.liveExercises[0].sets[0];realSet.set_log_id='set1';savedBody=null;confirm=true;
  ok=await window.cvToggleSet(0,0);
  assert(ok===true,'real confirmed toggle should succeed');
  assert(realSet.completed===true,'real set should complete only after confirmed path');
  assert(savedBody?.completed===true&&savedBody?.weight_kg===80&&savedBody?.reps===8,'real persistence body incorrect');
  assert(events.at(-1)?.detail?.completed===true,'real confirmed toggle should emit set-state');

  realSet.completed=false;realSet.weight_kg=null;realSet.reps=null;confirm=false;const beforeEvents=events.length;
  ok=await window.cvToggleSet(0,0);
  assert(ok===false,'unconfirmed real update should fail');
  assert(realSet.completed===false,'unconfirmed update must rollback completion');
  assert(realSet.weight_kg===null&&realSet.reps===null,'unconfirmed update must rollback values');
  assert(events.length===beforeEvents,'failed update must not emit success event');
  assert(toasts.at(-1)?.includes('No pude confirmar'),'failure should be visible to athlete');
  console.log('CV_SET_TOGGLE_RUNTIME_V56_NODE_OK');
})().catch(error=>{console.error(error.stack||error);process.exit(1)});
'''

with tempfile.NamedTemporaryFile('w', suffix='.js', delete=False, encoding='utf-8') as f:
    f.write(node)
    path = f.name
proc = subprocess.run(['node', path], capture_output=True, text=True)
if proc.returncode != 0:
    raise SystemExit((proc.stdout + '\n' + proc.stderr).strip())
if 'CV_SET_TOGGLE_RUNTIME_V56_NODE_OK' not in proc.stdout:
    raise SystemExit('V56 node runtime confirmation missing')
print('CV_SET_TOGGLE_RUNTIME_V56_OK')
