import { webkit } from 'playwright';
import assert from 'node:assert/strict';

const base=process.env.CV_TEST_URL||'http://127.0.0.1:4173';

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

async function waitForV73Decoration(page,id){
  await page.waitForFunction(inputId=>{
    const el=document.getElementById(inputId);
    return !!el&&el.dataset.cvPadV73==='1'&&el.readOnly===true&&el.getAttribute('inputmode')==='none';
  },id,{timeout:5000,polling:50});
}

async function openPadByRealTap(page,id){
  // A render can legitimately replace workout row nodes. A human taps the currently
  // visible node, so resolve the element only after that short render train settles.
  await page.waitForTimeout(220);
  await waitForV73Decoration(page,id);
  await page.evaluate(inputId=>{
    const el=document.getElementById(inputId);
    el?.scrollIntoView?.({block:'center',inline:'nearest',behavior:'instant'});
  },id);
  await page.waitForTimeout(160);
  await waitForV73Decoration(page,id);
  const point=await page.evaluate(inputId=>{
    const el=document.getElementById(inputId);if(!el)return null;
    const r=el.getBoundingClientRect();
    return {x:r.left+r.width/2,y:r.top+r.height/2,width:r.width,height:r.height};
  },id);
  assert.ok(point&&point.width>0&&point.height>0,`No tappable V73 box for ${id}`);
  const hit=await page.evaluate(({x,y})=>document.elementFromPoint(x,y)?.id||document.elementFromPoint(x,y)?.className||'',point);
  assert.ok(String(hit).includes(id)||String(hit).includes('cv'),`Unexpected element over ${id}: ${hit}`);
  await page.touchscreen.tap(point.x,point.y);
  await page.waitForFunction(inputId=>{
    const s=window.CVWorkoutNumpadV73?.state?.();
    const root=document.getElementById('cvNumpadV73');
    return !!s?.open&&s.inputId===inputId&&root&&!root.classList.contains('hidden')&&root.getAttribute('aria-hidden')==='false';
  },id,{timeout:3000});
  await page.waitForTimeout(180);
  const settled=await page.evaluate(inputId=>({
    pad:window.CVWorkoutNumpadV73.state(),
    focused:document.activeElement?.id||'',
    hidden:document.getElementById('cvNumpadV73')?.classList.contains('hidden'),
    ariaHidden:document.getElementById('cvNumpadV73')?.getAttribute('aria-hidden'),
    decorated:document.getElementById(inputId)?.dataset.cvPadV73||'',
    inputMode:document.getElementById(inputId)?.getAttribute('inputmode'),
    readOnly:document.getElementById(inputId)?.readOnly
  }),id);
  assert.equal(settled.pad.open,true,`V73 pad closed after real tap event train for ${id}`);
  assert.equal(settled.pad.inputId,id,`V73 real tap settled on wrong input for ${id}`);
  assert.notEqual(settled.focused,id,`Native input focus survived real tap for ${id}`);
  assert.equal(settled.hidden,false,`V73 pad became hidden after real tap for ${id}`);
  assert.equal(settled.ariaHidden,'false',`V73 pad aria state regressed after real tap for ${id}`);
  assert.equal(settled.decorated,'1',`${id} lost V73 decoration after touch`);
  assert.equal(settled.inputMode,'none',`${id} reverted to native keyboard mode after touch`);
  assert.equal(settled.readOnly,true,`${id} reverted to editable native input after touch`);
}

async function tapLocatorCenter(page,locator,label){
  const box=await locator.boundingBox();
  assert.ok(box&&box.width>0&&box.height>0,`No tappable box for ${label}`);
  await page.touchscreen.tap(box.x+box.width/2,box.y+box.height/2);
}

async function pressPadKey(page,key){
  await tapLocatorCenter(page,page.locator(`[data-key="${key}"]`),`pad key ${key}`);
}

