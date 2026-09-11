from pathlib import Path
import re
import subprocess
import tempfile

HTML = Path('client-portal/stable/index.html')
if not HTML.exists():
    raise SystemExit('stable client artifact missing; build before V58 E2E')
text = HTML.read_text(encoding='utf-8')

required = [
    'cv-client-e2e-v58: executable module interactions + backend rollback contract',
    'cv-client-modules-v57-js',
    "const state={dailyKey:'',dailyLoaded:false,habitLogs:new Map(),nutritionLog:null,missionsLoaded:false,missions:[],photosLoaded:false,photos:[],badgeBusy:false,actionLocks:new Set()}",
    "const key='habit:'+id;if(state.actionLocks.has(key))return false;state.actionLocks.add(key)",
    "finally{state.actionLocks.delete(key)}",
    "const key='nutrition:'+logDay();if(state.actionLocks.has(key))return false;state.actionLocks.add(key)",
    "sb.functions.invoke('log-habit'",
    "sb.functions.invoke('log-nutrition-day'",
    "await Promise.all([loadDaily(true),syncCvState()])",
    "sb.rpc('submit_weekly_checkin',payload)",
    "if(!saved?.id)throw new Error('El servidor no confirmó el check-in.')",
    "risk?.level==='RED'",
    "sb.from('notifications')",
    "sb.from('client_missions')",
    "sb.from('progress_photos')",
    ".eq('id',id).eq('client_id',uid()).select('id,visible_to_coach').maybeSingle()",
]
for fragment in required:
    if fragment not in text:
        raise SystemExit(f'V58 E2E contract missing: {fragment}')

if text.find('cv-client-modules-v57') > text.find('cv-client-e2e-v58'):
    raise SystemExit('V58 gate is not layered after V57')

match = re.search(r'<script id="cv-client-modules-v57-js">(.*?)</script>', text, flags=re.S)
if not match:
    raise SystemExit('V58 could not extract actual V57 runtime')
v57 = match.group(1)

