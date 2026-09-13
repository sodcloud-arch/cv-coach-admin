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

function rectClose(a,b,tolerance=0.75){
  if(!a||!b)return false;
  return ['x','y','width','height'].every(k=>Math.abs(Number(a[k])-Number(b[k]))<=tolerance);
}

async function tap(page,locator,label='target'){
  await locator.waitFor({state:'visible',timeout:15000});
  let lastDiagnostic=null;

  for(let attempt=0;attempt<4;attempt++){
    const token=`cv-canary-${label}-${Date.now()}-${attempt}-${Math.random().toString(36).slice(2)}`;
    try{
      await locator.evaluate((el,marker)=>{
        el.setAttribute('data-cv-canary-touch',marker);
        el.scrollIntoView({block:'center',inline:'nearest',behavior:'auto'});
      },token);
    }catch{
      await page.waitForTimeout(80);
      continue;
    }

    const selector=`[data-cv-canary-touch="${token}"]`;
    const deadline=Date.now()+4000;
    let previous=null;
    let stableSamples=0;

    while(Date.now()<deadline){
      const sample=await page.evaluate(({selector})=>{
        const el=document.querySelector(selector);
        if(!el||!el.isConnected)return {connected:false};
        const r=el.getBoundingClientRect();
        const cx=r.left+r.width/2;
        const cy=r.top+r.height/2;
        const hit=document.elementFromPoint(cx,cy);
        const style=getComputedStyle(el);
        return {
          connected:true,
          rect:{x:r.x,y:r.y,width:r.width,height:r.height},
          center:{x:cx,y:cy},
          viewport:{width:window.innerWidth,height:window.innerHeight},
          hitOk:Boolean(hit&&(hit===el||el.contains(hit))),
          text:(el.textContent||'').trim().slice(0,80),
          className:typeof el.className==='string'?el.className:'',
          visibility:style.visibility,
          display:style.display,
          opacity:style.opacity,
          transform:style.transform,
          animationName:style.animationName,
        };
      },{selector}).catch(()=>({connected:false}));

      lastDiagnostic=sample;
      if(!sample.connected)break;
      const r=sample.rect;
      const c=sample.center;
      const inViewport=r.width>=20&&r.height>=20&&c.x>=0&&c.y>=0&&c.x<=sample.viewport.width&&c.y<=sample.viewport.height;
      const visuallyReady=sample.display!=='none'&&sample.visibility!=='hidden'&&Number(sample.opacity)>0;
      if(inViewport&&visuallyReady&&sample.hitOk&&rectClose(previous,r))stableSamples+=1;
      else stableSamples=0;
      previous=r;

      if(stableSamples>=3){
        console.log(`CV_CANARY_V76_TOUCH_READY ${label} ${JSON.stringify({rect:r,hitOk:sample.hitOk,text:sample.text,animationName:sample.animationName,transform:sample.transform})}`);
        await page.touchscreen.tap(c.x,c.y);
        return sample;
      }
      await page.waitForTimeout(80);
    }
    await page.waitForTimeout(100);
  }

  throw new Error(`Raw touch target never became stable/unobstructed (${label}): ${JSON.stringify(lastDiagnostic)}`);
}

async function startWorkoutFromCurrentView(page){
  const deadline=Date.now()+15000;
  while(Date.now()<deadline){
    const candidates=page.locator('button[onclick*="startWorkout"], .cvWorkoutStartV40');
    const count=await candidates.count();
    for(let i=0;i<count;i++){
      const candidate=candidates.nth(i);
      if(await candidate.isVisible().catch(()=>false)){
        await tap(page,candidate,'start-workout');
        console.log('CV_CANARY_V76_START_TOUCH_STABLE');
        return;
      }
    }
    await page.waitForTimeout(250);
  }
  const visibleButtons=await page.locator('button:visible').evaluateAll(nodes=>nodes.slice(0,20).map(node=>({
    text:(node.textContent||'').trim(),
    id:node.id||'',
    className:typeof node.className==='string'?node.className:'',
    onclick:node.getAttribute('onclick')||'',
  })));
  throw new Error(`Workout start control missing; visible_buttons=${JSON.stringify(visibleButtons)}`);
}

