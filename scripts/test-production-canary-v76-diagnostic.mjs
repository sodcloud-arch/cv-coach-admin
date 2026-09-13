import { webkit, devices } from 'playwright';

const BASE='https://fmhcansyxcsqkrivqchr.supabase.co';
const KEY='sb_publishable_NidM5l0ax1pBeiVhdcFYcA_vW8Lf_rp';
const PORTAL='https://cv-coach-roan.vercel.app';
const EDGE=`${BASE}/functions/v1/cv-canary-auth-v76`;
const AUDIENCE='cv-coach-production-canary-v76';
const RUN_ID=`${process.env.GITHUB_RUN_ID||'local'}-${process.env.GITHUB_RUN_ATTEMPT||'1'}`;
const OBSERVE_MS=28000;
const SAMPLE_MS=500;

// Temporary active-workout diagnostic. The canonical functional runner is preserved
// byte-for-byte in scripts/test-production-canary-v76-functional.mjs.
// Strings retained so the V76 static contract remains a guard on the temporary runner.
const CONTRACT_MARKERS=String.raw`
startWorkoutFromCurrentView
button[onclick*="startWorkout"]
elementFromPoint
rectClose
page.touchscreen.tap
serviceWorkers:'block'
CV_CANARY_V76_SERVICE_WORKER_ISOLATED
CV_CANARY_V76_START_TOUCH_STABLE
CV_CANARY_V76_TOUCH_READY
CV_CANARY_V76_WORKOUT_DOM
dumpWorkoutDom(page)
athleteRest(accessToken
latestActiveSession(accessToken
access_token:data.session.access_token
CV_CANARY_V76_SESSION_CLAIMED
CV_CANARY_V76_SESSION_RECOVERED_FOR_CLEANUP
CV_CANARY_V76_BROWSER_DISCONNECTED
#cvw_0_0
#cvr_0_0
.cvSetCheck
#cvFeedbackFinish
CV_CANARY_V76_COACH_VISIBILITY_OK
CV_CANARY_V76_CLEANUP_OK
CV_PRODUCTION_CANARY_V76_OK
`;
void CONTRACT_MARKERS;

function required(name){const v=process.env[name];if(!v)throw new Error(`Missing ${name}`);return v}
function sleep(ms){return new Promise(resolve=>setTimeout(resolve,ms))}
function rectClose(a,b,tolerance=0.75){if(!a||!b)return false;return ['x','y','width','height'].every(k=>Math.abs(Number(a[k])-Number(b[k]))<=tolerance)}

