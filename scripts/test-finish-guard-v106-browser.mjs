import { chromium } from 'playwright';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const base=(process.env.CV_TEST_URL||'http://127.0.0.1:4178').replace(/\/$/,'');
const target=`${base}/?cv_v102=1&v=106&qa=finish-guard`;
const browser=await chromium.launch();
const context=await browser.newContext({
  viewport:{width:390,height:844},
  isMobile:true,
  hasTouch:true,
  serviceWorkers:'block'
});
const page=await context.newPage();
const errors=[];
page.on('pageerror',e=>errors.push(String(e?.message||e)));

async function currentIncompleteRow(){
  const row=page.locator('.cvV105ExerciseOpen .cvSetRow:not(.done):visible').first();
  await row.waitFor({state:'visible',timeout:5000});
  return row;
}

async function completeOne(){
  const row=await currentIncompleteRow();
  const reps=row.locator('input[id^="cvr_"]');
  const weight=row.locator('input[id^="cvw_"]');
  if(await reps.count())await reps.fill('8');
  if(await weight.count())await weight.fill('20');
  const anchorId=(await reps.count())?await reps.getAttribute('id'):await weight.getAttribute('id');
  await row.locator('.cvSetCheck').click();
  await page.waitForFunction(id=>{
    const anchor=id?document.getElementById(id):null;
    return !!anchor?.closest('.cvSetRow')?.classList.contains('done');
  },anchorId,{timeout:4000});
  const skip=page.locator('#cvRestVisualSkip');
  if(await skip.isVisible().catch(()=>false)){
    await skip.click();
    await page.waitForFunction(()=>document.getElementById('cvRestVisualV32')?.classList.contains('hidden'),null,{timeout:3000});
  }
}

async function clickFinish(){
  await page.evaluate(()=>{
    const button=[...document.querySelectorAll('.workoutTop button')].find(b=>/FINALIZAR/i.test(b.textContent||''));
    if(!button)throw new Error('FINALIZAR button not found');
    button.click();
  });
}

try{
  await page.goto(target,{waitUntil:'domcontentloaded',timeout:30000});
  await page.waitForFunction(()=>window.CVGuidedSetLoggingV105?.revision==='105.5',null,{timeout:10000});
  await page.waitForFunction(()=>window.CVFinishGuardV106?.version==='106',null,{timeout:10000});

  await page.evaluate(()=>document.getElementById('demoBtn')?.click());
  await page.waitForFunction(()=>!document.getElementById('app')?.classList.contains('hidden'),null,{timeout:5000});
  await page.evaluate(async()=>{if(typeof window.openDay==='function')await window.openDay('d1')});
  await page.waitForSelector('.cvWorkoutStartV40',{state:'visible',timeout:7000});
  await page.evaluate(()=>document.querySelector('.cvWorkoutStartV40')?.click());
  await page.waitForFunction(()=>document.body.classList.contains('cvWorkoutActiveV40'),null,{timeout:5000});

  fs.mkdirSync('artifacts/v106-finish-guard',{recursive:true});

  await completeOne();
  await completeOne();
  await completeOne();

  const partial=await page.evaluate(()=>({
    done:document.querySelectorAll('.cvSetRow.done').length,
    total:document.querySelectorAll('.cvSetRow').length,
    current:document.querySelector('.cvV105ExerciseOpen .exerciseTop h3')?.textContent?.trim()||'',
    compact:document.querySelector('.cvWorkoutCompactCopyV40')?.textContent?.replace(/\s+/g,' ').trim()||''
  }));
  assert.equal(partial.done,3);
  assert.equal(partial.total,15);
  assert.match(partial.current,/Peso muerto rumano/i);
  assert.match(partial.compact,/3\s*\/\s*15.*series/i);

  await clickFinish();
  const guard=page.locator('#cvFinishGuardV106');
  await guard.waitFor({state:'visible',timeout:5000});

  const guardState=await guard.evaluate(el=>({
    modal:el.querySelector('[role="dialog"]')?.getAttribute('aria-modal')||'',
    title:el.querySelector('h2')?.textContent?.trim()||'',
    text:el.textContent?.replace(/\s+/g,' ').trim()||'',
    continueFocused:document.activeElement?.id==='cvFinishGuardContinueV106'
  }));
  assert.equal(guardState.modal,'true');
  assert.match(guardState.title,/series pendientes/i);
  assert.match(guardState.text,/3\s*\/\s*15 SERIES/i);
  assert.match(guardState.text,/20% completado/i);
  assert.match(guardState.text,/12 series pendientes/i);
  assert.equal(guardState.continueFocused,true,'Continue training must receive initial focus');

  await page.screenshot({path:'artifacts/v106-finish-guard/01-partial-guard.png',fullPage:false});

  await page.locator('#cvFinishGuardContinueV106').click();
  await guard.waitFor({state:'detached',timeout:3000});
  await page.waitForTimeout(350);

  const continued=await page.evaluate(()=>({
    active:document.body.classList.contains('cvWorkoutActiveV40'),
    feedback:!!document.getElementById('cvV105DemoFeedback'),
    current:document.querySelector('.cvV105ExerciseOpen .exerciseTop h3')?.textContent?.trim()||'',
    done:document.querySelectorAll('.cvSetRow.done').length
  }));
  assert.equal(continued.active,true);
  assert.equal(continued.feedback,false);
  assert.match(continued.current,/Peso muerto rumano/i);
  assert.equal(continued.done,3);

  await clickFinish();
  await guard.waitFor({state:'visible',timeout:5000});
  await page.locator('#cvFinishGuardConfirmV106').click();

  const feedback=page.locator('#cvV105DemoFeedback');
  await feedback.waitFor({state:'visible',timeout:5000});
  assert.equal(await guard.count(),0,'Finish guard must close before post-workout feedback opens');

  const feedbackState=await feedback.evaluate(el=>({
    notice:el.querySelector('.cvV105DemoNotice')?.textContent?.replace(/\s+/g,' ').trim()||'',
    title:el.querySelector('h2')?.textContent?.trim()||''
  }));
  assert.match(feedbackState.notice,/NO ESCRIBE DATOS REALES/i);
  assert.match(feedbackState.title,/Cómo se sintió/i);

  await page.screenshot({path:'artifacts/v106-finish-guard/02-finish-anyway-feedback.png',fullPage:false});

  await page.locator('#cvV105DemoBack').click();
  await feedback.waitFor({state:'detached',timeout:3000});
  assert.equal(await page.evaluate(()=>document.body.classList.contains('cvWorkoutActiveV40')),true);
  assert.equal(await page.locator('.cvSetRow.done').count(),3,'Returning from feedback must preserve partial workout state');

  assert.equal(errors.length,0,'Browser errors: '+errors.join(' | '));
  console.log('CV_FINISH_GUARD_V106_OK',JSON.stringify({partial,guardState,continued,feedbackState}));
}finally{
  await context.close().catch(()=>{});
  await browser.close().catch(()=>{});
}
