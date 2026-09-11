from pathlib import Path
import json
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

# Regression target: the old final handler referenced helpers from another IIFE.
# Those names may exist elsewhere in the artifact, but the canonical v56 handler
# must not depend on them at all.
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
let workout={dayId:'d1',sessionId:null};
const set={set_log_id:'demo_0_0',set_number:1,weight_kg:null,reps:null,duration_seconds:null,completed:false};
const ex={session_exercise_id:'sx1',prescription_unit:'reps',rest_seconds:90,name:'Hip Thrust',sets:[set]};
global.window={cvExercises:()=>[ex],startWorkout:async()=>{workout.sessionId='demo';return true}};
let savedBody=null,confirm=true;
global.sb={from(table){assert(table==='set_logs','wrong table');return {update(body){savedBody=body;return {eq(){return this},select(){return this},async maybeSingle(){return confirm?{data:{id:'set1'},error:null}:{data:null,error:null}}}},select(){return {eq(){return this},async maybeSingle(){return {data:{id:'set1'},error:null}}}}}}};
'''

node = harness + '\n' + script + r'''
(async()=>{
  let ok=await window.cvToggleSet(0,0);
  assert(ok===true,'demo toggle should succeed');
  assert(workout.sessionId==='demo','demo should auto-start');
  assert(set.completed===true,'demo set should complete');
  assert(set.weight_kg===80&&set.reps===8,'demo performed values should be applied');
  assert(events.at(-1)?.detail?.completed===true,'demo should emit confirmed set-state');
  assert(toasts.length===0,'demo should not show an error toast');

  // Uncheck in demo: same canonical path, no persistence and no false rest.
  ok=await window.cvToggleSet(0,0);
  assert(ok===true&&set.completed===false,'demo uncheck should succeed');
  assert(events.at(-1)?.detail?.completed===false,'demo uncheck should emit set-state false');

  // Real confirmed persistence.
  mode='real';workout={dayId:'d1',sessionId:'s-real'};set.set_log_id='set1';set.completed=false;set.weight_kg=null;set.reps=null;savedBody=null;confirm=true;
  ok=await window.cvToggleSet(0,0);
  assert(ok===true,'real confirmed toggle should succeed');
  assert(set.completed===true,'real set should complete only after confirmed path');
  assert(savedBody?.completed===true&&savedBody?.weight_kg===80&&savedBody?.reps===8,'real persistence body incorrect');
  assert(events.at(-1)?.detail?.completed===true,'real confirmed toggle should emit set-state');

  // Server returns no row: rollback must protect UI/model and return false.
  set.completed=false;set.weight_kg=null;set.reps=null;confirm=false;const beforeEvents=events.length;
  ok=await window.cvToggleSet(0,0);
  assert(ok===false,'unconfirmed real update should fail');
  assert(set.completed===false,'unconfirmed update must rollback completion');
  assert(set.weight_kg===null&&set.reps===null,'unconfirmed update must rollback values');
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
