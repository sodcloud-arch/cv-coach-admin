import { chromium } from 'playwright';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const base=(process.env.CV_TEST_URL||'http://127.0.0.1:4180').replace(/\/$/,'');
const target=`${base}/?cv_v102=1&v=107&qa=recovery`;
const browser=await chromium.launch();
const context=await browser.newContext({
  viewport:{width:390,height:844},
  isMobile:true,
  hasTouch:true,
  serviceWorkers:'block'
});
let page=await context.newPage();
const errors=[];
page.on('pageerror',error=>errors.push(String(error?.message||error)));

async function startDemo(){
  await page.waitForFunction(()=>window.CVSessionRecoveryV107?.version==='107',null,{timeout:10000});
  await page.evaluate(()=>document.getElementById('demoBtn')?.click());
  await page.waitForFunction(()=>!document.getElementById('app')?.classList.contains('hidden'),null,{timeout:5000});
  await page.evaluate(async()=>{if(typeof window.openDay==='function')await window.openDay('d1')});
  await page.waitForSelector('.cvWorkoutStartV40',{state:'visible',timeout:7000});
  await page.evaluate(()=>document.querySelector('.cvWorkoutStartV40')?.click());
  await page.waitForFunction(()=>document.body.classList.contains('cvWorkoutActiveV40'),null,{timeout:5000});
}

async function completeOne(){
  const row=page.locator('.cvV105ExerciseOpen .cvSetRow:not(.done):visible').first();
  await row.waitFor({state:'visible',timeout:5000});
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
  await startDemo();
  fs.mkdirSync('artifacts/v107-session-recovery',{recursive:true});

  await completeOne();
  await completeOne();
  await completeOne();

  await page.waitForFunction(()=>window.CVSessionRecoveryV107?.read()?.done===3,null,{timeout:5000});
  const saved=await page.evaluate(()=>window.CVSessionRecoveryV107.read());
  assert.equal(saved.version,'107');
  assert.equal(saved.mode,'demo');
  assert.equal(saved.userId,null,'Demo recovery must not persist a real user id');
  assert.equal(saved.dayId,'d1');
  assert.equal(saved.done,3);
  assert.equal(saved.total,15);
  assert.equal(saved.pct,20);
  assert.ok(Array.isArray(saved.demoExercises)&&saved.demoExercises.length===5,'Demo recovery must preserve demo exercise state');
  assert.equal(saved.demoExercises[0].sets.filter(s=>s.completed).length,3);
  assert.equal(saved.demoExercises[0].sets[0].weight_kg,20);
  assert.equal(saved.demoExercises[0].sets[0].reps,8);

  await page.screenshot({path:'artifacts/v107-session-recovery/01-before-reload.png',fullPage:false});

  let beforeUnloadSeen=false;
  page.once('dialog',async dialog=>{
    beforeUnloadSeen=dialog.type()==='beforeunload';
    await dialog.accept();
  });
  await page.reload({waitUntil:'domcontentloaded',timeout:30000});
  assert.equal(beforeUnloadSeen,true,'Active incomplete session must trigger browser unload protection');

  await page.waitForFunction(()=>window.CVSessionRecoveryV107?.version==='107',null,{timeout:10000});
  const afterReloadStored=await page.evaluate(()=>window.CVSessionRecoveryV107.read());
  assert.equal(afterReloadStored.done,3,'Reload must preserve the 3 completed demo sets');

  await page.evaluate(()=>document.getElementById('demoBtn')?.click());
  await page.waitForFunction(()=>!document.getElementById('app')?.classList.contains('hidden'),null,{timeout:5000});
  await page.waitForSelector('#cvSessionRecoveryV107',{state:'visible',timeout:5000});

  const prompt=await page.evaluate(()=>{
    const el=document.getElementById('cvSessionRecoveryV107');
    return {
      title:el?.querySelector('h2')?.textContent?.trim()||'',
      text:el?.textContent?.replace(/\s+/g,' ').trim()||'',
      focused:document.activeElement?.id||''
    };
  });
  assert.match(prompt.title,/entrenamiento sigue disponible/i);
  assert.match(prompt.text,/3\s*\/\s*15 SERIES/i);
  assert.match(prompt.text,/20%/i);
  assert.match(prompt.text,/DEMO guardó estas series/i);
  assert.equal(prompt.focused,'cvSessionRecoveryResumeV107');

  await page.screenshot({path:'artifacts/v107-session-recovery/02-recovery-prompt.png',fullPage:false});

  await page.locator('#cvSessionRecoveryResumeV107').click();
  await page.waitForFunction(()=>document.body.classList.contains('cvWorkoutActiveV40'),null,{timeout:7000});
  await page.waitForFunction(()=>document.querySelectorAll('.cvSetRow.done').length===3,null,{timeout:5000});

  const restored=await page.evaluate(()=>({
    done:document.querySelectorAll('.cvSetRow.done').length,
    total:document.querySelectorAll('.cvSetRow').length,
    current:document.querySelector('.cvV105ExerciseOpen .exerciseTop h3')?.textContent?.trim()||'',
    recoveredNotice:document.querySelector('.cvSessionRecoveredV107')?.textContent?.trim()||'',
    firstWeight:document.getElementById('cvw_0_0')?.value||'',
    firstReps:document.getElementById('cvr_0_0')?.value||''
  }));
  assert.equal(restored.done,3);
  assert.equal(restored.total,15);
  assert.match(restored.current,/Peso muerto rumano/i);
  assert.match(restored.recoveredNotice,/3\/15 SERIES CONSERVADAS/i);
  assert.equal(restored.firstWeight,'20');
  assert.equal(restored.firstReps,'8');

  await page.screenshot({path:'artifacts/v107-session-recovery/03-restored.png',fullPage:false});

  for(let i=0;i<12;i++)await completeOne();
  assert.equal(await page.locator('.cvSetRow.done').count(),15);

  await clickFinish();
  await page.waitForSelector('#cvV105DemoFeedback',{state:'visible',timeout:5000});
  await page.selectOption('#cvV105DemoRpe','8');
  await page.selectOption('#cvV105DemoFatigue','5');
  await page.selectOption('#cvV105DemoPain','0');
  await page.locator('#cvV105DemoFinish').click();

  await page.waitForSelector('#cvWorkoutResultModal',{state:'visible',timeout:5000});
  await page.waitForFunction(()=>window.CVSessionRecoveryV107?.read()===null,null,{timeout:4000});
  assert.equal(await page.evaluate(()=>localStorage.getItem('cv_workout_recovery_v107')),null,'Successful finish must clear recovery draft');

  await page.screenshot({path:'artifacts/v107-session-recovery/04-finished-cleared.png',fullPage:false});
  assert.equal(errors.length,0,'Browser errors: '+errors.join(' | '));

  console.log('CV_SESSION_RECOVERY_V107_OK',JSON.stringify({saved:{done:saved.done,total:saved.total,pct:saved.pct},prompt,restored}));
}finally{
  await context.close().catch(()=>{});
  await browser.close().catch(()=>{});
}