prelude = r'''
const assert = (cond,msg)=>{ if(!cond) throw new Error(msg); };
var window=globalThis;
var mode='real';
var user={id:'client-v58'};
var view='noop';
var data={nutrition:{meal_target:3},habits:[],cv:{current_level:1,total_xp:0,credit_balance:0},days:[],sessions:[]};
var renderCount=0;
var messages=[];
var render=()=>{renderCount++};
var toast=(m)=>{messages.push(String(m))};
var esc=(v)=>String(v??'');
var progressTypes={front:'Frontal'};
var today=()=> '2026-09-11';
var navigator={vibrate:()=>true};
var localStorage={getItem:()=> '1',setItem:()=>{}};
var requestAnimationFrame=()=>{};
var setTimeout=(fn)=>{fn();return 1};

function classList(){return {values:new Set(),toggle(k,on){if(on)this.values.add(k);else this.values.delete(k)},contains(k){return this.values.has(k)},add(k){this.values.add(k)},remove(k){this.values.delete(k)}}}
const badge={textContent:'',classList:classList()};
const mobileBadge={textContent:'',classList:classList()};
var document={
  body:{dataset:{}},
  addEventListener:()=>{},
  getElementById:(id)=>id==='cvNotificationBadge'?badge:null,
  querySelector:(q)=>q==='.cvMobileNotifCountV39'?mobileBadge:null,
  querySelectorAll:()=>[],
  createElement:()=>({className:'',innerHTML:'',dataset:{},classList:classList(),querySelector:()=>null,querySelectorAll:()=>[],appendChild:()=>{},insertAdjacentElement:()=>{}})
};
window.addEventListener=()=>{};
window.nextDay=()=>null;
window.uploadProgressPhoto=undefined;

let invokeCalls=[];
let invokeHandler=async(name,opts)=>({data:{xp_earned:1,credits_earned:0,missions_completed:0,current_level:1},error:null});
let photoUpdateConfirmed=true;
let notificationCount=2;
const rows={
  habit_logs:[{id:'hl1',client_habit_id:'h1',log_date:'2026-09-11',value:2.5,completed:true}],
  nutrition_daily_logs:{id:'n1',log_date:'2026-09-11',adherence_pct:100,meals_completed:3,meal_target_snapshot:3,compliant:true},
  client_cv_state:{client_id:'client-v58',current_level:2,total_xp:35,credit_balance:4},
  client_missions:[
    {id:'m1',mission_name:'Activa',status:'active',progress:1,target:3,created_at:'2026-09-11'},
    {id:'m2',mission_name:'Completada',status:'completed',progress:3,target:3,created_at:'2026-09-10',completed_at:'2026-09-11'}
  ],
  progress_photos:[{id:'p1',photo_type:'front',storage_path:'test.webp',taken_at:'2026-09-11T10:00:00Z',visible_to_coach:true}]
};
function response(q,single=false){
  const t=q.table;
  if(t==='notifications') return {data:q.opts?.head?null:[],count:notificationCount,error:null};
  if(t==='progress_photos' && q.op==='update') return photoUpdateConfirmed?{data:{id:'p1',visible_to_coach:!!q.payload.visible_to_coach},error:null}:{data:null,error:null};
  if(t==='nutrition_daily_logs') return {data:rows[t],error:null};
  if(t==='client_cv_state') return {data:rows[t],error:null};
  return {data:rows[t]||[],error:null};
}
function query(table){
  const q={table,op:'select',payload:null,opts:null,filters:[],select(_fields,opts){this.opts=opts||null;return this},eq(k,v){this.filters.push(['eq',k,v]);return this},is(k,v){this.filters.push(['is',k,v]);return this},order(){return this},limit(){return this},update(payload){this.op='update';this.payload=payload;return this},maybeSingle(){return Promise.resolve(response(this,true))},then(resolve,reject){return Promise.resolve(response(this,false)).then(resolve,reject)}};
  return q;
}
var sb={
  from:(name)=>query(name),
  functions:{invoke:(name,opts)=>{invokeCalls.push([name,opts]);return invokeHandler(name,opts)}},
  storage:{from:()=>({createSignedUrl:async()=>({data:{signedUrl:'https://example.test/test.webp'},error:null})})}
};
'''

