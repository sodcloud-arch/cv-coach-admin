import { webkit } from 'playwright';
import assert from 'node:assert/strict';

const base=process.env.CV_TEST_URL||'http://127.0.0.1:4173';
const scenario=(process.env.CV_SCENARIO||'all').toLowerCase();

function isWebKitInfraClose(err){
  return /Target page, context or browser has been closed|Target closed|browser has been closed/i.test(String(err?.message||err));
}

async function withInfraRetry(label,fn){
  let last;
  for(let attempt=1;attempt<=2;attempt++){
    try{return await fn()}
    catch(err){
      last=err;
      if(attempt<2&&isWebKitInfraClose(err)){
        console.warn(`${label}_WEBKIT_INFRA_RETRY_${attempt}`);
        await new Promise(r=>setTimeout(r,350));
        continue;
      }
      throw err;
    }
  }
  throw last;
}

async function demoWorkoutPage(label){
  const browser=await webkit.launch();
  const context=await browser.newContext({viewport:{width:390,height:844},isMobile:true,hasTouch:true,serviceWorkers:'block'});
  const page=await context.newPage();
  const errors=[];
  page.on('pageerror',e=>errors.push(String(e?.message||e)));
  await page.goto(base,{waitUntil:'domcontentloaded',timeout:20000});
  await page.evaluate(()=>document.getElementById('demoBtn')?.click());
  await page.waitForFunction(()=>!document.getElementById('app')?.classList.contains('hidden'),null,{timeout:5000});
  await page.waitForFunction(()=>{
    try{if(document.getElementById('cvw_0_0'))return true;if(typeof window.openDay==='function')window.openDay('d1');return !!document.getElementById('cvw_0_0')}catch(_){return false}
  },null,{timeout:5000,polling:100});
  await page.waitForFunction(()=>!!window.CVWorkoutControllerV71&&!!window.CVWorkoutNumpadV73,null,{timeout:5000});
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
  },id,{timeout:5000,polling:50});
}

async function currentCenter(page,selector,label){
  const p=await page.evaluate(sel=>{
    const el=document.querySelector(sel);if(!el)return null;
    const r=el.getBoundingClientRect();
    return {x:r.left+r.width/2,y:r.top+r.height/2,width:r.width,height:r.height};
  },selector);
  assert.ok(p&&p.width>0&&p.height>0,`No tappable box for ${label}`);
  return p;
}

async function openPadByRealTap(page,id){
  await page.waitForTimeout(220);
  await waitForV73Decoration(page,id);
  await page.evaluate(inputId=>document.getElementById(inputId)?.scrollIntoView?.({block:'center',inline:'nearest',behavior:'instant'}),id);
  await page.waitForTimeout(160);
  await waitForV73Decoration(page,id);
  const point=await currentCenter(page,'#'+id,id);
  const hit=await page.evaluate(({x,y})=>{
    const el=document.elementFromPoint(x,y);return el?.id||el?.className||'';
  },point);
  assert.ok(String(hit).includes(id)||String(hit).includes('cv'),`Unexpected element over ${id}: ${hit}`);
  await page.touchscreen.tap(point.x,point.y);
  await page.waitForFunction(inputId=>{
    const s=window.CVWorkoutNumpadV73?.state?.();
    const root=document.getElementById('cvNumpadV73');
    return !!s?.open&&s.inputId===inputId&&root&&!root.classList.contains('hidden')&&root.getAttribute('aria-hidden')==='false';
  },id,{timeout:3000});
  await page.waitForTimeout(120);
  const settled=await page.evaluate(inputId=>({
    pad:window.CVWorkoutNumpadV73.state(),
    focused:document.activeElement?.id||'',
    decorated:document.getElementById(inputId)?.dataset.cvPadV73||'',
    inputMode:document.getElementById(inputId)?.getAttribute('inputmode'),
    readOnly:document.getElementById(inputId)?.readOnly
  }),id);
  assert.equal(settled.pad.open,true,`V73 pad closed after real tap for ${id}`);
  assert.equal(settled.pad.inputId,id,`V73 real tap opened wrong input for ${id}`);
  assert.notEqual(settled.focused,id,`Native input focus survived real tap for ${id}`);
  assert.equal(settled.decorated,'1',`${id} lost V73 decoration after touch`);
  assert.equal(settled.inputMode,'none',`${id} reverted to native keyboard mode after touch`);
  assert.equal(settled.readOnly,true,`${id} reverted to native editable input after touch`);
}

async function clearPadByJs(page){
  await page.evaluate(()=>{for(let i=0;i<8;i++)document.querySelector('[data-key="back"]')?.click()});
}

async function tapPadKey(page,key){
  const p=await currentCenter(page,`[data-key="${key}"]`,`pad key ${key}`);
  await page.touchscreen.tap(p.x,p.y);
}

async function tapDone(page){
  const p=await currentCenter(page,'[data-pad-action="done"]','LISTO');
  await page.touchscreen.tap(p.x,p.y);
}

async function setWithPhysicalPad(page,id,value){
  await openPadByRealTap(page,id);
  const active=await page.evaluate(()=>window.CVWorkoutNumpadV73.state());
  const expectedScroll=Math.max(0,Number(active.restoreY)||0);
  await clearPadByJs(page);
  for(const ch of String(value).replace('.',',')){
    if(ch===',')await tapPadKey(page,'decimal');
    else await tapPadKey(page,ch);
  }
  await tapDone(page);
  await page.waitForFunction(inputId=>window.CVWorkoutNumpadV73.state().open===false&&document.getElementById(inputId)?.value!==undefined,id,{timeout:3000});
  await page.waitForTimeout(120);
  const result=await page.evaluate(inputId=>({
    value:document.getElementById(inputId)?.value,
    readOnly:document.getElementById(inputId)?.readOnly,
    inputMode:document.getElementById(inputId)?.getAttribute('inputmode'),
    scrollY:window.scrollY
  }),id);
  assert.equal(result.value,String(value),`V73 did not commit ${value} into ${id}`);
  assert.equal(result.readOnly,true,`${id} is not readonly under V73`);
  assert.equal(result.inputMode,'none',`${id} can still request native keyboard`);
  assert.ok(Math.abs(result.scrollY-expectedScroll)<=4,`V73 did not restore scroll for ${id}: expected ${expectedScroll}, got ${result.scrollY}`);
}

