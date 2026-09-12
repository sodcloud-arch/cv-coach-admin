import { webkit } from 'playwright';
import assert from 'node:assert/strict';

const base=process.env.CV_TEST_URL||'http://127.0.0.1:4173';
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const browser=await webkit.launch();
const context=await browser.newContext({viewport:{width:390,height:844},isMobile:true,hasTouch:true,serviceWorkers:'block'});

// Keep genuine touch/click delivery while removing CI-only media/haptic noise.
await context.addInitScript(()=>{
  try{localStorage.setItem('cv_sound_enabled','0')}catch(_){}
  class SilentAudio{
    constructor(src=''){this.src=src;this.currentTime=0;this.volume=1;this.muted=false;this.paused=true;this.preload='auto'}
    play(){this.paused=false;return Promise.resolve()}
    pause(){this.paused=true}
    addEventListener(){}
    removeEventListener(){}
    load(){}
  }
  class SilentParam{setValueAtTime(){} exponentialRampToValueAtTime(){} linearRampToValueAtTime(){}}
  class SilentNode{
    constructor(){this.frequency=new SilentParam();this.gain=new SilentParam();this.type='triangle'}
    connect(){return this} disconnect(){} start(){} stop(){}
  }
  class SilentAudioContext{
    constructor(){this.state='running';this.currentTime=0;this.destination=new SilentNode()}
    resume(){this.state='running';return Promise.resolve()}
    suspend(){this.state='suspended';return Promise.resolve()}
    close(){this.state='closed';return Promise.resolve()}
    createOscillator(){return new SilentNode()}
    createGain(){return new SilentNode()}
  }
  try{Object.defineProperty(window,'Audio',{value:SilentAudio,writable:true,configurable:true})}catch(_){window.Audio=SilentAudio}
  try{Object.defineProperty(window,'AudioContext',{value:SilentAudioContext,writable:true,configurable:true})}catch(_){window.AudioContext=SilentAudioContext}
  try{Object.defineProperty(window,'webkitAudioContext',{value:SilentAudioContext,writable:true,configurable:true})}catch(_){window.webkitAudioContext=SilentAudioContext}
  try{Object.defineProperty(navigator,'vibrate',{value:()=>true,writable:true,configurable:true})}catch(_){}
  window.__CV_TEST_MEDIA_STUB__=true;
});

const page=await context.newPage();
const pageErrors=[];
const consoleLines=[];
let pageClosed=false,contextClosed=false,browserDisconnected=false;

page.on('console',msg=>{
  const line=msg.text();
  consoleLines.push(line);
  console.log('CV_PAGE_CONSOLE',msg.type(),line);
});
page.on('pageerror',e=>{
  const text=String(e?.stack||e?.message||e);
  pageErrors.push(text);
  console.log('CV_PAGE_ERROR',text);
});
page.on('close',()=>{pageClosed=true;console.log('CV_TRACE_PAGE_CLOSE')});
context.on('close',()=>{contextClosed=true;console.log('CV_TRACE_CONTEXT_CLOSE')});
browser.on('disconnected',()=>{browserDisconnected=true;console.log('CV_TRACE_BROWSER_DISCONNECTED')});

async function setValue(id,value){
  const opened=await page.evaluate(inputId=>window.CVWorkoutNumpadV73.open(inputId),id);
  assert.equal(opened,true,`V73 failed to open ${id}`);
  await page.evaluate(()=>{for(let i=0;i<8;i++)document.querySelector('[data-key="back"]')?.click()});
  for(const ch of String(value).replace('.',',')){
    await page.evaluate(k=>document.querySelector(`[data-key="${k===','?'decimal':k}"]`)?.click(),ch);
  }
  await page.evaluate(()=>document.querySelector('[data-pad-action="done"]')?.click());
  await page.waitForFunction(inputId=>window.CVWorkoutNumpadV73.state().open===false&&document.getElementById(inputId)?.value!==undefined,id,{timeout:3000});
}

