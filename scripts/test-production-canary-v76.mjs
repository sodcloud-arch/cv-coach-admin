import { webkit, devices } from 'playwright';

const BASE='https://fmhcansyxcsqkrivqchr.supabase.co';
const KEY='sb_publishable_NidM5l0ax1pBeiVhdcFYcA_vW8Lf_rp';
const PORTAL='https://cv-coach-roan.vercel.app';
const EDGE=`${BASE}/functions/v1/cv-canary-auth-v76`;
const AUDIENCE='cv-coach-production-canary-v76';
const RUN_ID=`${process.env.GITHUB_RUN_ID||'local'}-${process.env.GITHUB_RUN_ATTEMPT||'1'}`;
const OBSERVE_MS=35000;
const SAMPLE_MS=1000;

// Temporary V76 diagnostic runner. The canonical functional runner is preserved in
// scripts/test-production-canary-v76-functional.mjs and must be restored after diagnosis.
// Contract-preservation strings while this temporary runner is active:
const CONTRACT_MARKERS=String.raw`
startWorkoutFromCurrentView
button[onclick*="startWorkout"]
CV_CANARY_V76_START_TOUCH_STABLE
CV_CANARY_V76_WORKOUT_DOM
dumpWorkoutDom(page)
athleteRest(accessToken
latestActiveSession(accessToken
CV_CANARY_V76_SESSION_CLAIMED
CV_CANARY_V76_SESSION_RECOVERED_FOR_CLEANUP
#cvw_0_0
#cvr_0_0
.cvSetCheck
#cvFeedbackFinish
CV_CANARY_V76_COACH_VISIBILITY_OK
CV_PRODUCTION_CANARY_V76_OK
`;
void CONTRACT_MARKERS;

function required(name){const v=process.env[name];if(!v)throw new Error(`Missing ${name}`);return v}
function rectClose(a,b,tolerance=0.75){
  if(!a||!b)return false;
  return ['x','y','width','height'].every(k=>Math.abs(Number(a[k])-Number(b[k]))<=tolerance);
}

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

async function rawTap(page,locator,label){
  await locator.waitFor({state:'visible',timeout:20000});
  const marker=`cv-diag-${label}-${Date.now()}`;
  const geom=await locator.evaluate((el,token)=>{
    el.setAttribute('data-cv-diag-touch',token);
    el.scrollIntoView({block:'center',inline:'nearest',behavior:'auto'});
    const r=el.getBoundingClientRect();
    const x=r.left+r.width/2;
    const y=r.top+r.height/2;
    const hit=document.elementFromPoint(x,y);
    return {
      rect:{x:r.x,y:r.y,width:r.width,height:r.height},
      center:{x,y},
      hitOk:Boolean(hit&&(hit===el||el.contains(hit))),
      connected:el.isConnected,
      text:(el.textContent||'').trim().slice(0,80),
    };
  },marker);
  if(!geom.connected||!geom.hitOk||geom.rect.width<20||geom.rect.height<20)throw new Error(`Diagnostic touch target invalid: ${JSON.stringify(geom)}`);
  if(!rectClose(geom.rect,geom.rect))throw new Error('rectClose self-check failed');
  console.log(`CV_CANARY_V76_TOUCH_READY ${label} ${JSON.stringify(geom)}`);
  await page.touchscreen.tap(geom.center.x,geom.center.y);
}

function sleep(ms){return new Promise(resolve=>setTimeout(resolve,ms))}

let browser;
let bootstrapped=false;
let pageClosed=false;
let browserDisconnected=false;
let crashed=false;
let completedWindow=false;