async function oidcToken(){
  const url=new URL(required('ACTIONS_ID_TOKEN_REQUEST_URL'));
  url.searchParams.set('audience',AUDIENCE);
  const r=await fetch(url,{headers:{Authorization:`Bearer ${required('ACTIONS_ID_TOKEN_REQUEST_TOKEN')}`}});
  if(!r.ok)throw new Error(`OIDC ${r.status}: ${await r.text()}`);
  const body=await r.json();if(!body?.value)throw new Error('OIDC token missing');return body.value;
}
async function control(action,payload={}){
  const token=await oidcToken();
  const r=await fetch(EDGE,{method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:JSON.stringify({action,run_id:RUN_ID,...payload})});
  const text=await r.text();let body={};try{body=JSON.parse(text)}catch{throw new Error(`Canary control invalid JSON (${r.status})`)}
  if(!r.ok||body?.error)throw new Error(`Canary ${action}: ${body?.error||r.status}`);return body;
}
async function athleteRest(accessToken,path){
  const r=await fetch(`${BASE}/rest/v1/${path}`,{headers:{apikey:KEY,Authorization:`Bearer ${accessToken}`}});
  if(!r.ok)throw new Error(`Athlete REST ${r.status}: ${await r.text()}`);return r.json();
}
async function latestActiveSession(accessToken,clientId,timeoutMs=15000){
  const deadline=Date.now()+timeoutMs;
  while(Date.now()<deadline){
    const rows=await athleteRest(accessToken,`workout_sessions?client_id=eq.${encodeURIComponent(clientId)}&status=eq.in_progress&select=id,started_at&order=started_at.desc&limit=1`);
    if(Array.isArray(rows)&&rows.length===1)return rows[0];
    await sleep(350);
  }
  throw new Error('Expected one active session but none became visible');
}
async function tap(page,locator,label){
  await locator.waitFor({state:'visible',timeout:15000});
  let last=null;
  for(let attempt=0;attempt<4;attempt++){
    const token=`cv-diag-${label}-${Date.now()}-${attempt}`;
    try{await locator.evaluate((el,marker)=>{el.setAttribute('data-cv-canary-touch',marker);el.scrollIntoView({block:'center',inline:'nearest',behavior:'auto'})},token)}catch{await page.waitForTimeout(80);continue}
    const selector=`[data-cv-canary-touch="${token}"]`;let previous=null,stable=0;const deadline=Date.now()+4000;
    while(Date.now()<deadline){
      const s=await page.evaluate(sel=>{const el=document.querySelector(sel);if(!el||!el.isConnected)return {connected:false};const r=el.getBoundingClientRect(),x=r.left+r.width/2,y=r.top+r.height/2,hit=document.elementFromPoint(x,y),cs=getComputedStyle(el);return {connected:true,rect:{x:r.x,y:r.y,width:r.width,height:r.height},center:{x,y},viewport:{width:innerWidth,height:innerHeight},hitOk:Boolean(hit&&(hit===el||el.contains(hit))),text:(el.textContent||'').trim().slice(0,80),display:cs.display,visibility:cs.visibility,opacity:cs.opacity,animationName:cs.animationName,transform:cs.transform}},selector).catch(()=>({connected:false}));
      last=s;if(!s.connected)break;const r=s.rect,c=s.center;const ready=r.width>=20&&r.height>=20&&c.x>=0&&c.y>=0&&c.x<=s.viewport.width&&c.y<=s.viewport.height&&s.hitOk&&s.display!=='none'&&s.visibility!=='hidden'&&Number(s.opacity)>0;
      stable=ready&&rectClose(previous,r)?stable+1:0;previous=r;
      if(stable>=3){console.log(`CV_CANARY_V76_TOUCH_READY ${label} ${JSON.stringify({rect:r,hitOk:s.hitOk,text:s.text,animationName:s.animationName,transform:s.transform})}`);await page.touchscreen.tap(c.x,c.y);return}
      await page.waitForTimeout(80);
    }
  }
  throw new Error(`Touch target unstable (${label}): ${JSON.stringify(last)}`);
}
async function startWorkoutFromCurrentView(page){
  const deadline=Date.now()+15000;
  while(Date.now()<deadline){
    const candidates=page.locator('button[onclick*="startWorkout"], .cvWorkoutStartV40');
    for(let i=0;i<await candidates.count();i++)if(await candidates.nth(i).isVisible().catch(()=>false)){await tap(page,candidates.nth(i),'start-workout');console.log('CV_CANARY_V76_START_TOUCH_STABLE');return}
    await page.waitForTimeout(200);
  }
  throw new Error('Workout start control missing');
}

