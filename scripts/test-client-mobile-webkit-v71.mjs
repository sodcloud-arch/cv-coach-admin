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

async function setWithPad(page,id,value){
  const before=await page.evaluate(()=>window.scrollY);
  const opened=await page.evaluate(inputId=>window.CVWorkoutNumpadV73.open(inputId),id);
  assert.equal(opened,true,`V73 failed to open ${id}`);
  const active=await page.evaluate(()=>({pad:window.CVWorkoutNumpadV73.state(),focused:document.activeElement?.id||''}));
  assert.equal(active.pad.inputId,id,`V73 opened wrong input for ${id}`);
  assert.notEqual(active.focused,id,`Native input focus survived V73 open for ${id}`);
  await page.evaluate(()=>{for(let i=0;i<8;i++)document.querySelector('[data-key="back"]')?.click()});
  for(const ch of String(value).replace('.',',')){
    if(ch===',')await page.evaluate(()=>document.querySelector('[data-key="decimal"]')?.click());
    else await page.evaluate(k=>document.querySelector(`[data-key="${k}"]`)?.click(),ch);
  }
  await page.evaluate(()=>document.querySelector('[data-pad-action="done"]')?.click());
  await page.waitForFunction(inputId=>window.CVWorkoutNumpadV73.state().open===false&&document.getElementById(inputId)?.value!==undefined,id,{timeout:3000});
  const result=await page.evaluate(inputId=>({value:document.getElementById(inputId)?.value,readOnly:document.getElementById(inputId)?.readOnly,inputMode:document.getElementById(inputId)?.getAttribute('inputmode'),scrollY:window.scrollY}),id);
  assert.equal(result.value,String(value),`V73 did not commit ${value} into ${id}`);
  assert.equal(result.readOnly,true,`${id} is not readonly under V73`);
  assert.equal(result.inputMode,'none',`${id} can still request native keyboard`);
  assert.ok(Math.abs(result.scrollY-before)<=4,`V73 moved the workout page while editing ${id}: ${before} -> ${result.scrollY}`);
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
    await page.evaluate(()=>document.querySelector('.cvSetCheck')?.click());
    await page.waitForFunction(()=>window.CVWorkoutControllerV71?.diagnose?.().sessionId==='demo'&&window.cvExercises?.()?.[0]?.sets?.[0]?.completed===true,null,{timeout:5000});
    const got=await page.evaluate(()=>{const s=window.cvExercises()?.[0]?.sets?.[0];return {w:s?.weight_kg,r:s?.reps,c:s?.completed}});
    assert.deepEqual(got,{w:22.5,r:9,c:true},'first-set auto-start lost V73 values or completion');
    assert.equal(errors.length,0,'Auto-start workout errors: '+errors.join(' | '));
    console.log('CV_V73_AUTO_START_WEBKIT_OK');
  } finally {await t.context.close().catch(()=>{});await t.browser.close().catch(()=>{})}
}

await explicitStartTest();
await autoStartTest();
console.log('CV_MOBILE_WEBKIT_V71_V73_OK');