try{
  await page.goto(base,{waitUntil:'domcontentloaded',timeout:20000});
  await page.evaluate(()=>document.getElementById('demoBtn')?.click());
  await page.waitForFunction(()=>!document.getElementById('app')?.classList.contains('hidden'),null,{timeout:5000});
  await page.waitForFunction(()=>{
    try{if(document.getElementById('cvw_0_0'))return true;if(typeof window.openDay==='function')window.openDay('d1');return !!document.getElementById('cvw_0_0')}catch(_){return false}
  },null,{timeout:5000,polling:100});
  await page.waitForFunction(()=>!!window.CVWorkoutControllerV71&&!!window.CVWorkoutNumpadV73,null,{timeout:5000});
  assert.equal(await page.evaluate(()=>window.__CV_TEST_MEDIA_STUB__===true),true,'CI media stub missing');

  await setValue('cvw_0_0','22.5');
  await setValue('cvr_0_0','9');

  await page.evaluate(()=>{
    const safe=v=>{try{return JSON.stringify(v)}catch(_){return JSON.stringify({text:String(v)})}};
    const emit=(name,payload={})=>console.log(`CV_TRACE_${name} ${safe({...payload,t:Math.round(performance.now())})}`);
    const domState=()=>{
      const btn=document.querySelector('.cvSetCheck');
      return {
        pressed:btn?.getAttribute('aria-pressed')||'',
        cls:btn?.className||'',
        disabled:!!btn?.disabled,
        kg:document.getElementById('cvw_0_0')?.value,
        reps:document.getElementById('cvr_0_0')?.value,
        bodyClass:document.body.className
      };
    };

    ['pointerdown','pointerup','touchstart','touchend','click'].forEach(type=>{
      document.addEventListener(type,e=>{
        const t=e?.target;
        emit(`EVENT_${type.toUpperCase()}`,{tag:t?.tagName||'',cls:typeof t?.className==='string'?t.className:'',id:t?.id||'',disabled:!!t?.disabled});
      },true);
    });

    if(typeof window.render==='function'){
      const originalRender=window.render;
      let renderSeq=0;
      window.render=function(){
        const seq=++renderSeq;
        emit('RENDER_ENTER',{seq,args:[...arguments].map(x=>typeof x)});
        try{
          const out=originalRender.apply(this,arguments);
          emit('RENDER_RETURN',{seq,dom:domState()});
          return out;
        }catch(err){
          emit('RENDER_THROW',{seq,error:String(err?.stack||err?.message||err)});
          throw err;
        }
      };
      emit('HOOK_RENDER_READY');
    }

    const originalToggle=window.cvToggleSet;
    emit('HOOK_TOGGLE_READY',{type:typeof originalToggle});
    window.cvToggleSet=function(){
      const args=[...arguments];
      emit('TOGGLE_ENTER',{args,dom:domState()});
      try{
        const out=originalToggle.apply(this,args);
        emit('TOGGLE_RETURNED',{thenable:!!(out&&typeof out.then==='function'),type:typeof out});
        if(out&&typeof out.then==='function'){
          out.then(v=>{
            emit('TOGGLE_RESOLVE',{value:v,dom:domState()});
            try{emit('CONTROLLER_STATE',{state:window.CVWorkoutControllerV71?.diagnose?.()||null})}
            catch(err){emit('CONTROLLER_STATE_ERROR',{error:String(err?.message||err)})}

            // Do not call cvExercises in the resolve microtask. Probe it separately so
            // a stuck getter can be identified by BEGIN-without-END in the log.
            [0,25,100,300,800].forEach(ms=>setTimeout(()=>emit('HEARTBEAT',{ms,dom:domState()}),ms));
            setTimeout(()=>{
              emit('EXERCISES_PROBE_BEGIN');
              try{
                const s=window.cvExercises?.()?.[0]?.sets?.[0];
                emit('EXERCISES_PROBE_END',{set:s?{weight_kg:s.weight_kg,reps:s.reps,completed:s.completed}:null});
              }catch(err){emit('EXERCISES_PROBE_ERROR',{error:String(err?.stack||err?.message||err)})}
            },60);
          }).catch(err=>emit('TOGGLE_REJECT',{error:String(err?.stack||err?.message||err)}));
        }else emit('TOGGLE_SYNC_RETURN',{value:out,dom:domState()});
        return out;
      }catch(err){emit('TOGGLE_THROW',{error:String(err?.stack||err?.message||err)});throw err}
    };

    if(typeof window.startWorkout==='function'){
      const originalStart=window.startWorkout;
      window.startWorkout=function(){
        const args=[...arguments];emit('START_ENTER',{args});
        try{
          const out=originalStart.apply(this,args);emit('START_RETURNED',{thenable:!!(out&&typeof out.then==='function')});
          if(out&&typeof out.then==='function')out.then(v=>emit('START_RESOLVE',{value:v})).catch(err=>emit('START_REJECT',{error:String(err?.message||err)}));
          return out;
        }catch(err){emit('START_THROW',{error:String(err?.message||err)});throw err}
      };
      emit('HOOK_START_READY');
    }

    const controller=window.CVWorkoutControllerV71;
    if(controller&&typeof controller.start==='function'){
      const originalControllerStart=controller.start.bind(controller);
      controller.start=function(){
        const args=[...arguments];emit('CONTROLLER_START_ENTER',{args});
        try{
          const out=originalControllerStart(...args);emit('CONTROLLER_START_RETURNED',{thenable:!!(out&&typeof out.then==='function')});
          if(out&&typeof out.then==='function')out.then(v=>emit('CONTROLLER_START_RESOLVE',{value:v})).catch(err=>emit('CONTROLLER_START_REJECT',{error:String(err?.message||err)}));
          return out;
        }catch(err){emit('CONTROLLER_START_THROW',{error:String(err?.message||err)});throw err}
      };
      emit('HOOK_CONTROLLER_START_READY');
    }
    emit('HOOKS_INSTALLED',{dom:domState()});
  });

  const target=await page.evaluate(()=>{
    const el=document.querySelector('.cvSetCheck');const r=el?.getBoundingClientRect?.();if(!r)return null;
    const x=r.left+r.width/2,y=r.top+r.height/2;const hit=document.elementFromPoint(x,y);
    return {x,y,width:r.width,height:r.height,viewport:{w:innerWidth,h:innerHeight},hitTag:hit?.tagName||'',hitClass:typeof hit?.className==='string'?hit.className:''};
  });
  console.log('CV_V73_CHECK_TARGET',JSON.stringify(target));
  assert.ok(target&&target.x>=0&&target.x<=target.viewport.w&&target.y>=0&&target.y<=target.viewport.h,'Set check center outside viewport');
  assert.ok(String(target.hitClass).includes('cvSetCheck'),'Set check is covered');

  console.log('CV_TRACE_NODE_TAP_BEGIN');
  await page.touchscreen.tap(target.x,target.y);
  console.log('CV_TRACE_NODE_TAP_RETURNED');

  // Never query the page after the tap. If the UI thread wedges, streamed console
  // markers still identify the exact last healthy phase.
  await sleep(1800);
  console.log('CV_TRACE_NODE_AFTER_SLEEP',JSON.stringify({pageClosed,contextClosed,browserDisconnected,pageErrors}));

  const has=name=>consoleLines.some(line=>line.startsWith(`CV_TRACE_${name} `)||line===`CV_TRACE_${name}`);
  assert.equal(has('EVENT_CLICK'),true,'Physical click did not reach the set button');
  assert.equal(has('TOGGLE_ENTER'),true,'cvToggleSet was not invoked');
  assert.equal(has('TOGGLE_RESOLVE'),true,'cvToggleSet did not resolve');
  assert.equal(has('CONTROLLER_STATE'),true,'controller state was not readable at toggle resolution');
  assert.equal(has('HEARTBEAT'),true,'no post-toggle heartbeat executed');

  console.log('CV_V73_SET_CHECK_STREAM_DIAGNOSTIC_COMPLETE');
} finally {
  await Promise.race([context.close().catch(()=>{}),sleep(1200)]).catch(()=>{});
  await Promise.race([browser.close().catch(()=>{}),sleep(1200)]).catch(()=>{});
}