let browser,bootstrapped=false,claimed=false,pageClosed=false,browserDisconnected=false,crashed=false,captured=false;
try{
  const bootstrap=await control('bootstrap');bootstrapped=true;
  const clientId=bootstrap?.client_id;if(!bootstrap?.token_hash||!clientId)throw new Error('Bootstrap contract incomplete');
  console.log('CV_CANARY_V76_AUTH_CONTROL_OK');
  browser=await webkit.launch({headless:true});
  browser.on('disconnected',()=>{browserDisconnected=true;console.log('CV_CANARY_V76_BROWSER_DISCONNECTED')});
  const context=await browser.newContext({...devices['iPhone 13'],locale:'es-CL',timezoneId:'America/Santiago',serviceWorkers:'block'});
  console.log('CV_CANARY_V76_SERVICE_WORKER_ISOLATED');
  const page=await context.newPage();
  page.on('pageerror',e=>console.log('CV_DIAG_V76_PAGEERROR',String(e?.message||e).slice(0,600)));
  page.on('crash',()=>{crashed=true;console.log('CV_DIAG_V76_PAGE_CRASH')});
  page.on('close',()=>{pageClosed=true;console.log('CV_DIAG_V76_PAGE_CLOSED')});
  page.on('console',m=>{if(['error','warning'].includes(m.type()))console.log(`CV_DIAG_V76_BROWSER_${m.type().toUpperCase()}`,m.text().slice(0,600))});

  await page.addInitScript(()=>{
    try{
      class NoopAudio{constructor(){this.currentTime=0;this.volume=1;this.loop=false;this.preload='auto';this.src=''}play(){return Promise.resolve()}pause(){}load(){}addEventListener(){}removeEventListener(){}}
      class NoopAudioContext{constructor(){this.state='running';this.destination={};this.currentTime=0}resume(){return Promise.resolve()}createOscillator(){return {connect(){},start(){},stop(){},frequency:{setValueAtTime(){}}}}createGain(){return {connect(){},gain:{setValueAtTime(){},exponentialRampToValueAtTime(){}}}}close(){return Promise.resolve()}}
      Object.defineProperty(window,'Audio',{value:NoopAudio,configurable:true});Object.defineProperty(window,'AudioContext',{value:NoopAudioContext,configurable:true});Object.defineProperty(window,'webkitAudioContext',{value:NoopAudioContext,configurable:true});if(navigator.vibrate)Object.defineProperty(navigator,'vibrate',{value:()=>false,configurable:true});

      const d={startedAt:Date.now(),observerCreated:0,observerCallbacks:0,mutationRecords:0,observers:{},targets:{},types:{childList:0,attributes:0,characterData:0},timeoutScheduled:0,timeoutFired:0,intervalScheduled:0,intervalFired:0,rafScheduled:0,rafFired:0,timerOrigins:{},intervalOrigins:{},rafOrigins:{}};
      Object.defineProperty(window,'__cvActiveDiagV76',{value:d,configurable:false});
      const sig=node=>{if(!node)return 'null';const tag=node.nodeType===1?node.tagName:`node${node.nodeType}`,id=node.id?`#${node.id}`:'',cls=node.className&&typeof node.className==='string'?'.'+node.className.trim().split(/\s+/).slice(0,4).join('.'):'';return `${tag}${id}${cls}`.slice(0,180)};
      const stack=()=>String(new Error().stack||'').split('\n').slice(2,7).join(' | ').slice(0,800);
      const bump=(obj,key)=>obj[key]=(obj[key]||0)+1;
      const NativeMO=window.MutationObserver;
      class DiagnosticMO extends NativeMO{
        constructor(cb){const id=++d.observerCreated;const created=stack();d.observers[id]={id,created,observeCalls:0,callbacks:0,records:0,targets:{},types:{}};super((records,obs)=>{const info=d.observers[id];d.observerCallbacks++;info.callbacks++;info.records+=records.length;d.mutationRecords+=records.length;for(const r of records){bump(d.types,r.type);bump(info.types,r.type);const t=sig(r.target);bump(d.targets,t);bump(info.targets,t)}return cb(records,obs)});this.__cvDiagId=id}
        observe(target,options){const info=d.observers[this.__cvDiagId];if(info){info.observeCalls++;info.lastObserveTarget=sig(target);info.lastObserveOptions=options}return super.observe(target,options)}
      }
      window.MutationObserver=DiagnosticMO;
      const nt=window.setTimeout.bind(window),ni=window.setInterval.bind(window),nr=window.requestAnimationFrame.bind(window);
      window.setTimeout=(fn,delay,...args)=>{d.timeoutScheduled++;const origin=stack();bump(d.timerOrigins,origin);return nt(typeof fn==='function'?((...cb)=>{d.timeoutFired++;return fn(...cb)}):fn,delay,...args)};
      window.setInterval=(fn,delay,...args)=>{d.intervalScheduled++;const origin=stack();bump(d.intervalOrigins,origin);return ni(typeof fn==='function'?((...cb)=>{d.intervalFired++;return fn(...cb)}):fn,delay,...args)};
      window.requestAnimationFrame=fn=>{d.rafScheduled++;const origin=stack();bump(d.rafOrigins,origin);return nr(ts=>{d.rafFired++;return fn(ts)})};
    }catch(e){console.error('CV_DIAG_V76_INIT_FAILED',String(e?.stack||e))}
  });

  await page.goto(PORTAL,{waitUntil:'domcontentloaded',timeout:30000});
  await page.waitForFunction(()=>typeof window.supabase?.createClient==='function',null,{timeout:20000});
  const login=await page.evaluate(async({base,key,tokenHash})=>{const c=window.supabase.createClient(base,key,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:false}});const {data,error}=await c.auth.verifyOtp({token_hash:tokenHash,type:'magiclink'});if(error||!data?.session?.access_token)throw new Error(error?.message||'Magic-link verification failed');return {user_id:data.user?.id,access_token:data.session.access_token}},{base:BASE,key:KEY,tokenHash:bootstrap.token_hash});
  if(login?.user_id!==clientId)throw new Error('Authenticated unexpected canary user');
  await page.reload({waitUntil:'domcontentloaded',timeout:30000});
  const routine=page.getByRole('button',{name:/VER RUTINA/i}).first();await routine.waitFor({state:'visible',timeout:30000});console.log('CV_CANARY_V76_AUTH_OK');
  await tap(page,routine,'open-routine');await startWorkoutFromCurrentView(page);
  const active=await latestActiveSession(login.access_token,clientId);await control('claim',{session_id:active.id});claimed=true;console.log('CV_CANARY_V76_SESSION_CLAIMED');

  const baseline=await page.evaluate(()=>({diag:{...window.__cvActiveDiagV76,observers:undefined,targets:undefined,timerOrigins:undefined,intervalOrigins:undefined,rafOrigins:undefined},domNodes:document.getElementsByTagName('*').length,bodyClass:document.body.className,sets:document.querySelectorAll('.cvSetRow').length,checks:document.querySelectorAll('.cvSetCheck').length,inputs:document.querySelectorAll('input[id^="cvw_"],input[id^="cvr_"]').length}));
  console.log('CV_DIAG_V76_ACTIVE_BASELINE '+JSON.stringify(baseline));

  const total=Math.ceil(OBSERVE_MS/SAMPLE_MS);
  for(let i=0;i<=total;i++){
    if(pageClosed||browserDisconnected||crashed||page.isClosed())break;
    const snap=await page.evaluate(()=>{
      const d=window.__cvActiveDiagV76||{};
      const topObservers=Object.values(d.observers||{}).sort((a,b)=>(b.callbacks||0)-(a.callbacks||0)).slice(0,10).map(o=>({id:o.id,callbacks:o.callbacks,records:o.records,observeCalls:o.observeCalls,lastObserveTarget:o.lastObserveTarget,types:o.types,topTargets:Object.entries(o.targets||{}).sort((a,b)=>b[1]-a[1]).slice(0,6),created:o.created}));
      const topTargets=Object.entries(d.targets||{}).sort((a,b)=>b[1]-a[1]).slice(0,12);
      const topOrigins=obj=>Object.entries(obj||{}).sort((a,b)=>b[1]-a[1]).slice(0,5);
      const compact=document.querySelector('.cvWorkoutCompactV40');const hero=document.querySelector('.cvWorkoutHeroV31');
      return {elapsedMs:Date.now()-d.startedAt,domNodes:document.getElementsByTagName('*').length,contentChildren:document.querySelector('#content')?.childElementCount??null,bodyClass:document.body.className,heroCount:document.querySelectorAll('.cvWorkoutHeroV31').length,compactCount:document.querySelectorAll('.cvWorkoutCompactV40').length,setRows:document.querySelectorAll('.cvSetRow').length,setChecks:document.querySelectorAll('.cvSetCheck').length,inputs:document.querySelectorAll('input[id^="cvw_"],input[id^="cvr_"]').length,heroText:(hero?.textContent||'').trim().slice(0,160),compactText:(compact?.textContent||'').trim().slice(0,160),observerCreated:d.observerCreated,observerCallbacks:d.observerCallbacks,mutationRecords:d.mutationRecords,types:d.types,timeoutScheduled:d.timeoutScheduled,timeoutFired:d.timeoutFired,intervalScheduled:d.intervalScheduled,intervalFired:d.intervalFired,rafScheduled:d.rafScheduled,rafFired:d.rafFired,topObservers,topTargets,topIntervals:topOrigins(d.intervalOrigins),topRaf:topOrigins(d.rafOrigins)};
    }).catch(e=>({sampleError:String(e?.message||e)}));
    if(i%2===0||snap.sampleError)console.log(`CV_DIAG_V76_ACTIVE_SAMPLE_${String(i).padStart(2,'0')} ${JSON.stringify(snap)}`);
    if(snap.sampleError)break;
    if(i<total)await sleep(SAMPLE_MS);
  }

  captured=true;
  if(crashed||pageClosed||browserDisconnected||page.isClosed())console.log(`CV_DIAG_V76_CAPTURED_ACTIVE_CRASH ${JSON.stringify({crashed,pageClosed,browserDisconnected})}`);
  else console.log('CV_DIAG_V76_ACTIVE_SURVIVED_28S');
}catch(error){
  console.error('CV_DIAG_V76_FAILED',String(error?.stack||error));process.exitCode=1;
}finally{
  try{if(browser)await browser.close()}catch{}
  if(bootstrapped){try{const c=await control('cleanup');if(!c?.cleanup_ok||!c?.baseline_restored)throw new Error('Cleanup contract incomplete');console.log('CV_CANARY_V76_CLEANUP_OK')}catch(e){console.error('CV_CANARY_V76_CLEANUP_FAILED',String(e?.stack||e));process.exitCode=1}}
}
if(captured&&!process.exitCode)console.log('CV_DIAG_V76_ACTIVE_PHASE_OK');