async function setWithDeterministicPad(page,id,value){
  const opened=await page.evaluate(inputId=>window.CVWorkoutNumpadV73.open(inputId),id);
  assert.equal(opened,true,`V73 failed to open ${id}`);
  await clearPadByJs(page);
  for(const ch of String(value).replace('.',',')){
    await page.evaluate(k=>document.querySelector(`[data-key="${k===','?'decimal':k}"]`)?.click(),ch);
  }
  await page.evaluate(()=>document.querySelector('[data-pad-action="done"]')?.click());
  await page.waitForFunction(inputId=>window.CVWorkoutNumpadV73.state().open===false&&document.getElementById(inputId)?.value!==undefined,id,{timeout:3000});
  const valueNow=await page.evaluate(inputId=>document.getElementById(inputId)?.value,id);
  assert.equal(valueNow,String(value),`Deterministic V73 setup failed for ${id}`);
}

async function realTouchEditorTest(){
  let t;
  try{
    t=await demoWorkoutPage('REAL_TOUCH');
    const {page,errors}=t;
    await setWithPhysicalPad(page,'cvw_0_0','17.5');
    await setWithPhysicalPad(page,'cvr_0_0','11');
    const values=await page.evaluate(()=>({w:document.getElementById('cvw_0_0')?.value,r:document.getElementById('cvr_0_0')?.value}));
    assert.deepEqual(values,{w:'17.5',r:'11'},'real touch editing did not persist KG/reps');
    assert.equal(errors.length,0,'Real-touch workout errors: '+errors.join(' | '));
    console.log('CV_V73_REAL_TOUCH_EDITOR_WEBKIT_OK');
  } finally {await closeTest(t)}
}

async function explicitStartTest(){
  let t;
  try{
    t=await demoWorkoutPage('EXPLICIT');
    const {page,errors}=t;
    await setWithDeterministicPad(page,'cvw_0_0','20');
    await setWithDeterministicPad(page,'cvr_0_0','8');
    const started=await page.evaluate(()=>window.startWorkout());
    assert.equal(started,true,'explicit start did not resolve true');
    await page.waitForFunction(()=>window.CVWorkoutControllerV71?.diagnose?.().sessionId==='demo',null,{timeout:5000});
    const got=await page.evaluate(()=>{const s=window.cvExercises()?.[0]?.sets?.[0];return {w:s?.weight_kg,r:s?.reps}});
    assert.deepEqual(got,{w:20,r:8},'explicit start lost V73-edited values');
    assert.equal(errors.length,0,'Explicit workout errors: '+errors.join(' | '));
    console.log('CV_V73_EXPLICIT_START_WEBKIT_OK');
  } finally {await closeTest(t)}
}

async function physicalSetCheckTest(){
  let t;
  try{
    t=await demoWorkoutPage('SET_CHECK');
    const {page,errors}=t;
    await setWithDeterministicPad(page,'cvw_0_0','22.5');
    await setWithDeterministicPad(page,'cvr_0_0','9');
    await page.waitForTimeout(180);
    await page.evaluate(()=>{
      const base=window.cvToggleSet;
      window.__cvPhysicalToggleCalls=0;
      window.cvToggleSet=function(){window.__cvPhysicalToggleCalls++;return base.apply(this,arguments)};
    });
    const p=await currentCenter(page,'.cvSetCheck','first set check');
    await page.touchscreen.tap(p.x,p.y);
    await page.waitForTimeout(65);
    await page.touchscreen.tap(p.x,p.y);
    await page.waitForFunction(()=>window.CVWorkoutControllerV71?.diagnose?.().sessionId==='demo',null,{timeout:5000});
    await page.waitForTimeout(550);
    const got=await page.evaluate(()=>{
      const s=window.cvExercises()?.[0]?.sets?.[0];
      return {w:s?.weight_kg,r:s?.reps,c:s?.completed,calls:window.__cvPhysicalToggleCalls||0};
    });
    assert.equal(got.calls,1,`Rapid physical double tap invoked cvToggleSet ${got.calls} times`);
    assert.deepEqual({w:got.w,r:got.r,c:got.c},{w:22.5,r:9,c:true},'physical first-set tap lost values or completion');
    assert.equal(errors.length,0,'Physical set-check errors: '+errors.join(' | '));
    console.log('CV_V73_PHYSICAL_SET_CHECK_DOUBLE_TAP_GUARD_OK');
  } finally {await closeTest(t)}
}

const scenarios={editor:realTouchEditorTest,start:explicitStartTest,check:physicalSetCheckTest};

if(scenario==='all'){
  for(const [name,fn] of Object.entries(scenarios))await withInfraRetry(name.toUpperCase(),fn);
}else{
  const fn=scenarios[scenario];
  assert.ok(fn,`Unknown CV_SCENARIO=${scenario}`);
  await withInfraRetry(scenario.toUpperCase(),fn);
}

console.log(`CV_MOBILE_WEBKIT_V73_${scenario.toUpperCase()}_OK`);