async function editNumber(page,selector,value){
  const input=page.locator(selector);
  await tap(page,input,`edit-${selector.replace('#','')}`);
  const panel=page.locator('#cvNumpadV73');
  await panel.waitFor({state:'visible',timeout:10000});
  await tap(page,panel.locator('[data-cv-key="clear"]'),'numpad-clear');
  for(const char of String(value)){
    const key=char==='.'?'dot':char;
    await tap(page,panel.locator(`[data-cv-key="${key}"]`),`numpad-${key}`);
  }
  await tap(page,panel.locator('[data-cv-key="done"]'),'numpad-done');
  await page.waitForFunction(({sel,expected})=>document.querySelector(sel)?.value===expected,{sel:selector,expected:String(value)},{timeout:10000});
}

async function dumpWorkoutDom(page){
  const controls=await page.locator('input,button').evaluateAll(nodes=>nodes.filter(node=>{
    const r=node.getBoundingClientRect();
    const s=getComputedStyle(node);
    return r.width>0&&r.height>0&&s.display!=='none'&&s.visibility!=='hidden';
  }).slice(0,120).map(node=>{
    const owner=node.closest('.cvSetRow,.setRow,[class*="SetRow"],[class*="setRow"],.exerciseCard,[class*="exercise"]');
    return {
      tag:node.tagName,
      id:node.id||'',
      className:typeof node.className==='string'?node.className:'',
      type:node.getAttribute('type')||'',
      inputmode:node.getAttribute('inputmode')||'',
      name:node.getAttribute('name')||'',
      placeholder:node.getAttribute('placeholder')||'',
      readonly:node.hasAttribute('readonly'),
      text:(node.textContent||'').trim().slice(0,80),
      ownerClass:owner&&typeof owner.className==='string'?owner.className:'',
    };
  }));
  console.log('CV_CANARY_V76_WORKOUT_DOM',JSON.stringify(controls));
  return controls;
}

async function athleteRest(accessToken,path){
  if(!accessToken)throw new Error('Athlete access token missing');
  const r=await fetch(`${BASE}/rest/v1/${path}`,{headers:{apikey:KEY,Authorization:`Bearer ${accessToken}`}});
  if(!r.ok)throw new Error(`Athlete REST ${r.status}: ${await r.text()}`);
  return r.json();
}

async function latestActiveSession(accessToken,clientId,timeoutMs=15000){
  const deadline=Date.now()+timeoutMs;
  while(Date.now()<deadline){
    const rows=await athleteRest(accessToken,`workout_sessions?client_id=eq.${encodeURIComponent(clientId)}&status=eq.in_progress&select=id,started_at&order=started_at.desc&limit=1`);
    if(Array.isArray(rows)&&rows.length===1)return rows[0];
    await new Promise(r=>setTimeout(r,500));
  }
  throw new Error('Expected one active session but none became visible');
}

async function waitSetPersisted(accessToken,sessionId){
  const deadline=Date.now()+15000;
  while(Date.now()<deadline){
    const exercises=await athleteRest(accessToken,`session_exercises?workout_session_id=eq.${sessionId}&select=id`);
    if(Array.isArray(exercises)&&exercises.length){
      const ids=exercises.map(x=>x.id).join(',');
      const sets=await athleteRest(accessToken,`set_logs?session_exercise_id=in.(${ids})&completed=eq.true&select=id,weight_kg,reps,completed`);
      const hit=(sets||[]).filter(x=>Number(x.weight_kg)===EXPECTED_WEIGHT&&Number(x.reps)===EXPECTED_REPS&&x.completed===true);
      if(hit.length===1)return hit[0];
    }
    await new Promise(r=>setTimeout(r,500));
  }
  throw new Error('Completed canary set was not persisted');
}

