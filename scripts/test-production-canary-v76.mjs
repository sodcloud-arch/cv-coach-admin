import { webkit, devices } from 'playwright';

const BASE='https://fmhcansyxcsqkrivqchr.supabase.co';
const KEY='sb_publishable_NidM5l0ax1pBeiVhdcFYcA_vW8Lf_rp';
const PORTAL='https://cv-coach-roan.vercel.app';
const EDGE=`${BASE}/functions/v1/cv-canary-auth-v76`;
const AUDIENCE='cv-coach-production-canary-v76';
const RUN_ID=`${process.env.GITHUB_RUN_ID||'local'}-${process.env.GITHUB_RUN_ATTEMPT||'1'}`;
const EXPECTED_WEIGHT=1;
const EXPECTED_REPS=1;

function required(name){const v=process.env[name];if(!v)throw new Error(`Missing ${name}`);return v}

async function oidcToken(){
  const requestToken=required('ACTIONS_ID_TOKEN_REQUEST_TOKEN');
  const rawUrl=required('ACTIONS_ID_TOKEN_REQUEST_URL');
  const url=new URL(rawUrl);
  url.searchParams.set('audience',AUDIENCE);
  const r=await fetch(url,{headers:{Authorization:`Bearer ${requestToken}`}});
  if(!r.ok)throw new Error(`OIDC ${r.status}: ${await r.text()}`);
  const body=await r.json();
  if(!body?.value)throw new Error('OIDC token missing');
  return body.value;
}

async function control(action,payload={}){
  const token=await oidcToken();
  const r=await fetch(EDGE,{
    method:'POST',
    headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},
    body:JSON.stringify({action,run_id:RUN_ID,...payload}),
  });
  const text=await r.text();
  let body={};
  try{body=JSON.parse(text)}catch{throw new Error(`Canary control invalid JSON (${r.status})`)}
  if(!r.ok||body?.error)throw new Error(`Canary ${action}: ${body?.error||r.status}`);
  return body;
}

async function tap(page,locator){
  await locator.waitFor({state:'visible',timeout:15000});
  await locator.scrollIntoViewIfNeeded();
  const box=await locator.boundingBox();
  if(!box)throw new Error('Touch target has no bounding box');
  await page.touchscreen.tap(box.x+box.width/2,box.y+box.height/2);
}

async function editNumber(page,selector,value){
  const input=page.locator(selector);
  await tap(page,input);
  const panel=page.locator('#cvNumpadV73');
  await panel.waitFor({state:'visible',timeout:10000});
  await tap(page,panel.locator('[data-cv-key="clear"]'));
  for(const char of String(value)){
    const key=char==='.'?'dot':char;
    await tap(page,panel.locator(`[data-cv-key="${key}"]`));
  }
  await tap(page,panel.locator('[data-cv-key="done"]'));
  await page.waitForFunction(({sel,expected})=>document.querySelector(sel)?.value===expected,{sel:selector,expected:String(value)},{timeout:10000});
}

async function athleteAuth(page){
  return page.evaluate(async({base,key})=>{
    const c=window.supabase.createClient(base,key,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:false}});
    const {data,error}=await c.auth.getSession();
    if(error||!data?.session?.access_token)throw new Error(error?.message||'Athlete session missing');
    return {access_token:data.session.access_token,user_id:data.session.user.id};
  },{base:BASE,key:KEY});
}

async function athleteRest(page,path){
  const auth=await athleteAuth(page);
  const r=await fetch(`${BASE}/rest/v1/${path}`,{headers:{apikey:KEY,Authorization:`Bearer ${auth.access_token}`}});
  if(!r.ok)throw new Error(`Athlete REST ${r.status}: ${await r.text()}`);
  return r.json();
}

