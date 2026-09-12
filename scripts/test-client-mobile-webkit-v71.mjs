import { webkit } from 'playwright';
import assert from 'node:assert/strict';

const base=process.env.CV_TEST_URL||'http://127.0.0.1:4173';

async function demoWorkoutPage(label){
  const browser=await webkit.launch();
  const context=await browser.newContext({viewport:{width:390,height:844},isMobile:true,hasTouch:true,serviceWorkers:'block'});

  await context.addInitScript(()=>{
    try{localStorage.setItem('cv_sound_enabled','0')}catch(_){}
    class SilentAudio{
      constructor(src=''){this.src=src;this.currentTime=0;this.volume=1;this.muted=false;this.paused=true}
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
  });

  const page=await context.newPage();
  const errors=[];
  page.on('pageerror',e=>{
    const detail=String(e?.stack||e?.message||e);
    errors.push(detail);
    console.log('CV_V74_PAGEERROR_STACK',detail.replace(/\n/g,' <NL> '));
  });
  await page.goto(base,{waitUntil:'domcontentloaded',timeout:20000});
  await page.waitForFunction(()=>!!window.CVWorkoutInteractionV74,null,{timeout:5000});
  await page.waitForTimeout(350);

  const startupDataErrors=errors.filter(x=>/data\.days|data is null|null is not an object/i.test(x));
  assert.equal(startupDataErrors.length,0,'V74 failed to guard null-data render race: '+startupDataErrors.join(' | '));

  await page.evaluate(()=>document.getElementById('demoBtn')?.click());
  await page.waitForFunction(()=>!document.getElementById('app')?.classList.contains('hidden'),null,{timeout:5000});
  await page.waitForFunction(()=>{
    try{if(document.getElementById('cvw_0_0'))return true;if(typeof window.openDay==='function')window.openDay('d1');return !!document.getElementById('cvw_0_0')}catch(_){return false}
  },null,{timeout:5000,polling:100});
  await page.waitForFunction(()=>!!window.CVWorkoutControllerV71&&!!window.CVWorkoutNumpadV73&&!!window.CVWorkoutInteractionV74,null,{timeout:5000});
  errors.length=0;
  console.log(label+'_READY');
  return {browser,context,page,errors};
}

async function closeTest(t){
  await t?.context?.close().catch(()=>{});
  await t?.browser?.close().catch(()=>{});
}

async function waitForV73Decoration(page,id){
  await page.waitForFunction(inputId=>{
    const el=document.getElementById(inputId);
    return !!el&&el.dataset.cvPadV73==='1'&&el.readOnly===true&&el.getAttribute('inputmode')==='none';
  },id,{timeout:3000,polling:25});
}

async function setWithPad(page,id,value){
  await waitForV73Decoration(page,id);
  const opened=await page.evaluate(inputId=>window.CVWorkoutNumpadV73.open(inputId),id);
  assert.equal(opened,true,`V73 failed to open ${id}`);
  const active=await page.evaluate(()=>({pad:window.CVWorkoutNumpadV73.state(),focused:document.activeElement?.id||''}));
  assert.equal(active.pad.inputId,id,`V73 opened wrong input for ${id}`);
  assert.notEqual(active.focused,id,`Native input focus survived V73 open for ${id}`);
  await page.evaluate(()=>{for(let i=0;i<8;i++)document.querySelector('[data-key="back"]')?.click()});
  for(const ch of String(value).replace('.',',')){
    await page.evaluate(k=>document.querySelector(`[data-key="${k===','?'decimal':k}"]`)?.click(),ch);
  }
  await page.evaluate(()=>document.querySelector('[data-pad-action="done"]')?.click());
  await page.waitForFunction(inputId=>window.CVWorkoutNumpadV73.state().open===false&&document.getElementById(inputId)?.value!==undefined,id,{timeout:3000});
  const result=await page.evaluate(inputId=>({value:document.getElementById(inputId)?.value,readOnly:document.getElementById(inputId)?.readOnly,inputMode:document.getElementById(inputId)?.getAttribute('inputmode')}),id);
  assert.equal(result.value,String(value),`V73 did not commit ${value} into ${id}`);
  assert.equal(result.readOnly,true,`${id} is not readonly under V73`);
  assert.equal(result.inputMode,'none',`${id} can still request native keyboard`);
}

async function explicitStartTest(){
  let t;
  try{
    t=await demoWorkoutPage('EXPLICIT');
    const {page,errors}=t;
    await setWithPad(page,'cvw_0_0','20');
    await setWithPad(page,'cvr_0_0','8');
    const started=await page.evaluate(()=>window.startWorkout());
    assert.equal(started,true,'explicit start did not resolve true');
    await page.waitForFunction(()=>window.CVWorkoutControllerV71?.diagnose?.().sessionId==='demo',null,{timeout:5000});
    const got=await page.evaluate(()=>{const s=window.cvExercises()?.[0]?.sets?.[0];return {w:s?.weight_kg,r:s?.reps}});
    assert.deepEqual(got,{w:20,r:8},'explicit start lost V73-edited values');
    assert.equal(errors.length,0,'Explicit workout errors: '+errors.join(' | '));
    console.log('CV_V74_EXPLICIT_START_WEBKIT_OK');
  } finally {await closeTest(t)}
}

async function physicalAutoStartTest(){
  let t;
  try{
    t=await demoWorkoutPage('PHYSICAL_AUTO');
    const {page,errors}=t;
    await setWithPad(page,'cvw_0_0','22.5');
    await setWithPad(page,'cvr_0_0','9');
    await page.evaluate(()=>document.querySelector('.cvSetCheck')?.scrollIntoView?.({block:'center',inline:'nearest',behavior:'instant'}));
    await page.waitForTimeout(120);
    const p=await page.evaluate(()=>{const el=document.querySelector('.cvSetCheck');const r=el?.getBoundingClientRect?.();return r?{x:r.left+r.width/2,y:r.top+r.height/2,width:r.width,height:r.height}:null});
    assert.ok(p&&p.width>0&&p.height>0,'first set check is not tappable');
    await page.touchscreen.tap(p.x,p.y);
    await page.waitForFunction(()=>window.CVWorkoutControllerV71?.diagnose?.().sessionId==='demo'&&window.cvExercises?.()?.[0]?.sets?.[0]?.completed===true,null,{timeout:5000});
    const got=await page.evaluate(()=>{const s=window.cvExercises()?.[0]?.sets?.[0];return {w:s?.weight_kg,r:s?.reps,c:s?.completed}});
    assert.deepEqual(got,{w:22.5,r:9,c:true},'physical first-set tap lost values or completion');
    assert.equal(errors.length,0,'Physical auto-start workout errors: '+errors.join(' | '));
    console.log('CV_V74_PHYSICAL_AUTO_START_WEBKIT_OK');
  } finally {await closeTest(t)}
}

async function immediateFeedbackAndDoubleTapTest(){
  let t;
  try{
    t=await demoWorkoutPage('PENDING_GUARD');
    const {page,errors}=t;

    const seeded=await page.evaluate(()=>{
      const w=document.getElementById('cvw_0_0'),r=document.getElementById('cvr_0_0');
      if(!w||!r)return null;
      w.value='25';r.value='10';
      w.dispatchEvent(new Event('input',{bubbles:true}));
      r.dispatchEvent(new Event('input',{bubbles:true}));
      return {w:w.value,r:r.value};
    });
    assert.deepEqual(seeded,{w:'25',r:'10'},'V74 pending test could not seed KG/reps');

    const result=await page.evaluate(async()=>{
      const diagnosticBefore=window.CVWorkoutInteractionV74.diagnose();
      const first=window.cvToggleSet(0,0);

      // No await here: V74 must lock and paint synchronously before its first async yield.
      const btn=document.querySelector('.cvSetCheck'),row=btn?.closest('.cvSetRow');
      const during={
        pending:window.CVWorkoutInteractionV74.pending.has('0:0'),
        disabled:!!btn?.disabled,
        busy:btn?.getAttribute('aria-busy')||'',
        visualDone:!!btn?.classList.contains('done'),
        rowPending:!!row?.classList.contains('cv74Pending')
      };
      const secondPromise=window.cvToggleSet(0,0);
      const second=await secondPromise;
      const firstResult=await first;
      const s=window.cvExercises()?.[0]?.sets?.[0];
      return {diagnosticBefore,during,second,firstResult,sessionId:window.CVWorkoutControllerV71?.diagnose?.().sessionId||'',set:s?{w:s.weight_kg,r:s.reps,c:s.completed}:null,pendingAfter:window.CVWorkoutInteractionV74.pending.size};
    });

    assert.equal(result.diagnosticBefore?.toggleInstalled,true,'V74 was not the active set-toggle owner');
    assert.deepEqual(result.during,{pending:true,disabled:true,busy:'true',visualDone:true,rowPending:true},'V74 did not provide synchronous pending feedback');
    assert.equal(result.second,false,'V74 did not block the second concurrent toggle');
    assert.equal(result.sessionId,'demo','V74 auto-start did not establish session');
    assert.deepEqual(result.set,{w:25,r:10,c:true},'V74 concurrent path corrupted first-set state');
    assert.equal(result.pendingAfter,0,'V74 pending lock leaked after completion');
    assert.equal(errors.length,0,'V74 pending guard errors: '+errors.join(' | '));
    console.log('CV_V74_IMMEDIATE_FEEDBACK_DOUBLE_TAP_GUARD_OK');
  } finally {await closeTest(t)}
}

await explicitStartTest();
await physicalAutoStartTest();
await immediateFeedbackAndDoubleTapTest();
console.log('CV_MOBILE_WEBKIT_V74_OK');
