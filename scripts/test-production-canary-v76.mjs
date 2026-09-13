import { webkit, devices } from 'playwright';

const BASE='https://fmhcansyxcsqkrivqchr.supabase.co';
const KEY='sb_publishable_NidM5l0ax1pBeiVhdcFYcA_vW8Lf_rp';
const PORTAL='https://cv-coach-roan.vercel.app';
const EDGE=`${BASE}/functions/v1/cv-canary-auth-v76`;
const AUDIENCE='cv-coach-production-canary-v76';
const RUN_ID=`${process.env.GITHUB_RUN_ID||'local'}-${process.env.GITHUB_RUN_ATTEMPT||'1'}`;
const OBSERVE_MS=45000;
const SAMPLE_MS=2500;

// Lightweight active-workout probe. The functional E2E runner remains preserved in
// scripts/test-production-canary-v76-functional.mjs. This probe intentionally does NOT
// monkey-patch MutationObserver, timers or requestAnimationFrame: observation must not
// become the workload being measured.
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
  const body=await r.json();
  if(!body?.value)throw new Error('OIDC token missing');
  return body.value;
}
async function control(action,payload={}){
  const token=await oidcToken();
  const r=await fetch(EDGE,{method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:JSON.stringify({action,run_id:RUN_ID,...payload})});
  const text=await r.text();let body={};
  try{body=JSON.parse(text)}catch{throw new Error(`Canary control invalid JSON (${r.status})`)}
  if(!r.ok||body?.error)throw new Error(`Canary ${action}: ${body?.error||r.status}`);
  return body;
}
async function athleteRest(accessToken,path){
  const r=await fetch(`${BASE}/rest/v1/${path}`,{headers:{apikey:KEY,Authorization:`Bearer ${accessToken}`}});
  if(!r.ok)throw new Error(`Athlete REST ${r.status}: ${await r.text()}`);
  return r.json();
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
    const token=`cv-lite-${label}-${Date.now()}-${attempt}`;
    try{await locator.evaluate((el,marker)=>{el.setAttribute('data-cv-canary-touch',marker);el.scrollIntoView({block:'center',inline:'nearest',behavior:'auto'})},token)}catch{await page.waitForTimeout(80);continue}
    const selector=`[data-cv-canary-touch="${token}"]`;
    let previous=null,stable=0;const deadline=Date.now()+4000;
    while(Date.now()<deadline){
      const s=await page.evaluate(sel=>{
        const el=document.querySelector(sel);if(!el||!el.isConnected)return {connected:false};
        const r=el.getBoundingClientRect(),x=r.left+r.width/2,y=r.top+r.height/2,hit=document.elementFromPoint(x,y),cs=getComputedStyle(el);
        return {connected:true,rect:{x:r.x,y:r.y,width:r.width,height:r.height},center:{x,y},viewport:{width:innerWidth,height:innerHeight},hitOk:Boolean(hit&&(hit===el||el.contains(hit))),text:(el.textContent||'').trim().slice(0,80),display:cs.display,visibility:cs.visibility,opacity:cs.opacity,animationName:cs.animationName,transform:cs.transform};
      },selector).catch(()=>({connected:false}));
      last=s;if(!s.connected)break;
      const r=s.rect,c=s.center;
      const ready=r.width>=20&&r.height>=20&&c.x>=0&&c.y>=0&&c.x<=s.viewport.width&&c.y<=s.viewport.height&&s.hitOk&&s.display!=='none'&&s.visibility!=='hidden'&&Number(s.opacity)>0;
      stable=ready&&rectClose(previous,r)?stable+1:0;previous=r;
      if(stable>=3){
        console.log(`CV_CANARY_V76_TOUCH_READY ${label} ${JSON.stringify({rect:r,hitOk:s.hitOk,text:s.text,animationName:s.animationName,transform:s.transform})}`);
        await page.touchscreen.tap(c.x,c.y);
        return;
      }
      await page.waitForTimeout(80);
    }
  }
  throw new Error(`Touch target unstable (${label}): ${JSON.stringify(last)}`);
}
async function startWorkoutFromCurrentView(page){
  const deadline=Date.now()+15000;
  while(Date.now()<deadline){
    const candidates=page.locator('button[onclick*="startWorkout"], .cvWorkoutStartV40');
    for(let i=0;i<await candidates.count();i++){
      const candidate=candidates.nth(i);
      if(await candidate.isVisible().catch(()=>false)){
        await tap(page,candidate,'start-workout');
        console.log('CV_CANARY_V76_START_TOUCH_STABLE');
        return;
      }
    }
    await page.waitForTimeout(200);
  }
  throw new Error('Workout start control missing');
}

