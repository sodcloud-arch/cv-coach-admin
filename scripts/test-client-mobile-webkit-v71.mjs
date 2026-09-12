import { webkit } from 'playwright';
import assert from 'node:assert/strict';

const base=process.env.CV_TEST_URL||'http://127.0.0.1:4173';
const browser=await webkit.launch();
const context=await browser.newContext({viewport:{width:390,height:844},isMobile:true,hasTouch:true});

async function demoWorkoutPage(){
  const page=await context.newPage();
  const errors=[];
  page.on('pageerror',e=>errors.push(String(e?.message||e)));
  await page.goto(base,{waitUntil:'domcontentloaded',timeout:30000});
  await page.locator('#demoBtn').click();
  await page.locator('#app:not(.hidden)').waitFor({state:'visible',timeout:10000});
  await page.evaluate(()=>window.openDay('d1'));
  await page.locator('.cvWorkoutStartV40').waitFor({state:'visible',timeout:10000});
  return {page,errors};
}

try{
  // Path A: explicit INICIAR ENTRENAMIENTO + iOS-style Done/blur viewport restoration.
  const a=await demoWorkoutPage();
  const page=a.page;
  const kg=page.locator('#cvw_0_0');
  await kg.scrollIntoViewIfNeeded();
  const scrollBefore=await page.evaluate(()=>window.scrollY);
  await kg.click();
  await page.waitForTimeout(850); // allow legacy center-scroll + V72 stabilizer to run
  await page.evaluate(()=>document.activeElement?.blur()); // equivalent lifecycle to tapping Done/Listo
  await page.waitForTimeout(760); // allow Safari-style viewport settle + V72 multi-restore
  const scrollAfter=await page.evaluate(()=>window.scrollY);
  assert.ok(Math.abs(scrollAfter-scrollBefore)<=6,`Done/blur did not restore scroll: before=${scrollBefore} after=${scrollAfter}`);
  assert.equal(await page.evaluate(()=>window.CVIOSKeyboardV72?.version),'v72','V72 keyboard guard missing');

  await page.locator('#cvw_0_0').fill('20');
  await page.locator('#cvr_0_0').fill('8');
  const started=await page.evaluate(()=>window.startWorkout());
  assert.equal(started,true,'explicit start should return true');
  await page.waitForFunction(()=>window.CVWorkoutControllerV71?.diagnose?.().sessionId==='demo',null,{timeout:5000});
  assert.equal(await page.evaluate(()=>document.body.classList.contains('cvWorkoutActiveV40')),true,'active class missing after start');
  assert.equal(await page.locator('.cvWorkoutStartV40').count(),0,'start CTA remained after start');
  const preserved=await page.evaluate(()=>{const s=window.cvExercises?.()?.[0]?.sets?.[0];return {w:s?.weight_kg,r:s?.reps}});
  assert.deepEqual(preserved,{w:20,r:8},'pre-start values were not preserved');
  assert.equal(a.errors.length,0,'Path A page errors: '+a.errors.join(' | '));
  await page.close();

  // Path B: fresh page. First set check must auto-start and complete the set.
  // Using a fresh page prevents a previous active demo session from contaminating this scenario.
  const b=await demoWorkoutPage();
  const pageB=b.page;
  await pageB.locator('#cvw_0_0').fill('22.5');
  await pageB.locator('#cvr_0_0').fill('9');
  await pageB.locator('.cvSetCheck').first().click();
  await pageB.waitForFunction(()=>window.CVWorkoutControllerV71?.diagnose?.().sessionId==='demo',null,{timeout:5000});
  await pageB.waitForFunction(()=>window.cvExercises?.()?.[0]?.sets?.[0]?.completed===true,null,{timeout:5000});
  const firstSet=await pageB.evaluate(()=>{const s=window.cvExercises?.()?.[0]?.sets?.[0];return {w:s?.weight_kg,r:s?.reps,c:s?.completed}});
  assert.deepEqual(firstSet,{w:22.5,r:9,c:true},'first-set auto-start did not preserve and complete values');
  assert.equal(b.errors.length,0,'Path B page errors: '+b.errors.join(' | '));
  await pageB.close();

  console.log('CV_MOBILE_WEBKIT_V71_V72_OK');
} finally {
  await browser.close();
}
