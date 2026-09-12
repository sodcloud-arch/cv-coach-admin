import { webkit } from 'playwright';
import assert from 'node:assert/strict';

const base=process.env.CV_TEST_URL||'http://127.0.0.1:4173';
const browser=await webkit.launch();
const context=await browser.newContext({viewport:{width:390,height:844},isMobile:true,hasTouch:true,serviceWorkers:'block'});

// WebKit headless on Linux can terminate its page when a physical user gesture
// unlocks WebAudio/HTMLAudio. That is infrastructure noise, not the behavior
// under test here. Keep the genuine touchscreen event train while replacing
// only media + vibration with deterministic no-op implementations.
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
page.on('pageerror',e=>pageErrors.push(String(e?.message||e)));

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
    window.__cvCheckTrace=[];
    const log=(type,e)=>{
      const t=e?.target;
      window.__cvCheckTrace.push({
        type,
        targetTag:t?.tagName||'',
        targetClass:typeof t?.className==='string'?t.className:'',
        targetId:t?.id||'',
        time:Math.round(performance.now())
      });
    };
    document.addEventListener('pointerdown',e=>log('pointerdown',e),true);
    document.addEventListener('touchstart',e=>log('touchstart',e),true);
    document.addEventListener('touchend',e=>log('touchend',e),true);
    document.addEventListener('click',e=>log('click',e),true);
    const original=window.cvToggleSet;
    window.__cvToggleCalls=[];
    window.cvToggleSet=function(){
      const args=[...arguments];
      window.__cvToggleCalls.push({args,time:Math.round(performance.now()),phase:'enter'});
      try{
        const out=original.apply(this,args);
        if(out&&typeof out.then==='function'){
          out.then(v=>window.__cvToggleCalls.push({args,time:Math.round(performance.now()),phase:'resolve',value:v}))
             .catch(err=>window.__cvToggleCalls.push({args,time:Math.round(performance.now()),phase:'reject',error:String(err?.message||err)}));
        }else{
          window.__cvToggleCalls.push({args,time:Math.round(performance.now()),phase:'return',value:out});
        }
        return out;
      }catch(err){
        window.__cvToggleCalls.push({args,time:Math.round(performance.now()),phase:'throw',error:String(err?.message||err)});
        throw err;
      }
    };
  });

  const before=await page.evaluate(()=>{
    const el=document.querySelector('.cvSetCheck');
    const r=el?.getBoundingClientRect?.();
    return {
      exists:!!el,
      rect:r?{x:r.x,y:r.y,width:r.width,height:r.height,bottom:r.bottom,right:r.right}:null,
      viewport:{w:innerWidth,h:innerHeight},
      scrollY,
      onclick:el?.getAttribute('onclick')||'',
      disabled:!!el?.disabled,
      pointerEvents:el?getComputedStyle(el).pointerEvents:'',
      visibility:el?getComputedStyle(el).visibility:'',
      display:el?getComputedStyle(el).display:'',
      opacity:el?getComputedStyle(el).opacity:'',
      html:el?.outerHTML?.slice(0,600)||''
    };
  });
  console.log('CV_V73_CHECK_BEFORE',JSON.stringify(before));
  assert.equal(before.exists,true,'First .cvSetCheck missing');

  await page.evaluate(()=>document.querySelector('.cvSetCheck')?.scrollIntoView?.({block:'center',inline:'nearest',behavior:'instant'}));
  await page.waitForTimeout(180);

  const target=await page.evaluate(()=>{
    const el=document.querySelector('.cvSetCheck');
    const r=el?.getBoundingClientRect?.();
    if(!r)return null;
    const x=r.left+r.width/2,y=r.top+r.height/2;
    const hit=document.elementFromPoint(x,y);
    return {
      x,y,width:r.width,height:r.height,
      viewport:{w:innerWidth,h:innerHeight},
      scrollY,
      hitTag:hit?.tagName||'',
      hitClass:typeof hit?.className==='string'?hit.className:'',
      hitId:hit?.id||'',
      hitHtml:hit?.outerHTML?.slice(0,400)||''
    };
  });
  console.log('CV_V73_CHECK_TARGET',JSON.stringify(target));
  assert.ok(target&&target.y>=0&&target.y<=target.viewport.h&&target.x>=0&&target.x<=target.viewport.w,'Set check center is outside viewport after scroll');
  assert.ok(String(target.hitClass).includes('cvSetCheck')||String(target.hitHtml).includes('cvSetCheck'),'Set check is covered by another element');

  await page.touchscreen.tap(target.x,target.y);
  await page.waitForFunction(()=>window.__cvCheckTrace?.some(x=>x.type==='click'&&String(x.targetClass).includes('cvSetCheck')),null,{timeout:3000});
  await page.waitForFunction(()=>window.CVWorkoutControllerV71?.diagnose?.().sessionId==='demo'&&window.cvExercises?.()?.[0]?.sets?.[0]?.completed===true,null,{timeout:5000});
  await page.waitForTimeout(180);

  const after=await page.evaluate(()=>{
    const s=window.cvExercises?.()?.[0]?.sets?.[0];
    return {
      trace:window.__cvCheckTrace||[],
      calls:window.__cvToggleCalls||[],
      controller:window.CVWorkoutControllerV71?.diagnose?.()||null,
      set:s?{weight_kg:s.weight_kg,reps:s.reps,completed:s.completed}:null,
      checkClass:document.querySelector('.cvSetCheck')?.className||'',
      checkAria:document.querySelector('.cvSetCheck')?.getAttribute('aria-pressed')||'',
      scrollY
    };
  });
  console.log('CV_V73_CHECK_AFTER',JSON.stringify(after));
  console.log('CV_V73_CHECK_PAGE_ERRORS',JSON.stringify(pageErrors));

  const clickSeen=after.trace.some(x=>x.type==='click'&&String(x.targetClass).includes('cvSetCheck'));
  const touchSeen=after.trace.some(x=>x.type==='touchstart'&&String(x.targetClass).includes('cvSetCheck'));
  assert.equal(touchSeen,true,'Physical touchstart never reached .cvSetCheck');
  assert.equal(clickSeen,true,'Physical click never reached .cvSetCheck');
  assert.ok(after.calls.some(x=>x.phase==='enter'),'cvToggleSet was not invoked by physical check click');
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
