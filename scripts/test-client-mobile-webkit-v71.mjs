import { webkit } from 'playwright';
import assert from 'node:assert/strict';

const base=process.env.CV_TEST_URL||'http://127.0.0.1:4173';
const browser=await webkit.launch();
const context=await browser.newContext({viewport:{width:390,height:844},isMobile:true,hasTouch:true});
const page=await context.newPage();
const pageErrors=[];
page.on('pageerror',e=>pageErrors.push(String(e?.message||e)));

try{
  await page.goto(base,{waitUntil:'domcontentloaded',timeout:30000});
  await page.locator('#demoBtn').click();
  await page.locator('#app:not(.hidden)').waitFor({state:'visible',timeout:10000});
  await page.evaluate(()=>window.openDay('d1'));
  await page.locator('.cvWorkoutStartV40').waitFor({state:'visible',timeout:10000});

  // Path A: explicit INICIAR ENTRENAMIENTO must synchronously enter demo session.
  await page.locator('#cvw_0_0').fill('20');
  await page.locator('#cvr_0_0').fill('8');
  const started=await page.evaluate(()=>window.startWorkout());
  assert.equal(started,true,'explicit start should return true');
  await page.waitForFunction(()=>window.CVWorkoutControllerV71?.diagnose?.().sessionId==='demo',null,{timeout:5000});
  assert.equal(await page.evaluate(()=>document.body.classList.contains('cvWorkoutActiveV40')),true,'active class missing after start');
  assert.equal(await page.locator('.cvWorkoutStartV40').count(),0,'start CTA remained after start');
  const preserved=await page.evaluate(()=>{const s=window.cvExercises?.()?.[0]?.sets?.[0];return {w:s?.weight_kg,r:s?.reps}});
  assert.deepEqual(preserved,{w:20,r:8},'pre-start values were not preserved');

  // Path B: first set check must auto-start a fresh pre-start workout and complete that set.
  await page.evaluate(()=>window.openDay('d1'));
  await page.locator('.cvWorkoutStartV40').waitFor({state:'visible',timeout:5000});
  await page.locator('#cvw_0_0').fill('22.5');
  await page.locator('#cvr_0_0').fill('9');
  await page.locator('.cvSetCheck').first().click();
  await page.waitForFunction(()=>window.CVWorkoutControllerV71?.diagnose?.().sessionId==='demo',null,{timeout:5000});
  await page.waitForFunction(()=>window.cvExercises?.()?.[0]?.sets?.[0]?.completed===true,null,{timeout:5000});
  const firstSet=await page.evaluate(()=>{const s=window.cvExercises?.()?.[0]?.sets?.[0];return {w:s?.weight_kg,r:s?.reps,c:s?.completed}});
  assert.deepEqual(firstSet,{w:22.5,r:9,c:true},'first-set auto-start did not preserve and complete values');

  assert.equal(pageErrors.length,0,'page errors: '+pageErrors.join(' | '));
  console.log('CV_MOBILE_WEBKIT_V71_OK');
} finally {
  await browser.close();
}