async function latestActiveSession(page,clientId){
  const rows=await athleteRest(page,`workout_sessions?client_id=eq.${encodeURIComponent(clientId)}&status=eq.in_progress&select=id,started_at&order=started_at.desc&limit=1`);
  if(!Array.isArray(rows)||rows.length!==1)throw new Error(`Expected one active session, got ${Array.isArray(rows)?rows.length:'invalid'}`);
  return rows[0];
}

async function waitSetPersisted(page,sessionId){
  const deadline=Date.now()+15000;
  while(Date.now()<deadline){
    const exercises=await athleteRest(page,`session_exercises?workout_session_id=eq.${sessionId}&select=id`);
    if(Array.isArray(exercises)&&exercises.length){
      const ids=exercises.map(x=>x.id).join(',');
      const sets=await athleteRest(page,`set_logs?session_exercise_id=in.(${ids})&completed=eq.true&select=id,weight_kg,reps,completed`);
      const hit=(sets||[]).filter(x=>Number(x.weight_kg)===EXPECTED_WEIGHT&&Number(x.reps)===EXPECTED_REPS&&x.completed===true);
      if(hit.length===1)return hit[0];
    }
    await new Promise(r=>setTimeout(r,500));
  }
  throw new Error('Completed canary set was not persisted');
}

async function waitTerminal(page,sessionId){
  const deadline=Date.now()+20000;
  while(Date.now()<deadline){
    const rows=await athleteRest(page,`workout_sessions?id=eq.${sessionId}&select=id,status,completion_pct,finished_at,session_notes`);
    if(rows?.[0]&&rows[0].status!=='in_progress')return rows[0];
    await new Promise(r=>setTimeout(r,700));
  }
  throw new Error('Workout did not reach terminal state');
}