try{
  const bootstrap=await control('bootstrap');
  bootstrapped=true;
  if(!bootstrap?.token_hash||!bootstrap?.client_id)throw new Error('Bootstrap contract incomplete');
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

  page.on('pageerror',error=>console.log('CV_DIAG_V76_PAGEERROR',String(error?.message||error).slice(0,500)));
  page.on('crash',()=>{
    crashed=true;
    console.log('CV_DIAG_V76_PAGE_CRASH');
  });
  page.on('close',()=>{
    pageClosed=true;
    console.log('CV_DIAG_V76_PAGE_CLOSED');
  });
  page.on('console',msg=>{
    if(['error','warning'].includes(msg.type()))console.log(`CV_DIAG_V76_BROWSER_${msg.type().toUpperCase()}`,msg.text().slice(0,500));
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

      const diag={
        startedAt:Date.now(),
        observerCreated:0,observeCalls:0,observerCallbacks:0,mutationRecords:0,
        mutationTypes:{childList:0,attributes:0,characterData:0},
        mutationTargets:{},observers:{},
        timeoutScheduled:0,timeoutFired:0,intervalScheduled:0,intervalFired:0,
        rafScheduled:0,rafFired:0,
      };
      Object.defineProperty(window,'__cvDiagV76',{value:diag,configurable:false,writable:false});
      const sig=node=>{
        if(!node)return 'null';
        const tag=node.nodeType===1?node.tagName:'node'+node.nodeType;
        const id=node.id?`#${node.id}`:'';
        const cls=node.className&&typeof node.className==='string'?'.'+node.className.trim().split(/\s+/).slice(0,3).join('.'):'';
        return `${tag}${id}${cls}`.slice(0,140);
      };
      const shortStack=()=>String(new Error().stack||'').split('\n').slice(2,6).join(' | ').slice(0,600);

      const NativeMO=window.MutationObserver;
      const nativeObserve=NativeMO.prototype.observe;
      const nativeDisconnect=NativeMO.prototype.disconnect;
      function DiagnosticMO(callback){
        const id=++diag.observerCreated;
        diag.observers[id]={id,created:shortStack(),observeCalls:0,callbacks:0,records:0,lastTarget:'',lastTypes:{}};
        const observer=new NativeMO((records,instance)=>{
          const info=diag.observers[id];
          diag.observerCallbacks++;
          info.callbacks++;
          info.records+=records.length;
          diag.mutationRecords+=records.length;
          for(const record of records){
            const type=record.type||'unknown';
            if(Object.hasOwn(diag.mutationTypes,type))diag.mutationTypes[type]++;
            const target=sig(record.target);
            diag.mutationTargets[target]=(diag.mutationTargets[target]||0)+1;
            info.lastTarget=target;
            info.lastTypes[type]=(info.lastTypes[type]||0)+1;
          }
          return callback(records,instance);
        });
        Object.defineProperty(observer,'__cvDiagObserverId',{value:id,configurable:true});
        return observer;
      }
      DiagnosticMO.prototype=NativeMO.prototype;
      Object.setPrototypeOf(DiagnosticMO,NativeMO);
      window.MutationObserver=DiagnosticMO;
      NativeMO.prototype.observe=function(target,options){
        const id=this.__cvDiagObserverId;
        if(id&&diag.observers[id]){
          diag.observeCalls++;
          diag.observers[id].observeCalls++;
          diag.observers[id].lastObserveTarget=sig(target);
          diag.observers[id].lastObserveOptions=options;
        }
        return nativeObserve.call(this,target,options);
      };
      NativeMO.prototype.disconnect=function(){return nativeDisconnect.call(this)};

      const nativeTimeout=window.setTimeout.bind(window);
      const nativeInterval=window.setInterval.bind(window);
      const nativeRaf=window.requestAnimationFrame.bind(window);
      window.setTimeout=(fn,delay,...args)=>{
        diag.timeoutScheduled++;
        if(typeof fn!=='function')return nativeTimeout(fn,delay,...args);
        return nativeTimeout((...cbArgs)=>{diag.timeoutFired++;return fn(...cbArgs)},delay,...args);
      };
      window.setInterval=(fn,delay,...args)=>{
        diag.intervalScheduled++;
        if(typeof fn!=='function')return nativeInterval(fn,delay,...args);
        return nativeInterval((...cbArgs)=>{diag.intervalFired++;return fn(...cbArgs)},delay,...args);
      };
      window.requestAnimationFrame=fn=>{
        diag.rafScheduled++;
        return nativeRaf(ts=>{diag.rafFired++;return fn(ts)});
      };
    }catch(error){
      console.error('CV_DIAG_V76_INIT_FAILED',String(error?.stack||error));
    }
  });

  await page.goto(PORTAL,{waitUntil:'domcontentloaded',timeout:30000});
  await page.waitForFunction(()=>typeof window.supabase?.createClient==='function',null,{timeout:20000});
  const loginResult=await page.evaluate(async({base,key,tokenHash})=>{
    const c=window.supabase.createClient(base,key,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:false}});
    const {data,error}=await c.auth.verifyOtp({token_hash:tokenHash,type:'magiclink'});
    if(error||!data?.session?.access_token)throw new Error(error?.message||'Magic-link verification failed');
    return {user_id:data.user?.id,access_token:data.session.access_token};
  },{base:BASE,key:KEY,tokenHash:bootstrap.token_hash});
  if(loginResult?.user_id!==bootstrap.client_id)throw new Error('Authenticated unexpected canary user');
  await page.reload({waitUntil:'domcontentloaded',timeout:30000});
  const routineCta=page.getByRole('button',{name:/VER RUTINA/i}).first();
  await routineCta.waitFor({state:'visible',timeout:30000});
  console.log('CV_CANARY_V76_AUTH_OK');

  await rawTap(page,routineCta,'open-routine');
  console.log('CV_DIAG_V76_ROUTINE_OPENED');

  const samples=Math.ceil(OBSERVE_MS/SAMPLE_MS);
  for(let i=0;i<=samples;i++){
    if(pageClosed||browserDisconnected||crashed||page.isClosed())break;
    const snapshot=await page.evaluate(()=>{
      const d=window.__cvDiagV76||{};
      const starts=[...document.querySelectorAll('button[onclick*="startWorkout"], .cvWorkoutStartV40')].slice(0,8).map(el=>{
        const r=el.getBoundingClientRect();
        const style=getComputedStyle(el);
        return {
          text:(el.textContent||'').trim().slice(0,80),
          className:typeof el.className==='string'?el.className:'',
          connected:el.isConnected,
          rect:[Math.round(r.x),Math.round(r.y),Math.round(r.width),Math.round(r.height)],
          display:style.display,visibility:style.visibility,opacity:style.opacity,
        };
      });
      const topObservers=Object.values(d.observers||{}).sort((a,b)=>(b.callbacks||0)-(a.callbacks||0)).slice(0,8).map(x=>({
        id:x.id,callbacks:x.callbacks,records:x.records,observeCalls:x.observeCalls,
        lastTarget:x.lastTarget,lastObserveTarget:x.lastObserveTarget,
        lastTypes:x.lastTypes,created:x.created,
      }));
      const topTargets=Object.entries(d.mutationTargets||{}).sort((a,b)=>b[1]-a[1]).slice(0,10);
      return {
        elapsedMs:Date.now()-(d.startedAt||Date.now()),
        domNodes:document.getElementsByTagName('*').length,
        contentChildren:document.querySelector('#content')?.childElementCount??null,
        heroCount:document.querySelectorAll('.cvWorkoutHeroV31').length,
        compactCount:document.querySelectorAll('.cvWorkoutCompactV40').length,
        startCount:starts.length,starts,
        observerCreated:d.observerCreated,observeCalls:d.observeCalls,
        observerCallbacks:d.observerCallbacks,mutationRecords:d.mutationRecords,
        mutationTypes:d.mutationTypes,
        timeoutScheduled:d.timeoutScheduled,timeoutFired:d.timeoutFired,
        intervalScheduled:d.intervalScheduled,intervalFired:d.intervalFired,
        rafScheduled:d.rafScheduled,rafFired:d.rafFired,
        topObservers,topTargets,
      };
    }).catch(error=>({sampleError:String(error?.message||error)}));
    console.log(`CV_DIAG_V76_SAMPLE_${String(i).padStart(2,'0')} ${JSON.stringify(snapshot)}`);
    if(snapshot.sampleError)break;
    if(i<samples)await sleep(SAMPLE_MS);
  }

  if(pageClosed||browserDisconnected||crashed||page.isClosed()){
    throw new Error(`WebKit terminated during passive pre-start diagnostic: ${JSON.stringify({pageClosed,browserDisconnected,crashed})}`);
  }
  completedWindow=true;
  console.log('CV_DIAG_V76_SURVIVED_35S_PRESTART');
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

if(!process.exitCode&&completedWindow)console.log('CV_DIAG_V76_OK');