tests = r'''
(async()=>{
  assert(window.CVClientModulesV57?.version==='v57','V57 runtime did not initialize');

  // Habit double tap: only one backend invocation while first request is pending.
  let releaseHabit;
  invokeCalls=[];
  invokeHandler=(name,opts)=>new Promise(resolve=>{releaseHabit=()=>resolve({data:{xp_earned:5,current_level:1},error:null})});
  const h1=window.logHabit('h1',2.5,true);
  const h2=window.logHabit('h1',2.5,true);
  assert(await h2===false,'habit duplicate tap was not rejected');
  assert(invokeCalls.length===1 && invokeCalls[0][0]==='log-habit','habit duplicate invoked backend more than once');
  releaseHabit();
  assert(await h1===true,'habit confirmed path failed');
  assert(window.CVClientModulesV57.state.actionLocks.size===0,'habit lock was not released');
  assert(window.CVClientModulesV57.state.habitLogs.get('h1')?.completed===true,'habit hydration did not restore confirmed state');

  // Habit network/backend error: no stuck lock and visible error feedback.
  messages=[];
  invokeHandler=async()=>({data:null,error:{message:'network down'}});
  assert(await window.logHabit('h1',2.5,true)===false,'habit error path reported success');
  assert(window.CVClientModulesV57.state.actionLocks.size===0,'habit error left action locked');
  assert(messages.some(x=>x.includes('network down')),'habit error was not surfaced');

  // Nutrition double tap and confirmed hydration.
  let releaseNutrition;
  invokeCalls=[];
  invokeHandler=(name,opts)=>new Promise(resolve=>{releaseNutrition=()=>resolve({data:{xp_earned:10,current_level:2},error:null})});
  const n1=window.cvLogNutritionMealsV57(3);
  const n2=window.cvLogNutritionMealsV57(3);
  assert(await n2===false,'nutrition duplicate tap was not rejected');
  assert(invokeCalls.length===1 && invokeCalls[0][0]==='log-nutrition-day','nutrition duplicate invoked backend more than once');
  const body=invokeCalls[0][1].body;
  assert(body.meals_completed===3 && body.adherence_pct===100 && body.compliant===true,'nutrition meal conversion is incorrect');
  releaseNutrition();
  assert(await n1===true,'nutrition confirmed path failed');
  assert(window.CVClientModulesV57.state.nutritionLog?.meals_completed===3,'nutrition hydration did not restore confirmed state');
  assert(window.CVClientModulesV57.state.actionLocks.size===0,'nutrition lock was not released');

  // Mission query must preserve full lifecycle, not only active rows.
  await window.CVClientModulesV57.loadMissions(true);
  const missionStatuses=window.CVClientModulesV57.state.missions.map(x=>x.status).sort().join(',');
  assert(missionStatuses==='active,completed','mission lifecycle did not preserve completed history');

  // Notification unread badge state.
  await window.CVClientModulesV57.syncBadge();
  assert(badge.textContent==='2' && mobileBadge.textContent==='2','notification badge did not hydrate unread count');
  notificationCount=0;
  await window.CVClientModulesV57.syncBadge();
  assert(badge.classList.contains('hidden') && mobileBadge.classList.contains('hidden'),'notification zero state did not hide badge');

  // Progress photo privacy requires exact-row confirmation and must release locks on failure.
  view='progress';messages=[];photoUpdateConfirmed=false;
  await window.cvTogglePhotoVisibilityV57('p1',false);
  assert(messages.some(x=>x.includes('No se confirmó el cambio.')),'photo unconfirmed update was not surfaced');
  assert(window.CVClientModulesV57.state.actionLocks.size===0,'photo failure left action locked');
  messages=[];photoUpdateConfirmed=true;
  await window.cvTogglePhotoVisibilityV57('p1',false);
  assert(messages.some(x=>x.includes('privada')),'photo confirmed privacy change lacked success feedback');
  assert(window.CVClientModulesV57.state.actionLocks.size===0,'photo success left action locked');

  // Next-session sequencing contracts.
  data.days=[{id:'d1'},{id:'d2'},{id:'d3'}];
  data.sessions=[{program_day_id:'d2',status:'in_progress'}];
  assert(window.nextDay()?.id==='d2','active workout was not resumed first');
  data.sessions=[{program_day_id:'d2',status:'abandoned'}];
  assert(window.nextDay()?.id==='d2','abandoned day was incorrectly skipped');
  data.sessions=[{program_day_id:'d2',status:'completed'}];
  assert(window.nextDay()?.id==='d3','completed day did not advance sequentially');

  console.log('CV_CLIENT_MODULE_RUNTIME_E2E_V58_OK');
})().catch(err=>{console.error(err.stack||err);process.exit(1)});
'''

with tempfile.TemporaryDirectory() as tmp:
    js = Path(tmp) / 'v58-runtime-e2e.js'
    js.write_text(prelude + '\n' + v57 + '\n' + tests, encoding='utf-8')
    checked = subprocess.run(['node', '--check', str(js)], text=True, capture_output=True)
    if checked.returncode != 0:
        raise SystemExit('V58 runtime E2E syntax failed:\n' + checked.stdout + checked.stderr)
    run = subprocess.run(['node', str(js)], text=True, capture_output=True, timeout=30)
    if run.returncode != 0:
        raise SystemExit('V58 runtime E2E failed:\n' + run.stdout + run.stderr)
    if 'CV_CLIENT_MODULE_RUNTIME_E2E_V58_OK' not in run.stdout:
        raise SystemExit('V58 runtime E2E success marker missing')

print('CV_CLIENT_MODULE_E2E_V58_OK')