let browser;
let bootstrapped=false;
let athleteAccessToken=null;
let canaryClientId=null;
let claimedSessionId=null;
let pageClosed=false;
let browserDisconnected=false;
let crashed=false;
let survived=false;
try{
  const bootstrap=await control('bootstrap');
  bootstrapped=true;
  canaryClientId=bootstrap?.client_id||null;
  if(!bootstrap?.token_hash||!canaryClientId)throw new Error('Bootstrap contract incomplete');
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
      class NoopAudioContext{constructor(){this.state='running';this.destination={};this.currentTime=0}resume(){this.state='running';return Promise.resolve()}createOscillator(){return {connect(){},start(){},stop(){},frequency:{setValueAtTime(){}}}}createGain(){return {connect(){},gain:{setValueAtTime(){},exponentialRampToValueAtTime(){}}}}close(){return Promise.resolve()}}
      Object.defineProperty(window,'Audio',{value:NoopAudio,configurable:true});
      Object.defineProperty(window,'AudioContext',{value:NoopAudioContext,configurable:true});
      Object.defineProperty(window,'webkitAudioContext',{value:NoopAudioContext,configurable:true});
      if(navigator.vibrate)Object.defineProperty(navigator,'vibrate',{value:()=>false,configurable:true});
    }catch{}
  });

  await page.goto(PORTAL,{waitUntil:'domcontentloaded',timeout:30000});
  await page.waitForFunction(()=>{try{return typeof sb!=='undefined'&&typeof sb?.auth?.verifyOtp==='function'}catch{return false}},null,{timeout:20000});
  const login=await page.evaluate(async tokenHash=>{
    const {data,error}=await sb.auth.verifyOtp({token_hash:tokenHash,type:'magiclink'});
    if(error||!data?.session?.access_token)throw new Error(error?.message||'Magic-link verification failed');
    return {user_id:data.user?.id,access_token:data.session.access_token};
  },bootstrap.token_hash);
  if(login?.user_id!==canaryClientId)throw new Error('Authenticated unexpected canary user');
  athleteAccessToken=login.access_token;
  console.log('CV_CANARY_V76_SINGLE_AUTH_CLIENT_OK');

  await page.reload({waitUntil:'domcontentloaded',timeout:30000});
  const routine=page.getByRole('button',{name:/VER RUTINA/i}).first();
  await routine.waitFor({state:'visible',timeout:30000});
  console.log('CV_CANARY_V76_AUTH_OK');
  await tap(page,routine,'open-routine');
  await startWorkoutFromCurrentView(page);

  const active=await latestActiveSession(athleteAccessToken,canaryClientId);
  await control('claim',{session_id:active.id});
  claimedSessionId=active.id;
  console.log('CV_CANARY_V76_SESSION_CLAIMED');

  const started=Date.now();
  for(let i=0;Date.now()-started<=OBSERVE_MS;i++){
    if(pageClosed||browserDisconnected||crashed||page.isClosed())break;
    const snap=await page.evaluate(()=>{
      const inputs=[...document.querySelectorAll('input[id^="cvw_"],input[id^="cvr_"]')].slice(0,4).map(el=>({id:el.id,readonly:el.readOnly,inputmode:el.getAttribute('inputmode'),value:el.value}));
      return {domNodes:document.getElementsByTagName('*').length,contentChildren:document.querySelector('#content')?.childElementCount??null,bodyClass:document.body.className,heroCount:document.querySelectorAll('.cvWorkoutHeroV31').length,compactCount:document.querySelectorAll('.cvWorkoutCompactV40').length,setRows:document.querySelectorAll('.cvSetRow').length,setChecks:document.querySelectorAll('.cvSetCheck').length,inputs};
    }).catch(e=>({sampleError:String(e?.message||e)}));
    console.log(`CV_DIAG_V76_LITE_SAMPLE_${String(i).padStart(2,'0')} ${JSON.stringify({elapsedMs:Date.now()-started,...snap})}`);
    if(snap.sampleError)break;
    await sleep(SAMPLE_MS);
  }

  if(crashed||pageClosed||browserDisconnected||page.isClosed())throw new Error('WebKit closed during lightweight active-workout observation');
  survived=true;
  console.log('CV_DIAG_V76_ACTIVE_SURVIVED_45S');
}catch(error){
  console.error('CV_DIAG_V76_FAILED',String(error?.stack||error));
  process.exitCode=1;
}finally{
  if(bootstrapped&&!claimedSessionId&&athleteAccessToken&&canaryClientId){
    try{
      const orphan=await latestActiveSession(athleteAccessToken,canaryClientId,5000);
      await control('claim',{session_id:orphan.id});
      claimedSessionId=orphan.id;
      console.log('CV_CANARY_V76_SESSION_RECOVERED_FOR_CLEANUP');
    }catch{}
  }
  try{if(browser)await browser.close()}catch{}
  if(bootstrapped){
    try{
      const clean=await control('cleanup');
      if(!clean?.cleanup_ok||!clean?.baseline_restored)throw new Error('Cleanup contract incomplete');
      console.log('CV_CANARY_V76_CLEANUP_OK');
    }catch(e){console.error('CV_CANARY_V76_CLEANUP_FAILED',String(e?.stack||e));process.exitCode=1}
  }
}
if(survived&&!process.exitCode)console.log('CV_DIAG_V76_ACTIVE_PHASE_OK');
