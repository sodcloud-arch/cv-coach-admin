import { webkit, devices } from 'playwright';

const BASE='https://fmhcansyxcsqkrivqchr.supabase.co';
const KEY='sb_publishable_NidM5l0ax1pBeiVhdcFYcA_vW8Lf_rp';
const PORTAL='https://cv-coach-roan.vercel.app';
const EDGE=`${BASE}/functions/v1/cv-canary-auth-v76`;
const AUDIENCE='cv-coach-production-canary-v76';
const RUN_ID=`${process.env.GITHUB_RUN_ID||'local'}-${process.env.GITHUB_RUN_ATTEMPT||'1'}`;

// Temporary diagnostic. Canonical functional runner is preserved separately.
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
function rectClose(a,b){return Boolean(a&&b)}

function required(name){const v=process.env[name];if(!v)throw new Error(`Missing ${name}`);return v}
async function oidcToken(){
  const url=new URL(required('ACTIONS_ID_TOKEN_REQUEST_URL'));
  url.searchParams.set('audience',AUDIENCE);
  const r=await fetch(url,{headers:{Authorization:`Bearer ${required('ACTIONS_ID_TOKEN_REQUEST_TOKEN')}`}});
  if(!r.ok)throw new Error(`OIDC ${r.status}: ${await r.text()}`);
  const body=await r.json(); if(!body?.value)throw new Error('OIDC token missing'); return body.value;
}
async function control(action,payload={}){
  const token=await oidcToken();
  const r=await fetch(EDGE,{method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:JSON.stringify({action,run_id:RUN_ID,...payload})});
  const text=await r.text(); let body={}; try{body=JSON.parse(text)}catch{throw new Error(`Canary control invalid JSON (${r.status})`)}
  if(!r.ok||body?.error)throw new Error(`Canary ${action}: ${body?.error||r.status}`); return body;
}

function sleep(ms){return new Promise(r=>setTimeout(r,ms))}

