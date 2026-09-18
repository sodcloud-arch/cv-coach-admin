import { webkit } from 'playwright';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const base=(process.env.CV_TEST_URL||'http://127.0.0.1:4173').replace(/\/$/,'');
const target=`${base}/?cv_v102=1&v=105`;
const browser=await webkit.launch();
const context=await browser.newContext({
  viewport:{width:390,height:844},
  isMobile:true,
  hasTouch:true,
  serviceWorkers:'block'
});
const page=await context.newPage();
const errors=[];
page.on('pageerror',error=>errors.push(String(error?.message||error)));

try{
  await page.goto(target,{waitUntil:'domcontentloaded',timeout:30000});
  await page.waitForFunction(()=>window.CVInlineSetEntryV104?.version==='104',null,{timeout:10000});
  await page.waitForFunction(()=>window.CVGuidedSetLoggingV105?.version==='105',null,{timeout:10000});
  await page.evaluate(()=>document.getElementById('demoBtn')?.click());
  await page.waitForFunction(()=>!document.getElementById('app')?.classList.contains('hidden'),null,{timeout:5000});
  await page.waitForFunction(()=>{
    try{
      if(document.querySelector('.cvSetRow'))return true;
      if(typeof window.openDay==='function')window.openDay('d1');
      return !!document.querySelector('.cvSetRow');
    }catch(_){return false}
  },null,{timeout:7000,polling:100});
  await page.waitForFunction(()=>[...document.querySelectorAll('.cvSetRow')].some(row=>row.offsetWidth>0&&row.offsetHeight>0),null,{timeout:5000});
  await page.waitForFunction(()=>document.querySelector('.cvSetRow.cvV105Next'),null,{timeout:5000});

  const initial=await page.evaluate(()=>{
    const row=[...document.querySelectorAll('.cvSetRow.cvV105Next')].find(el=>el.offsetWidth>0&&el.offsetHeight>0);
    if(!row)throw new Error('No visible V105 next row');
    const w=row.querySelector('input[id^="cvw_"]');
    const r=row.querySelector('input[id^="cvr_"]');
    const check=row.querySelector('.cvSetCheck');
    return {
      htmlVersion:document.documentElement.getAttribute('data-cv-guided-set-logging'),
      bodyClass:document.body.classList.contains('cvGuidedSetLoggingV105'),
      hasHint:!!row.closest('.cvHevyExercise,.workoutExercise')?.querySelector('.cvV105LoggingHint'),
      weightId:w?.id||'',
      repsId:r?.id||'',
      weightLabel:w?.getAttribute('aria-label')||'',
      repsLabel:r?.getAttribute('aria-label')||'',
      checkLabel:check?.getAttribute('aria-label')||'',
      weightFont:w?getComputedStyle(w).fontSize:'',
      repsFont:r?getComputedStyle(r).fontSize:'',
      mediaVisible:!!row.closest('.cvHevyExercise,.workoutExercise')?.querySelector(':scope>.exerciseMedia') && (()=>{const m=row.closest('.cvHevyExercise,.workoutExercise')?.querySelector(':scope>.exerciseMedia');const s=getComputedStyle(m);return m.offsetWidth>0&&m.offsetHeight>0&&s.display!=='none'})(),
      imageVisible:(()=>{const img=row.closest('.cvHevyExercise,.workoutExercise')?.querySelector(':scope>.exerciseMedia .photo');return !!img&&img.offsetWidth>0&&img.offsetHeight>0&&getComputedStyle(img).display!=='none'})(),
      executionButtonVisible:(()=>{const b=row.closest('.cvHevyExercise,.workoutExercise')?.querySelector('.cvExecutionBtnV35');return !!b&&b.offsetWidth>0&&b.offsetHeight>0&&getComputedStyle(b).display!=='none'})()
    };
  });

  assert.equal(initial.htmlVersion,'105.1');
  assert.equal(initial.bodyClass,true);
  assert.equal(initial.hasHint,true);
  assert.match(initial.weightId,/^cvw_/);
  assert.match(initial.repsId,/^cvr_/);
  assert.match(initial.weightLabel,/Peso.*serie/i);
  assert.match(initial.repsLabel,/(Repeticiones|tiempo|segundos).*serie|serie.*(Repeticiones|tiempo|segundos)/i);
  assert.match(initial.checkLabel,/serie/i);
  assert.ok(parseFloat(initial.weightFont)>=19);
  assert.ok(parseFloat(initial.repsFont)>=19);
  assert.equal(initial.mediaVisible,true,'Current exercise media must be visible automatically');
  assert.equal(initial.imageVisible,true,'Current exercise image must be visible automatically in demo');
  assert.equal(initial.executionButtonVisible,false,'Current exercise must not require VER EJECUCIÓN');

  const weight=page.locator('.cvSetRow.cvV105Next input[id^="cvw_"]:visible').first();
  const reps=page.locator('.cvSetRow.cvV105Next input[id^="cvr_"]:visible').first();
  await weight.focus();
  await page.keyboard.press('Enter');
  assert.equal(await reps.evaluate(el=>document.activeElement===el),true,'Enter on KG must move to REPS');

  await page.keyboard.press('Enter');
  const checkFocused=await page.evaluate(()=>{
    const row=[...document.querySelectorAll('.cvSetRow.cvV105Next')].find(el=>el.offsetWidth>0&&el.offsetHeight>0);
    return document.activeElement===row?.querySelector('.cvSetCheck');
  });
  assert.equal(checkFocused,true,'Enter on REPS must move focus to completion control');

  const modalOpen=await page.evaluate(()=>!!document.querySelector('.cvTechBackdrop.show,.cvPadBackdrop.show,[role="dialog"].show'));
  assert.equal(modalOpen,false,'V105 logging flow must remain inline');
  assert.equal(errors.length,0,'Browser errors: '+errors.join(' | '));

  fs.mkdirSync('artifacts',{recursive:true});
  const currentCard=page.locator('.cvV105ExerciseOpen:visible').first();
  await currentCard.scrollIntoViewIfNeeded();
  await page.waitForTimeout(250);
  await page.screenshot({path:'artifacts/v105-mobile-current.png',fullPage:false});
  console.log('CV_V105_SCREENSHOT_WRITTEN artifacts/v105-mobile-current.png');
  console.log('CV_GUIDED_SET_LOGGING_V105_BROWSER_OK',JSON.stringify(initial));
}finally{
  await context.close().catch(()=>{});
  await browser.close().catch(()=>{});
}
