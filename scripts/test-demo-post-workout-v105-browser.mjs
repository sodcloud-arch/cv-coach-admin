import { chromium } from 'playwright';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const base=(process.env.CV_TEST_URL||'http://127.0.0.1:4175').replace(/\/$/,'');
const target=`${base}/?cv_v102=1&v=105&qa=finish`;
const browser=await chromium.launch();
const context=await browser.newContext({viewport:{width:390,height:844},isMobile:true,hasTouch:true,serviceWorkers:'block'});
const page=await context.newPage();
const errors=[];
let watchWrites=false;
const writeRequests=[];

page.on('pageerror',e=>errors.push(String(e?.message||e)));
page.on('request',req=>{
  if(!watchWrites)return;
  const url=req.url(),method=req.method();
  if(/fmhcansyxcsqkrivqchr\.supabase\.co/i.test(url)&&/POST|PATCH|PUT|DELETE/i.test(method)){
    writeRequests.push({method,url});
  }
});

async function startDemo(){
  await page.goto(target,{waitUntil:'domcontentloaded',timeout:30000});
  await page.waitForFunction(()=>window.CVGuidedSetLoggingV105?.revision==='105.5',null,{timeout:10000});
  await page.evaluate(()=>document.getElementById('demoBtn')?.click());
  await page.waitForFunction(()=>!document.getElementById('app')?.classList.contains('hidden'),null,{timeout:5000});
  await page.evaluate(async()=>{if(typeof window.openDay==='function')await window.openDay('d1')});
  await page.waitForSelector('.cvWorkoutStartV40',{state:'visible',timeout:7000});
  await page.locator('.cvWorkoutStartV40').click();
  await page.waitForFunction(()=>document.body.classList.contains('cvWorkoutActiveV40'),null,{timeout:5000});
}

async function completeOne(){
  const row=page.locator('.cvV105ExerciseOpen .cvSetRow:not(.done):visible').first();
  await row.waitFor({state:'visible',timeout:5000});
  const reps=row.locator('input[id^="cvr_"]');
  if(await reps.count())await reps.fill('8');
  const weight=row.locator('input[id^="cvw_"]');
  if(await weight.count())await weight.fill('20');
  const check=row.locator('.cvSetCheck');
  const id=(await reps.count())?await reps.getAttribute('id'):await weight.getAttribute('id');
  await check.click();
  await page.waitForFunction(anchorId=>{
    const anchor=anchorId?document.getElementById(anchorId):null;
    const live=anchor?.closest('.cvSetRow');
    return !!live?.classList.contains('done');
  },id,{timeout:4000});
  const skip=page.locator('#cvRestVisualSkip');
  if(await skip.isVisible().catch(()=>false)){
    await skip.click();
    await page.waitForFunction(()=>document.getElementById('cvRestVisualV32')?.classList.contains('hidden'),null,{timeout:3000});
  }
}

try{
  await startDemo();
  fs.mkdirSync('artifacts/v105-post-workout',{recursive:true});

  for(let i=0;i<15;i++)await completeOne();

  const completed=await page.evaluate(()=>({
    done:document.querySelectorAll('.cvSetRow.done').length,
    total:document.querySelectorAll('.cvSetRow').length,
    compact:document.querySelector('.cvWorkoutCompactCopyV40')?.textContent?.replace(/\s+/g,' ').trim()||''
  }));
  assert.equal(completed.done,15);
  assert.equal(completed.total,15);
  assert.match(completed.compact,/15\s*\/\s*15.*series/i);

  watchWrites=true;
  const finish=page.locator('.workoutTop button').filter({hasText:/FINALIZAR/i}).first();
  await finish.click();
  const feedback=page.locator('#cvV105DemoFeedback');
  await feedback.waitFor({state:'visible',timeout:5000});

  const feedbackState=await feedback.evaluate(el=>({
    notice:el.querySelector('.cvV105DemoNotice')?.textContent?.replace(/\s+/g,' ').trim()||'',
    title:el.querySelector('h2')?.textContent?.trim()||'',
    dialog:el.querySelector('[role="dialog"]')?.getAttribute('aria-modal')||''
  }));
  assert.match(feedbackState.notice,/NO ESCRIBE DATOS REALES/i);
  assert.match(feedbackState.title,/Cómo se sintió/i);
  assert.equal(feedbackState.dialog,'true');

  await page.screenshot({path:'artifacts/v105-post-workout/01-feedback.png',fullPage:false});

  await page.selectOption('#cvV105DemoRpe','8');
  await page.selectOption('#cvV105DemoFatigue','5');
  await page.selectOption('#cvV105DemoPain','0');
  await page.fill('#cvV105DemoNotes','Sesión demo QA');
  await page.locator('#cvV105DemoFinish').click();

  await page.waitForSelector('#cvWorkoutResultModal',{state:'visible',timeout:5000});
  await page.waitForFunction(()=>document.querySelector('#cvWorkoutResultModal .cvV105DemoNotice'),null,{timeout:3000});

  const result=await page.evaluate(()=>{
    const modal=document.getElementById('cvWorkoutResultModal');
    const metrics=[...modal.querySelectorAll('.cvResultMetric')].map(x=>x.textContent.replace(/\s+/g,' ').trim());
    return {
      notice:modal.querySelector('.cvV105DemoNotice')?.textContent?.replace(/\s+/g,' ').trim()||'',
      title:modal.querySelector('.cvResultHero h2')?.textContent?.trim()||'',
      metrics,
      bodyHome:!document.body.classList.contains('cvWorkoutActiveV40'),
      resultVisible:modal.offsetWidth>0&&modal.offsetHeight>0
    };
  });

  assert.equal(result.resultVisible,true);
  assert.match(result.notice,/RESULTADOS SIMULADOS/i);
  assert.match(result.title,/ENTRENAMIENTO COMPLETADO/i);
  assert.ok(result.metrics.some(x=>/Finalización\s*100%/i.test(x)),'Summary must show 100% completion');
  assert.ok(result.metrics.some(x=>/Volumen\s*2\.400 kg/i.test(x)||/Volumen\s*2400 kg/i.test(x)),'Summary must show demo volume');
  assert.equal(result.bodyHome,true,'Demo should return to home behind the result summary');
  assert.equal(writeRequests.length,0,'Demo finalization must not issue Supabase write requests: '+JSON.stringify(writeRequests));
  assert.equal(errors.length,0,'Browser errors: '+errors.join(' | '));

  await page.screenshot({path:'artifacts/v105-post-workout/02-result.png',fullPage:false});
  console.log('CV_DEMO_POST_WORKOUT_V105_OK',JSON.stringify({completed,feedbackState,result}));
}finally{
  await context.close().catch(()=>{});
  await browser.close().catch(()=>{});
}
