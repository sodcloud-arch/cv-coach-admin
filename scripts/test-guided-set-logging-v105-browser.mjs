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
  await page.evaluate(async()=>{try{if(document.fonts?.ready)await document.fonts.ready}catch(_){}});
  await page.waitForFunction(()=>{
    const button=document.querySelector('.cvWorkoutStartV40');
    if(!button)return false;
    const height=button.getBoundingClientRect().height;
    return height>=42&&height<=48;
  },null,{timeout:5000});

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
      executionButtonVisible:(()=>{const b=row.closest('.cvHevyExercise,.workoutExercise')?.querySelector('.cvExecutionBtnV35');return !!b&&b.offsetWidth>0&&b.offsetHeight>0&&getComputedStyle(b).display!=='none'})(),
      detailsSeparated:(()=>{const card=row.closest('.cvHevyExercise,.workoutExercise');const title=card?.querySelector('.cvDetailsTitleRowV103 h3,.cvExerciseTitleRowV35 h3');const details=card?.querySelector('.cvDetailsLinkV103');if(!title||!details)return false;const tr=title.getBoundingClientRect(),dr=details.getBoundingClientRect();return dr.top>=tr.bottom-2})(),
      mediaHeight:(()=>{const m=row.closest('.cvHevyExercise,.workoutExercise')?.querySelector(':scope>.exerciseMedia');return m?m.getBoundingClientRect().height:0})(),
      prestartClass:document.body.classList.contains('cvWorkoutPrestartV40'),
      prestartHeroHeight:(()=>{const hero=document.querySelector('.cvWorkoutHeroV31');return hero?hero.getBoundingClientRect().height:0})(),
      startCtaHeight:(()=>{const b=document.querySelector('.cvWorkoutStartV40');return b?b.getBoundingClientRect().height:0})()
    };
  });

  await page.waitForFunction(()=>{
    const img=document.querySelector('.cvV105ExerciseOpen > .exerciseMedia .photo');
    return !img || (img.complete && img.naturalWidth>0);
  },null,{timeout:5000}).catch(()=>{});
  fs.mkdirSync('artifacts',{recursive:true});
  try{
    await page.screenshot({path:'artifacts/v105-mobile-current.png',fullPage:false,timeout:7000});
    console.log('CV_V105_SCREENSHOT_WRITTEN artifacts/v105-mobile-current.png');
  }catch(error){
    console.warn('CV_V105_SCREENSHOT_SKIPPED',String(error?.message||error));
  }

  assert.equal(initial.htmlVersion,'105.4');
  assert.equal(initial.bodyClass,true);
  assert.equal(initial.hasHint,false,'V105.4 keeps redundant logging hint removed');
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
  assert.equal(initial.detailsSeparated,true,'VER DETALLES must be visually separated from exercise title');
  assert.ok(initial.mediaHeight<=212,'Current exercise media should be compact enough to keep series visible');
  assert.equal(initial.prestartClass,true,'Demo workout should be in compact prestart state before start');
  assert.ok(initial.prestartHeroHeight>0&&initial.prestartHeroHeight<=230,'Prestart summary should be compact on mobile');
  assert.ok(initial.startCtaHeight>=42&&initial.startCtaHeight<=48,`Start CTA should stay prominent without consuming excess height; measured ${initial.startCtaHeight}px`);

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

  console.log('CV_GUIDED_SET_LOGGING_V105_BROWSER_OK',JSON.stringify(initial));
}finally{
  await context.close().catch(()=>{});
  await browser.close().catch(()=>{});
}
