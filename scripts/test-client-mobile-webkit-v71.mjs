import { webkit } from 'playwright';
import assert from 'node:assert/strict';

const base=process.env.CV_TEST_URL||'http://127.0.0.1:4173';
const browser=await webkit.launch();
browser.on('disconnected',()=>console.error('WEBKIT_BROWSER_DISCONNECTED'));
const context=await browser.newContext({
  viewport:{width:390,height:844},
  isMobile:true,
  hasTouch:true,
  serviceWorkers:'block'
});
context.setDefaultTimeout?.(10000);

async function demoWorkoutPage(label){
  const page=await context.newPage();
  page.setDefaultTimeout(10000);
  const errors=[],events=[];
  page.on('pageerror',e=>errors.push(String(e?.message||e)));
  page.on('console',m=>{const t=m.text();if(/CV V7|CV Coach|error|failed/i.test(t))events.push(`console:${m.type()}:${t}`)});
  page.on('close',()=>events.push('page:close'));
  page.on('crash',()=>events.push('page:crash'));
  await page.goto(base,{waitUntil:'domcontentloaded',timeout:30000});
  await page.evaluate(()=>document.getElementById('demoBtn')?.click());
  await page.locator('#app:not(.hidden)').waitFor({state:'visible',timeout:10000});
  await page.evaluate(()=>window.openDay('d1'));
  await page.locator('.cvWorkoutStartV40').waitFor({state:'visible',timeout:10000});
  console.log(`${label}_READY`);
  return {page,errors,events};
}

async function deterministicScrollToInput(page,id){
  await page.evaluate(inputId=>{
    const el=document.getElementById(inputId);
    if(!el)throw new Error(`Input ${inputId} missing`);
    const absoluteTop=el.getBoundingClientRect().top+window.scrollY;
    window.scrollTo(0,Math.max(0,absoluteTop-300));
  },id);
  await page.waitForTimeout(80);
}

async function setWorkoutInput(page,id,value){
  await page.evaluate(({id,value})=>{
    const el=document.getElementById(id);
    if(!el)throw new Error(`Input ${id} missing`);
    el.value=String(value);
    el.dispatchEvent(new Event('input',{bubbles:true}));
    el.dispatchEvent(new Event('change',{bubbles:true}));
  },{id,value});
}

try{
  // Path A: explicit INICIAR ENTRENAMIENTO + the same focusout lifecycle used by iOS Done/Listo.
  const a=await demoWorkoutPage('PATH_A');
  const page=a.page;
  await deterministicScrollToInput(page,'cvw_0_0');
  const scrollBefore=await page.evaluate(()=>window.scrollY);

  // Use DOM focus instead of Playwright actionability: the app intentionally has continuous
  // mutation/render observers, which can keep a locator from ever reaching Playwright's
  // synthetic "stable" state even though Safari can focus the input normally.
  await page.evaluate(()=>document.getElementById('cvw_0_0')?.focus({preventScroll:true}));
  await page.waitForTimeout(850);
  const scrollStable=await page.evaluate(()=>window.scrollY);

  // Emulate the page displacement caused by iOS shrinking/settling its visual viewport.
  await page.evaluate(()=>window.scrollBy(0,170));
  const scrollShifted=await page.evaluate(()=>window.scrollY);
  await page.evaluate(()=>document.activeElement?.blur());
  await page.waitForTimeout(820);
  const scrollAfter=await page.evaluate(()=>window.scrollY);
  console.log(`PATH_A_SCROLL before=${scrollBefore} stable=${scrollStable} shifted=${scrollShifted} after=${scrollAfter}`);
  assert.ok(Math.abs(scrollAfter-scrollBefore)<=8,`Done/blur did not restore scroll: before=${scrollBefore} after=${scrollAfter}`);
  assert.equal(await page.evaluate(()=>window.CVIOSKeyboardV72?.version),'v72','V72 keyboard guard missing');

  await setWorkoutInput(page,'cvw_0_0','20');
  await setWorkoutInput(page,'cvr_0_0','8');
  const started=await page.evaluate(()=>window.startWorkout());
  assert.equal(started,true,'explicit start should return true');
  await page.waitForFunction(()=>window.CVWorkoutControllerV71?.diagnose?.().sessionId==='demo',null,{timeout:5000});
  assert.equal(await page.evaluate(()=>document.body.classList.contains('cvWorkoutActiveV40')),true,'active class missing after start');
  assert.equal(await page.locator('.cvWorkoutStartV40').count(),0,'start CTA remained after start');
  const preserved=await page.evaluate(()=>{const s=window.cvExercises?.()?.[0]?.sets?.[0];return {w:s?.weight_kg,r:s?.reps}});
  assert.deepEqual(preserved,{w:20,r:8},'pre-start values were not preserved');
  assert.equal(a.errors.length,0,'Path A page errors: '+a.errors.join(' | '));
  console.log('PATH_A_OK '+a.events.join(','));
  await page.close();

  // Path B: a fresh page. First set check must auto-start and complete the set.
  const b=await demoWorkoutPage('PATH_B');
  const pageB=b.page;
  await setWorkoutInput(pageB,'cvw_0_0','22.5');
  await setWorkoutInput(pageB,'cvr_0_0','9');
  await pageB.evaluate(()=>document.querySelector('.cvSetCheck')?.click());
  await pageB.waitForFunction(()=>window.CVWorkoutControllerV71?.diagnose?.().sessionId==='demo',null,{timeout:5000});
  await pageB.waitForFunction(()=>window.cvExercises?.()?.[0]?.sets?.[0]?.completed===true,null,{timeout:5000});
  const firstSet=await pageB.evaluate(()=>{const s=window.cvExercises?.()?.[0]?.sets?.[0];return {w:s?.weight_kg,r:s?.reps,c:s?.completed}});
  assert.deepEqual(firstSet,{w:22.5,r:9,c:true},'first-set auto-start did not preserve and complete values');
  assert.equal(b.errors.length,0,'Path B page errors: '+b.errors.join(' | '));
  console.log('PATH_B_OK '+b.events.join(','));
  await pageB.close();

  console.log('CV_MOBILE_WEBKIT_V71_V72_OK');
} finally {
  await context.close().catch(()=>{});
  await browser.close().catch(()=>{});
}
