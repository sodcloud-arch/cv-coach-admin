import { webkit } from 'playwright';
import assert from 'node:assert/strict';

const base=process.env.CV_TEST_URL||'http://127.0.0.1:4173';
const browser=await webkit.launch();
const context=await browser.newContext({viewport:{width:390,height:844},isMobile:true,hasTouch:true,serviceWorkers:'block'});

// Keep the real touchscreen event path but neutralize CI-only media/haptic effects.
// This separates a workout-runtime failure from headless WebKit media instability.
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
    connect(){return this}
    disconnect(){}
    start(){}
    stop(){}
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
let pageClosed=false;
let contextClosed=false;
let browserDisconnected=false;

page.on('console',msg=>console.log('CV_PAGE_CONSOLE',msg.type(),msg.text()));
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

    ['pointerdown','pointerup','touchstart','touchend','click'].forEach(type=>{
      document.addEventListener(type,e=>{
        const t=e?.target;
        emit(`EVENT_${type.toUpperCase()}`,{
          tag:t?.tagName||'',
          cls:typeof t?.className==='string'?t.className:'',
          id:t?.id||'',
          disabled:!!t?.disabled
        });
      },true);
    });

    const originalToggle=window.cvToggleSet;
    emit('HOOK_TOGGLE_READY',{type:typeof originalToggle});
    window.cvToggleSet=function(){
      const args=[...arguments];
      emit('TOGGLE_ENTER',{args});
      try{
        const out=originalToggle.apply(this,args);
        emit('TOGGLE_RETURNED',{thenable:!!(out&&typeof out.then==='function'),type:typeof out});
        if(out&&typeof out.then==='function'){
          out.then(v=>emit('TOGGLE_RESOLVE',{value:v}))
             .catch(err=>emit('TOGGLE_REJECT',{error:String(err?.stack||err?.message||err)}));
        }else{
          emit('TOGGLE_SYNC_RETURN',{value:out});
        }
        return out;
      }catch(err){
        emit('TOGGLE_THROW',{error:String(err?.stack||err?.message||err)});
        throw err;
      }
    };

    if(typeof window.startWorkout==='function'){
      const originalStart=window.startWorkout;
      emit('HOOK_START_READY',{type:typeof originalStart});
      window.startWorkout=function(){
        const args=[...arguments];
        emit('START_ENTER',{args});
        try{
          const out=originalStart.apply(this,args);
          emit('START_RETURNED',{thenable:!!(out&&typeof out.then==='function'),type:typeof out});
          if(out&&typeof out.then==='function'){
            out.then(v=>emit('START_RESOLVE',{value:v}))
               .catch(err=>emit('START_REJECT',{error:String(err?.stack||err?.message||err)}));
          }else{
            emit('START_SYNC_RETURN',{value:out});
          }
          return out;
        }catch(err){
          emit('START_THROW',{error:String(err?.stack||err?.message||err)});
          throw err;
        }
      };
    }else emit('HOOK_START_UNAVAILABLE');

    const controller=window.CVWorkoutControllerV71;
    if(controller&&typeof controller.start==='function'){
      const originalControllerStart=controller.start.bind(controller);
      emit('HOOK_CONTROLLER_START_READY');
      controller.start=function(){
        const args=[...arguments];
        emit('CONTROLLER_START_ENTER',{args});
        try{
          const out=originalControllerStart(...args);
          emit('CONTROLLER_START_RETURNED',{thenable:!!(out&&typeof out.then==='function')});
          if(out&&typeof out.then==='function'){
            out.then(v=>emit('CONTROLLER_START_RESOLVE',{value:v}))
               .catch(err=>emit('CONTROLLER_START_REJECT',{error:String(err?.stack||err?.message||err)}));
          }
          return out;
        }catch(err){
          emit('CONTROLLER_START_THROW',{error:String(err?.stack||err?.message||err)});
          throw err;
        }
      };
    }else emit('HOOK_CONTROLLER_START_UNAVAILABLE',{keys:controller?Object.keys(controller):[]});

    window.addEventListener('beforeunload',()=>emit('BEFOREUNLOAD'));
    window.addEventListener('unload',()=>emit('UNLOAD'));
    emit('HOOKS_INSTALLED');
  });

  const before=await page.evaluate(()=>{
    const el=document.querySelector('.cvSetCheck');
    const r=el?.getBoundingClientRect?.();
    return {
      exists:!!el,
      rect:r?{x:r.x,y:r.y,width:r.width,height:r.height,bottom:r.bottom,right:r.right}:null,
      viewport:{w:innerWidth,h:innerHeight},scrollY,
      onclick:el?.getAttribute('onclick')||'',disabled:!!el?.disabled,
      pointerEvents:el?getComputedStyle(el).pointerEvents:'',
      visibility:el?getComputedStyle(el).visibility:'',display:el?getComputedStyle(el).display:'',opacity:el?getComputedStyle(el).opacity:'',
      html:el?.outerHTML?.slice(0,600)||''
    };
  });
  console.log('CV_V73_CHECK_BEFORE',JSON.stringify(before));
  assert.equal(before.exists,true,'First .cvSetCheck missing');

  await page.evaluate(()=>document.querySelector('.cvSetCheck')?.scrollIntoView?.({block:'center',inline:'nearest',behavior:'instant'}));
  await page.waitForTimeout(180);
  const target=await page.evaluate(()=>{
    const el=document.querySelector('.cvSetCheck');const r=el?.getBoundingClientRect?.();if(!r)return null;
    const x=r.left+r.width/2,y=r.top+r.height/2;const hit=document.elementFromPoint(x,y);
    return {x,y,width:r.width,height:r.height,viewport:{w:innerWidth,h:innerHeight},scrollY,
      hitTag:hit?.tagName||'',hitClass:typeof hit?.className==='string'?hit.className:'',hitId:hit?.id||'',hitHtml:hit?.outerHTML?.slice(0,400)||''};
  });
  console.log('CV_V73_CHECK_TARGET',JSON.stringify(target));
  assert.ok(target&&target.y>=0&&target.y<=target.viewport.h&&target.x>=0&&target.x<=target.viewport.w,'Set check center is outside viewport after scroll');
  assert.ok(String(target.hitClass).includes('cvSetCheck')||String(target.hitHtml).includes('cvSetCheck'),'Set check is covered by another element');

  console.log('CV_TRACE_NODE_TAP_BEGIN');
  try{
    await page.touchscreen.tap(target.x,target.y);
    console.log('CV_TRACE_NODE_TAP_RETURNED');
  }catch(err){
    console.log('CV_TRACE_NODE_TAP_ERROR',String(err?.stack||err?.message||err));
    throw err;
  }

  // Remain on Node side so page console events survive if WebKit terminates.
  await new Promise(r=>setTimeout(r,1800));
  console.log('CV_TRACE_NODE_AFTER_SLEEP',JSON.stringify({pageClosed,contextClosed,browserDisconnected,pageErrors}));
  if(pageClosed||contextClosed||browserDisconnected){
    throw new Error(`WebKit closed after physical set-check tap page=${pageClosed} context=${contextClosed} browser=${browserDisconnected}`);
  }

  const after=await page.evaluate(()=>{
    const s=window.cvExercises?.()?.[0]?.sets?.[0];
    return {controller:window.CVWorkoutControllerV71?.diagnose?.()||null,
      set:s?{weight_kg:s.weight_kg,reps:s.reps,completed:s.completed}:null,
      checkClass:document.querySelector('.cvSetCheck')?.className||'',
      checkPressed:document.querySelector('.cvSetCheck')?.getAttribute('aria-pressed')||'',scrollY};
  });
  console.log('CV_V73_CHECK_AFTER',JSON.stringify(after));
  assert.equal(after.controller?.sessionId,'demo','physical check did not establish demo session');
  assert.equal(after.set?.completed,true,'physical check did not complete first set');
  assert.equal(after.set?.weight_kg,22.5,'physical check lost KG');
  assert.equal(after.set?.reps,9,'physical check lost reps');
  assert.equal(pageErrors.length,0,'Page errors: '+pageErrors.join(' | '));
  console.log('CV_V73_PHYSICAL_SET_CHECK_DIAGNOSTIC_OK');
} finally {
  await context.close().catch(()=>{});
  await browser.close().catch(()=>{});
}