async function setWithPad(page,id,value,{realTap=true}={}){
  if(realTap){
    await openPadByRealTap(page,id);
  }else{
    const opened=await page.evaluate(inputId=>window.CVWorkoutNumpadV73.open(inputId),id);
    assert.equal(opened,true,`V73 failed to open ${id}`);
  }
  const active=await page.evaluate(()=>({pad:window.CVWorkoutNumpadV73.state(),focused:document.activeElement?.id||''}));
  assert.equal(active.pad.inputId,id,`V73 opened wrong input for ${id}`);
  assert.notEqual(active.focused,id,`Native input focus survived V73 open for ${id}`);
  const expectedScroll=Math.max(0,Number(active.pad.restoreY)||0);
  for(let i=0;i<8;i++)await pressPadKey(page,'back');
  for(const ch of String(value).replace('.',',')){
    if(ch===',')await pressPadKey(page,'decimal');
    else await pressPadKey(page,ch);
  }
  await tapLocatorCenter(page,page.locator('[data-pad-action="done"]'),'LISTO');
  await page.waitForFunction(inputId=>window.CVWorkoutNumpadV73.state().open===false&&document.getElementById(inputId)?.value!==undefined,id,{timeout:3000});
  await page.waitForTimeout(120);
  const result=await page.evaluate(inputId=>({value:document.getElementById(inputId)?.value,readOnly:document.getElementById(inputId)?.readOnly,inputMode:document.getElementById(inputId)?.getAttribute('inputmode'),scrollY:window.scrollY}),id);
  assert.equal(result.value,String(value),`V73 did not commit ${value} into ${id}`);
  assert.equal(result.readOnly,true,`${id} is not readonly under V73`);
  assert.equal(result.inputMode,'none',`${id} can still request native keyboard`);
  assert.ok(Math.abs(result.scrollY-expectedScroll)<=4,`V73 did not restore the workout page after editing ${id}: expected ${expectedScroll}, got ${result.scrollY}`);
}

async function realTouchEditorTest(){
  const t=await demoWorkoutPage('REAL_TOUCH');
  try{
    const {page,errors}=t;
    await setWithPad(page,'cvw_0_0','17.5');
    await setWithPad(page,'cvr_0_0','11');
    const values=await page.evaluate(()=>({w:document.getElementById('cvw_0_0')?.value,r:document.getElementById('cvr_0_0')?.value}));
    assert.deepEqual(values,{w:'17.5',r:'11'},'real touch editing did not persist KG/reps fields');
    assert.equal(errors.length,0,'Real-touch workout errors: '+errors.join(' | '));
    console.log('CV_V73_REAL_TOUCH_EDITOR_WEBKIT_OK');
  } finally {await t.context.close().catch(()=>{});await t.browser.close().catch(()=>{})}
}

async function explicitStartTest(){
  const t=await demoWorkoutPage('EXPLICIT');
  try{
    const {page,errors}=t;
    await setWithPad(page,'cvw_0_0','20');
    await setWithPad(page,'cvr_0_0','8');
    const started=await page.evaluate(()=>window.startWorkout());
    assert.equal(started,true,'explicit start did not resolve true');
    await page.waitForFunction(()=>window.CVWorkoutControllerV71?.diagnose?.().sessionId==='demo',null,{timeout:5000});
    const got=await page.evaluate(()=>{const s=window.cvExercises()?.[0]?.sets?.[0];return {w:s?.weight_kg,r:s?.reps}});
    assert.deepEqual(got,{w:20,r:8},'explicit start lost V73-edited values');
    assert.equal(errors.length,0,'Explicit workout errors: '+errors.join(' | '));
    console.log('CV_V73_EXPLICIT_START_WEBKIT_OK');
  } finally {await t.context.close().catch(()=>{});await t.browser.close().catch(()=>{})}
}

async function autoStartTest(){
  const t=await demoWorkoutPage('AUTO');
  try{
    const {page,errors}=t;
    await setWithPad(page,'cvw_0_0','22.5');
    await setWithPad(page,'cvr_0_0','9');
    const check=page.locator('.cvSetCheck').first();
    await tapLocatorCenter(page,check,'first set check');
    await page.waitForFunction(()=>window.CVWorkoutControllerV71?.diagnose?.().sessionId==='demo'&&window.cvExercises?.()?.[0]?.sets?.[0]?.completed===true,null,{timeout:5000});
    const got=await page.evaluate(()=>{const s=window.cvExercises()?.[0]?.sets?.[0];return {w:s?.weight_kg,r:s?.reps,c:s?.completed}});
    assert.deepEqual(got,{w:22.5,r:9,c:true},'first-set auto-start lost V73 values or completion');
    assert.equal(errors.length,0,'Auto-start workout errors: '+errors.join(' | '));
    console.log('CV_V73_AUTO_START_WEBKIT_OK');
  } finally {await t.context.close().catch(()=>{});await t.browser.close().catch(()=>{})}
}

await realTouchEditorTest();
await explicitStartTest();
await autoStartTest();
console.log('CV_MOBILE_WEBKIT_V71_V73_REAL_TOUCH_OK');