async function waitTerminal(accessToken,sessionId){
  const deadline=Date.now()+20000;
  while(Date.now()<deadline){
    const rows=await athleteRest(accessToken,`workout_sessions?id=eq.${sessionId}&select=id,status,completion_pct,finished_at,session_notes`);
    if(rows?.[0]&&rows[0].status!=='in_progress')return rows[0];
    await new Promise(r=>setTimeout(r,700));
  }
  throw new Error('Workout did not reach terminal state');
}

let browser;
let bootstrapped=false;
let verified=false;
let athleteAccessToken=null;
let canaryClientId=null;
let claimedSessionId=null;
let browserDisconnected=false;
let pageClosed=false;
try{
  const bootstrap=await control('bootstrap');
  bootstrapped=true;
  canaryClientId=bootstrap?.client_id||null;
  if(!bootstrap?.token_hash||!canaryClientId)throw new Error('Bootstrap contract incomplete');
  console.log('CV_CANARY_V76_AUTH_CONTROL_OK');

  browser=await webkit.launch({headless:true});
  browser.on('disconnected',()=>{
    browserDisconnected=true;
    console.log('CV_CANARY_V76_BROWSER_DISCONNECTED');
  });
  const context=await browser.newContext({
    ...devices['iPhone 13'],
    locale:'es-CL',
    timezoneId:'America/Santiago',
    serviceWorkers:'block',
  });
  console.log('CV_CANARY_V76_SERVICE_WORKER_ISOLATED');
  const page=await context.newPage();
  const pageErrors=[];
  page.on('pageerror',e=>pageErrors.push(String(e?.message||e)));
  page.on('crash',()=>console.log('CV_CANARY_V76_PAGE_CRASH'));
  page.on('close',()=>{
    pageClosed=true;
    console.log('CV_CANARY_V76_PAGE_CLOSED');
  });

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
    if(error||!data?.session?.access_token)throw new Error(error?.message||'Magic-link verification failed');
    return {user_id:data.user?.id,access_token:data.session.access_token};
  },{base:BASE,key:KEY,tokenHash:bootstrap.token_hash});
  if(loginResult?.user_id!==canaryClientId)throw new Error('Authenticated unexpected canary user');
  athleteAccessToken=loginResult.access_token;
  await page.reload({waitUntil:'domcontentloaded',timeout:30000});
  const routineCta=page.getByRole('button',{name:/VER RUTINA/i}).first();
  await routineCta.waitFor({state:'visible',timeout:30000});
  console.log('CV_CANARY_V76_AUTH_OK');

  await tap(page,routineCta,'open-routine');
  await startWorkoutFromCurrentView(page);

  const active=await latestActiveSession(athleteAccessToken,canaryClientId);
  await control('claim',{session_id:active.id});
  claimedSessionId=active.id;
  console.log('CV_CANARY_V76_SESSION_CLAIMED');

  if(page.isClosed()||pageClosed||browserDisconnected)throw new Error('WebKit closed after workout start');
  await dumpWorkoutDom(page);
  await page.locator('#cvw_0_0').waitFor({state:'visible',timeout:20000});

  await editNumber(page,'#cvw_0_0',EXPECTED_WEIGHT);
  await editNumber(page,'#cvr_0_0',EXPECTED_REPS);
  const check=page.locator('.cvSetCheck').first();
  await tap(page,check,'complete-set');
  await waitSetPersisted(athleteAccessToken,active.id);
  console.log('CV_CANARY_V76_REAL_SET_OK');

  const finish=page.getByRole('button',{name:/FINALIZAR/i}).last();
  await tap(page,finish,'finish-workout');

  await page.locator('#cvFeedbackFinish').waitFor({state:'visible',timeout:10000});
  await page.locator('#cvFeedbackEffort').evaluate(el=>{el.value='6';el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}))});
  await page.locator('#cvFeedbackFatigue').evaluate(el=>{el.value='3';el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}))});
  await page.locator('#cvFeedbackPain').evaluate(el=>{el.value='0';el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}))});
  await page.locator('#cvFeedbackNotes').fill(`CV_CANARY_V76 run=${RUN_ID}`);
  await tap(page,page.locator('#cvFeedbackFinish'),'submit-feedback');

  const terminal=await waitTerminal(athleteAccessToken,active.id);
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