let browser; let bootstrapped=false;
try{
  const bootstrap=await control('bootstrap'); bootstrapped=true;
  if(!bootstrap?.token_hash||!bootstrap?.client_id)throw new Error('Bootstrap contract incomplete');
  console.log('CV_CANARY_V76_AUTH_CONTROL_OK');

  browser=await webkit.launch({headless:true});
  browser.on('disconnected',()=>console.log('CV_CANARY_V76_BROWSER_DISCONNECTED'));
  const context=await browser.newContext({...devices['iPhone 13'],locale:'es-CL',timezoneId:'America/Santiago',serviceWorkers:'block'});
  console.log('CV_CANARY_V76_SERVICE_WORKER_ISOLATED');
  const page=await context.newPage();
  page.on('pageerror',e=>console.log('CV_DIAG_V76_PAGEERROR',String(e?.message||e)));
  page.on('crash',()=>console.log('CV_DIAG_V76_PAGE_CRASH'));
  page.on('close',()=>console.log('CV_DIAG_V76_PAGE_CLOSED'));

  await page.addInitScript(()=>{
    try{
      class NoopAudio{play(){return Promise.resolve()} pause(){} load(){} addEventListener(){} removeEventListener(){}}
      class NoopAudioContext{constructor(){this.state='running';this.destination={};this.currentTime=0}resume(){return Promise.resolve()}createOscillator(){return {connect(){},start(){},stop(){},frequency:{setValueAtTime(){}}}}createGain(){return {connect(){},gain:{setValueAtTime(){},exponentialRampToValueAtTime(){}}}}close(){return Promise.resolve()}}
      Object.defineProperty(window,'Audio',{value:NoopAudio,configurable:true});
      Object.defineProperty(window,'AudioContext',{value:NoopAudioContext,configurable:true});
      Object.defineProperty(window,'webkitAudioContext',{value:NoopAudioContext,configurable:true});
      if(navigator.vibrate)Object.defineProperty(navigator,'vibrate',{value:()=>false,configurable:true});
    }catch{}
  });

  await page.goto(PORTAL,{waitUntil:'domcontentloaded',timeout:30000});
  await page.waitForFunction(()=>typeof window.supabase?.createClient==='function',null,{timeout:20000});
  const login=await page.evaluate(async({base,key,tokenHash})=>{
    const c=window.supabase.createClient(base,key,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:false}});
    const {data,error}=await c.auth.verifyOtp({token_hash:tokenHash,type:'magiclink'});
    if(error||!data?.session?.access_token)throw new Error(error?.message||'Magic-link verification failed');
    return {user_id:data.user?.id,access_token:data.session.access_token};
  },{base:BASE,key:KEY,tokenHash:bootstrap.token_hash});
  if(login?.user_id!==bootstrap.client_id)throw new Error('Authenticated unexpected canary user');
  await page.reload({waitUntil:'domcontentloaded',timeout:30000});

  const routine=page.getByRole('button',{name:/VER RUTINA/i}).first();
  await routine.waitFor({state:'visible',timeout:30000});
  console.log('CV_CANARY_V76_AUTH_OK');

  const geom=await routine.evaluate(el=>{
    window.__cvTouchProbe={events:[],openDayCalls:0};
    const record=e=>window.__cvTouchProbe.events.push({type:e.type,isTrusted:e.isTrusted,defaultPrevented:e.defaultPrevented,target:(e.target?.textContent||'').trim().slice(0,50),ts:Math.round(performance.now())});
    for(const type of ['touchstart','touchend','pointerdown','pointerup','mousedown','mouseup','click'])document.addEventListener(type,record,true);
    if(typeof window.openDay==='function'){
      const original=window.openDay;
      window.openDay=function(...args){window.__cvTouchProbe.openDayCalls++;window.__cvTouchProbe.openDayArgs=args;return original.apply(this,args)};
    }
    el.setAttribute('data-cv-canary-touch','routine-probe');
    el.scrollIntoView({block:'center',inline:'nearest',behavior:'auto'});
    const r=el.getBoundingClientRect(); const x=r.left+r.width/2,y=r.top+r.height/2; const hit=document.elementFromPoint(x,y);
    return {x,y,rect:{x:r.x,y:r.y,width:r.width,height:r.height},hitOk:Boolean(hit&&(hit===el||el.contains(hit))),onclick:el.getAttribute('onclick')||'',text:(el.textContent||'').trim()};
  });
  if(!geom.hitOk)throw new Error(`VER RUTINA hit-test failed: ${JSON.stringify(geom)}`);
  console.log('CV_CANARY_V76_TOUCH_READY open-routine '+JSON.stringify(geom));

  await page.touchscreen.tap(geom.x,geom.y);
  await sleep(1200);
  const touchState=await page.evaluate(()=>({probe:window.__cvTouchProbe||null,bodyView:document.body.dataset.cvView||'',startCount:document.querySelectorAll('button[onclick*="startWorkout"], .cvWorkoutStartV40').length,workoutTop:document.querySelectorAll('.workoutTop').length,buttons:[...document.querySelectorAll('button')].filter(b=>{const r=b.getBoundingClientRect();return r.width&&r.height}).slice(0,20).map(b=>({text:(b.textContent||'').trim().slice(0,80),onclick:b.getAttribute('onclick')||'',className:typeof b.className==='string'?b.className:''}))}));
  console.log('CV_DIAG_V76_AFTER_TOUCH '+JSON.stringify(touchState));

  if((touchState.probe?.openDayCalls||0)===0){
    await page.mouse.move(geom.x,geom.y);
    await page.mouse.down();
    await page.mouse.up();
    await sleep(1200);
    const mouseState=await page.evaluate(()=>({probe:window.__cvTouchProbe||null,bodyView:document.body.dataset.cvView||'',startCount:document.querySelectorAll('button[onclick*="startWorkout"], .cvWorkoutStartV40').length,workoutTop:document.querySelectorAll('.workoutTop').length,buttons:[...document.querySelectorAll('button')].filter(b=>{const r=b.getBoundingClientRect();return r.width&&r.height}).slice(0,20).map(b=>({text:(b.textContent||'').trim().slice(0,80),onclick:b.getAttribute('onclick')||'',className:typeof b.className==='string'?b.className:''}))}));
    console.log('CV_DIAG_V76_AFTER_MOUSE_CONTROL '+JSON.stringify(mouseState));
  }
  console.log('CV_DIAG_V76_TOUCH_SEQUENCE_OK');
}catch(error){
  console.error('CV_CANARY_V76_FAILED',String(error?.stack||error)); process.exitCode=1;
}finally{
  try{if(browser)await browser.close()}catch{}
  if(bootstrapped){try{const c=await control('cleanup');if(!c?.cleanup_ok||!c?.baseline_restored)throw new Error('Cleanup contract incomplete');console.log('CV_CANARY_V76_CLEANUP_OK')}catch(e){console.error('CV_CANARY_V76_CLEANUP_FAILED',String(e?.stack||e));process.exitCode=1}}
}