let browser;
let bootstrapped=false;
let verified=false;
try{
  const bootstrap=await control('bootstrap');
  bootstrapped=true;
  if(!bootstrap?.token_hash||!bootstrap?.client_id)throw new Error('Bootstrap contract incomplete');
  console.log('CV_CANARY_V76_AUTH_CONTROL_OK');

  browser=await webkit.launch({headless:true});
  const context=await browser.newContext({
    ...devices['iPhone 13'],
    locale:'es-CL',
    timezoneId:'America/Santiago',
  });
  const page=await context.newPage();
  const pageErrors=[];
  page.on('pageerror',e=>pageErrors.push(String(e?.message||e)));

  await page.addInitScript(()=>{
    try{
      class NoopAudio{
        constructor(){this.currentTime=0;this.volume=1;this.loop=false;this.preload='auto';this.src='';}
        play(){return Promise.resolve()}
        pause(){}
        load(){}
        addEventListener(){}
        removeEventListener(){}
      }
      class NoopAudioContext{
        constructor(){this.state='running';this.destination={};this.currentTime=0;}
        resume(){this.state='running';return Promise.resolve()}
        createOscillator(){return {connect(){},start(){},stop(){},frequency:{setValueAtTime(){}}}}
        createGain(){return {connect(){},gain:{setValueAtTime(){},exponentialRampToValueAtTime(){}}}}
        close(){return Promise.resolve()}
      }
      Object.defineProperty(window,'Audio',{value:NoopAudio,configurable:true});
      Object.defineProperty(window,'AudioContext',{value:NoopAudioContext,configurable:true});
      Object.defineProperty(window,'webkitAudioContext',{value:NoopAudioContext,configurable:true});
      if(navigator.vibrate)Object.defineProperty(navigator,'vibrate',{value:()=>false,configurable:true});
    }catch{}
  });

  await page.goto(PORTAL,{waitUntil:'domcontentloaded',timeout:30000});
  await page.waitForFunction(()=>typeof window.supabase?.createClient==='function',null,{timeout:20000});
  const loginResult=await page.evaluate(async({base,key,tokenHash})=>{
    const c=window.supabase.createClient(base,key,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:false}});
    const {data,error}=await c.auth.verifyOtp({token_hash:tokenHash,type:'magiclink'});
    if(error||!data?.session)throw new Error(error?.message||'Magic-link verification failed');
    return {user_id:data.user?.id};
  },{base:BASE,key:KEY,tokenHash:bootstrap.token_hash});
  if(loginResult?.user_id!==bootstrap.client_id)throw new Error('Authenticated unexpected canary user');
  await page.reload({waitUntil:'domcontentloaded',timeout:30000});
  await page.getByRole('button',{name:/VER RUTINA/i}).waitFor({state:'visible',timeout:30000});
  console.log('CV_CANARY_V76_AUTH_OK');

  await page.getByRole('button',{name:/VER RUTINA/i}).click();
  const openWorkout=page.getByRole('button',{name:/ABRIR ENTRENAMIENTO/i}).first();
  await openWorkout.waitFor({state:'visible',timeout:15000});
  await openWorkout.click();
  const start=page.getByRole('button',{name:/^INICIAR$/i}).first();
  await start.waitFor({state:'visible',timeout:15000});
  await start.click();

  await page.locator('#cvw_0_0').waitFor({state:'visible',timeout:20000});
  const active=await latestActiveSession(page,bootstrap.client_id);
  await control('claim',{session_id:active.id});
  console.log('CV_CANARY_V76_SESSION_CLAIMED');

  await editNumber(page,'#cvw_0_0',EXPECTED_WEIGHT);
  await editNumber(page,'#cvr_0_0',EXPECTED_REPS);
  const check=page.locator('.cvSetCheck').first();
  await tap(page,check);
  await waitSetPersisted(page,active.id);
  console.log('CV_CANARY_V76_REAL_SET_OK');

  const finish=page.getByRole('button',{name:/FINALIZAR/i}).last();
  await finish.waitFor({state:'visible',timeout:15000});
  await finish.scrollIntoViewIfNeeded();
  await finish.click();

  await page.locator('#cvFeedbackFinish').waitFor({state:'visible',timeout:10000});
  await page.locator('#cvFeedbackEffort').evaluate(el=>{el.value='6';el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}))});
  await page.locator('#cvFeedbackFatigue').evaluate(el=>{el.value='3';el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}))});
  await page.locator('#cvFeedbackPain').evaluate(el=>{el.value='0';el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}))});
  await page.locator('#cvFeedbackNotes').fill(`CV_CANARY_V76 run=${RUN_ID}`);
  await page.locator('#cvFeedbackFinish').click();

  const terminal=await waitTerminal(page,active.id);
  if(terminal.status!=='abandoned')throw new Error(`Expected abandoned terminal status, got ${terminal.status}`);
  console.log('CV_CANARY_V76_WORKOUT_OK');

  const verification=await control('verify',{expected_weight:EXPECTED_WEIGHT,expected_reps:EXPECTED_REPS});
  if(!verification?.coach_ficha_visible||!verification?.coach_report_visible||!verification?.state_unchanged)throw new Error('Server verification contract incomplete');
  verified=true;
  console.log('CV_CANARY_V76_COACH_VISIBILITY_OK');
  console.log('CV_CANARY_V76_STATE_ISOLATION_OK');

  if(pageErrors.length)throw new Error(`Production page errors: ${JSON.stringify(pageErrors)}`);
} catch(error){
  console.error('CV_CANARY_V76_FAILED',String(error?.stack||error));
  process.exitCode=1;
} finally {
  try{if(browser)await browser.close()}catch{}
  if(bootstrapped){
    try{
      const cleaned=await control('cleanup');
      if(!cleaned?.cleanup_ok||!cleaned?.baseline_restored)throw new Error('Cleanup contract incomplete');
      console.log('CV_CANARY_V76_CLEANUP_OK');
    }catch(error){
      console.error('CV_CANARY_V76_CLEANUP_FAILED',String(error?.stack||error));
      process.exitCode=1;
    }
  }
}

if(!process.exitCode&&verified)console.log('CV_PRODUCTION_CANARY_V76_OK');
