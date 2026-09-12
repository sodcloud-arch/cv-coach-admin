import { webkit } from 'playwright';
import assert from 'node:assert/strict';

const base=process.env.CV_TEST_URL||'http://127.0.0.1:4173';
const browser=await webkit.launch();
const context=await browser.newContext({viewport:{width:390,height:844},isMobile:true,hasTouch:true,serviceWorkers:'block'});

// Keep the physical touchscreen path but neutralize headless-Linux media/haptics.
await context.addInitScript(()=>{
  try{localStorage.setItem('cv_sound_enabled','0')}catch(_){}
  class SilentAudio{constructor(src=''){this.src=src;this.currentTime=0;this.volume=1;this.muted=false;this.paused=true}play(){this.paused=false;return Promise.resolve()}pause(){this.paused=true}addEventListener(){}removeEventListener(){}load(){}}
  class Param{setValueAtTime(){} exponentialRampToValueAtTime(){} linearRampToValueAtTime(){}}
  class Node{constructor(){this.frequency=new Param();this.gain=new Param();this.type='triangle'}connect(){return this}disconnect(){}start(){}stop(){}}
  class SilentAudioContext{constructor(){this.state='running';this.currentTime=0;this.destination=new Node()}resume(){this.state='running';return Promise.resolve()}suspend(){this.state='suspended';return Promise.resolve()}close(){this.state='closed';return Promise.resolve()}createOscillator(){return new Node()}createGain(){return new Node()}}
  Object.defineProperty(window,'Audio',{value:SilentAudio,writable:true,configurable:true});
  Object.defineProperty(window,'AudioContext',{value:SilentAudioContext,writable:true,configurable:true});
  Object.defineProperty(window,'webkitAudioContext',{value:SilentAudioContext,writable:true,configurable:true});
  try{Object.defineProperty(navigator,'vibrate',{value:()=>true,writable:true,configurable:true})}catch(_){}
});

const page=await context.newPage();
const errors=[];
page.on('pageerror',e=>errors.push(String(e?.stack||e?.message||e)));

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

  // Errors before this point belong to initial portal hydration, not the V73 set-check path.
  const bootErrors=[...errors];
  errors.length=0;
  console.log('CV_V73_BOOT_ERRORS',JSON.stringify(bootErrors));

  await setValue('cvw_0_0','22.5');
  await setValue('cvr_0_0','9');
  errors.length=0;

  await page.evaluate(()=>{
    window.__cvTouchTrace=[];
    ['pointerdown','touchstart','touchend','click'].forEach(type=>document.addEventListener(type,e=>{
      const t=e.target;window.__cvTouchTrace.push({type,cls:typeof t?.className==='string'?t.className:'',tag:t?.tagName||''});
    },true));
    const baseToggle=window.cvToggleSet;
    window.__cvToggleCalls=[];
    window.cvToggleSet=function(){
      const args=[...arguments];window.__cvToggleCalls.push({phase:'enter',args});
      const out=baseToggle.apply(this,args);
      Promise.resolve(out).then(v=>window.__cvToggleCalls.push({phase:'resolve',args,value:v})).catch(e=>window.__cvToggleCalls.push({phase:'reject',args,error:String(e?.message||e)}));
      return out;
    };
  });

  await page.evaluate(()=>document.querySelector('.cvSetCheck')?.scrollIntoView?.({block:'center',inline:'nearest',behavior:'instant'}));
  await page.waitForTimeout(160);
  const target=await page.evaluate(()=>{
    const el=document.querySelector('.cvSetCheck');if(!el)return null;
    const r=el.getBoundingClientRect(),x=r.left+r.width/2,y=r.top+r.height/2,hit=document.elementFromPoint(x,y);
    return {x,y,width:r.width,height:r.height,hitClass:typeof hit?.className==='string'?hit.className:'',disabled:!!el.disabled};
  });
  assert.ok(target&&target.width>=44&&target.height>=44,'First set check is not a stable 44px touch target');
  assert.equal(target.disabled,false,'First set check is disabled before touch');
  assert.ok(target.hitClass.includes('cvSetCheck'),'First set check is covered by another element');

  await page.touchscreen.tap(target.x,target.y);
  await page.waitForFunction(()=>window.__cvTouchTrace?.some(x=>x.type==='click'&&String(x.cls).includes('cvSetCheck')),null,{timeout:3000});
  await page.waitForFunction(()=>window.CVWorkoutControllerV71?.diagnose?.().sessionId==='demo'&&window.cvExercises?.()?.[0]?.sets?.[0]?.completed===true,null,{timeout:5000});
  await page.waitForTimeout(100);

  const result=await page.evaluate(()=>{
    const s=window.cvExercises()?.[0]?.sets?.[0];
    return {trace:window.__cvTouchTrace,calls:window.__cvToggleCalls,sessionId:window.CVWorkoutControllerV71?.diagnose?.().sessionId||'',weight:s?.weight_kg,reps:s?.reps,completed:!!s?.completed,checkClass:document.querySelector('.cvSetCheck')?.className||''};
  });
  assert.equal(result.trace.some(x=>x.type==='touchstart'&&x.cls.includes('cvSetCheck')),true,'touchstart did not reach set check');
  assert.equal(result.trace.some(x=>x.type==='click'&&x.cls.includes('cvSetCheck')),true,'click did not reach set check');
  assert.equal(result.calls.some(x=>x.phase==='enter'),true,'cvToggleSet was not called');
  assert.equal(result.calls.some(x=>x.phase==='resolve'&&x.value===true),true,'cvToggleSet did not resolve true');
  assert.deepEqual({sessionId:result.sessionId,weight:result.weight,reps:result.reps,completed:result.completed},{sessionId:'demo',weight:22.5,reps:9,completed:true},'Physical set check lost session or set state');
  assert.equal(errors.length,0,'Post-ready V73 errors: '+errors.join(' | '));
  console.log('CV_V73_PHYSICAL_SET_CHECK_READY_OK');
} finally {
  await context.close().catch(()=>{});
  await browser.close().catch(()=>{});
}
