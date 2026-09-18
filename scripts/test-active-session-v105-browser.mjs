import { chromium, webkit } from 'playwright';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const base=(process.env.CV_TEST_URL||'http://127.0.0.1:4173').replace(/\/$/,'');
const target=`${base}/?cv_v102=1&v=105&qa=active`;
const engine=String(process.env.CV_BROWSER||'chromium').toLowerCase()==='webkit'?webkit:chromium;
const browser=await engine.launch();
const context=await browser.newContext({
  viewport:{width:390,height:844},
  isMobile:true,
  hasTouch:true,
  serviceWorkers:'block'
});
const page=await context.newPage();
const errors=[];
page.on('pageerror',error=>errors.push(String(error?.message||error)));

const visible = async locator => locator.evaluate(el=>{
  const r=el.getBoundingClientRect(),s=getComputedStyle(el);
  return r.width>0&&r.height>0&&s.display!=='none'&&s.visibility!=='hidden';
});

async function currentCard(){
  const locator=page.locator('.cvV105ExerciseOpen:visible').first();
  await locator.waitFor({state:'visible',timeout:5000});
  return locator;
}

async function nextIncompleteRow(card){
  const rows=card.locator('.cvSetRow:visible');
  const count=await rows.count();
  for(let i=0;i<count;i++){
    const row=rows.nth(i);
    const done=await row.evaluate(el=>el.classList.contains('done'));
    if(!done)return row;
  }
  return null;
}

async function completeCurrentSet(){
  const card=await currentCard();
  const row=await nextIncompleteRow(card);
  assert.ok(row,'Expected an incomplete row in current exercise');

  const reps=row.locator('input[id^="cvr_"]');
  if(await reps.count()){
    const value=await reps.inputValue();
    if(!value)await reps.fill('8');
  }
  const weight=row.locator('input[id^="cvw_"]');
  if(await weight.count()){
    const value=await weight.inputValue();
    if(!value)await weight.fill('20');
  }

  const check=row.locator('.cvSetCheck');
  await check.click();
  await page.waitForFunction(el=>el?.classList.contains('done'),await row.elementHandle(),{timeout:4000});
  await page.waitForFunction(el=>el?.getAttribute('aria-pressed')==='true',await check.elementHandle(),{timeout:4000});

  const rest=page.locator('#cvRestVisualV32');
  await rest.waitFor({state:'visible',timeout:4000});
  const restState=await rest.evaluate(el=>{
    const r=el.getBoundingClientRect();
    const nav=document.querySelector('.nav');
    const nr=nav?.getBoundingClientRect();
    return {
      hidden:el.classList.contains('hidden'),
      time:el.querySelector('#cvRestVisualTime')?.textContent?.trim()||'',
      exercise:el.querySelector('#cvRestVisualName')?.textContent?.trim()||'',
      bottom:r.bottom,
      navTop:nr?.top??null
    };
  });
  assert.equal(restState.hidden,false,'Rest timer must become visible after completing a set');
  assert.match(restState.time,/^\d{2}:\d{2}$/,'Rest timer must show mm:ss');
  assert.ok(restState.exercise.length>0,'Rest timer must identify the exercise');
  if(restState.navTop!=null)assert.ok(restState.bottom<=restState.navTop+8,'Rest timer must not cover bottom navigation');

  return {row,card,restState};
}

try{
  await page.goto(target,{waitUntil:'domcontentloaded',timeout:30000});
  await page.waitForFunction(()=>window.CVInlineSetEntryV104?.version==='104',null,{timeout:10000});
  await page.waitForFunction(()=>window.CVGuidedSetLoggingV105?.revision==='105.4',null,{timeout:10000});

  await page.evaluate(()=>document.getElementById('demoBtn')?.click());
  await page.waitForFunction(()=>!document.getElementById('app')?.classList.contains('hidden'),null,{timeout:5000});
  await page.evaluate(async()=>{
    if(typeof window.openDay==='function')await window.openDay('d1');
  });
  await page.waitForFunction(()=>[...document.querySelectorAll('.cvSetRow')].some(row=>row.offsetWidth>0&&row.offsetHeight>0),null,{timeout:7000});
  await page.waitForFunction(()=>document.body.classList.contains('cvWorkoutPrestartV40'),null,{timeout:5000});
  await page.waitForSelector('.cvWorkoutStartV40',{state:'visible',timeout:7000});

  fs.mkdirSync('artifacts/v105-active-session',{recursive:true});

  const prestart=await page.evaluate(()=>{
    const hero=document.querySelector('.cvWorkoutHeroV31');
    const cta=document.querySelector('.cvWorkoutStartV40');
    return {
      prestart:document.body.classList.contains('cvWorkoutPrestartV40'),
      active:document.body.classList.contains('cvWorkoutActiveV40'),
      heroVisible:!!hero&&hero.offsetWidth>0&&hero.offsetHeight>0&&getComputedStyle(hero).display!=='none',
      ctaVisible:!!cta&&cta.offsetWidth>0&&cta.offsetHeight>0&&getComputedStyle(cta).display!=='none'
    };
  });
  assert.equal(prestart.prestart,true);
  assert.equal(prestart.active,false);
  assert.equal(prestart.heroVisible,true);
  assert.equal(prestart.ctaVisible,true);

  await page.locator('.cvWorkoutStartV40').click();
  await page.waitForFunction(()=>document.body.classList.contains('cvWorkoutActiveV40'),null,{timeout:5000});
  await page.waitForFunction(()=>!document.body.classList.contains('cvWorkoutPrestartV40'),null,{timeout:5000});
  await page.waitForSelector('.cvWorkoutCompactCopyV40',{state:'visible',timeout:5000});

  const active=await page.evaluate(()=>{
    const hero=document.querySelector('.cvWorkoutHeroV31');
    const top=document.querySelector('.workoutTop');
    const compact=document.querySelector('.cvWorkoutCompactCopyV40');
    const finish=[...document.querySelectorAll('.workoutTop button')].find(b=>/FINALIZAR/i.test(b.textContent||''));
    const card=document.querySelector('.cvV105ExerciseOpen');
    const media=card?.querySelector(':scope>.exerciseMedia');
    const title=card?.querySelector('.exerciseTop h3')?.textContent?.trim()||'';
    return {
      heroHidden:!hero||getComputedStyle(hero).display==='none',
      topVisible:!!top&&top.offsetWidth>0&&top.offsetHeight>0&&getComputedStyle(top).display!=='none',
      topPosition:top?getComputedStyle(top).position:'',
      compactText:compact?.textContent?.replace(/\s+/g,' ').trim()||'',
      finishVisible:!!finish&&finish.offsetWidth>0&&finish.offsetHeight>0,
      currentTitle:title,
      mediaVisible:!!media&&media.offsetWidth>0&&media.offsetHeight>0&&getComputedStyle(media).display!=='none'
    };
  });

  assert.equal(active.heroHidden,true,'Large prestart hero must disappear after starting');
  assert.equal(active.topVisible,true,'Compact active header must be visible');
  assert.equal(active.topPosition,'sticky','Active header should remain sticky while logging');
  assert.match(active.compactText,/0\s*\/\s*15.*series/i,'Active header must show set progress');
  assert.equal(active.finishVisible,true,'Finish action must remain available');
  assert.match(active.currentTitle,/Hip Thrust/i,'Hip Thrust should remain current after start');
  assert.equal(active.mediaVisible,true,'Current exercise image must stay open after starting');

  await page.screenshot({path:'artifacts/v105-active-session/01-started.png',fullPage:false});

  await page.waitForFunction(()=>{
    const t=document.getElementById('cvCompactTimerV40')?.textContent?.trim()||'00:00';
    const parts=t.split(':').map(Number);
    return parts.length===2&&(parts[0]*60+parts[1])>=1;
  },null,{timeout:3500});

  const first=await completeCurrentSet();
  await page.screenshot({path:'artifacts/v105-active-session/02-first-set-rest.png',fullPage:false});

  const firstProgress=await page.evaluate(()=>{
    const next=document.querySelector('.cvV105ExerciseOpen .cvSetRow.cvV105Next:not(.done)');
    const compact=document.querySelector('.cvWorkoutCompactCopyV40')?.textContent?.replace(/\s+/g,' ').trim()||'';
    const current=document.querySelector('.cvV105ExerciseOpen .exerciseTop h3')?.textContent?.trim()||'';
    return {nextExists:!!next,current,compact};
  });
  assert.equal(firstProgress.nextExists,true,'Next set should become highlighted after completing the first');
  assert.match(firstProgress.current,/Hip Thrust/i,'Exercise must stay on Hip Thrust until all its sets are complete');
  assert.match(firstProgress.compact,/1\s*\/\s*15.*series/i,'Active header must update set progress after completion');

  await page.locator('#cvRestVisualSkip').click();
  await page.waitForFunction(()=>document.getElementById('cvRestVisualV32')?.classList.contains('hidden'),null,{timeout:3000});

  await completeCurrentSet();
  await page.locator('#cvRestVisualSkip').click();
  await page.waitForFunction(()=>document.getElementById('cvRestVisualV32')?.classList.contains('hidden'),null,{timeout:3000});

  await completeCurrentSet();
  await page.screenshot({path:'artifacts/v105-active-session/03-first-exercise-complete.png',fullPage:false});
  await page.locator('#cvRestVisualSkip').click();
  await page.waitForFunction(()=>document.getElementById('cvRestVisualV32')?.classList.contains('hidden'),null,{timeout:3000});

  await page.waitForFunction(()=>{
    const title=document.querySelector('.cvV105ExerciseOpen .exerciseTop h3')?.textContent||'';
    return /Peso muerto rumano/i.test(title);
  },null,{timeout:5000});
  await page.waitForFunction(()=>{
    const img=document.querySelector('.cvV105ExerciseOpen > .exerciseMedia .photo');
    return !!img&&img.complete&&img.naturalWidth>0;
  },null,{timeout:8000});

  const transition=await page.evaluate(()=>{
    const card=document.querySelector('.cvV105ExerciseOpen');
    const title=card?.querySelector('.exerciseTop h3')?.textContent?.trim()||'';
    const media=card?.querySelector(':scope>.exerciseMedia');
    const r=card?.getBoundingClientRect();
    const vh=window.visualViewport?.height||window.innerHeight;
    const first=[...document.querySelectorAll('.cvHevyExercise')][0];
    const firstComplete=first?.classList.contains('cvExerciseComplete')||false;
    const firstTitle=first?.querySelector('.cvDetailsTitleRowV103 h3,.cvExerciseTitleRowV35 h3');
    const firstDetails=first?.querySelector('.cvDetailsLinkV103');
    const detailsSeparated=(()=>{if(!firstTitle||!firstDetails)return false;const tr=firstTitle.getBoundingClientRect(),dr=firstDetails.getBoundingClientRect();return dr.left>=tr.right+4||dr.top>=tr.bottom-2})(); 
    const img=card?.querySelector(':scope>.exerciseMedia .photo');
    const compact=document.querySelector('.cvWorkoutCompactCopyV40')?.textContent?.replace(/\s+/g,' ').trim()||'';
    return {
      title,
      mediaVisible:!!media&&media.offsetWidth>0&&media.offsetHeight>0&&getComputedStyle(media).display!=='none',
      imageLoaded:!!img&&img.complete&&img.naturalWidth>0,
      detailsSeparated,
      top:r?.top??9999,
      bottom:r?.bottom??9999,
      vh,
      firstComplete,
      compact
    };
  });

  assert.match(transition.title,/Peso muerto rumano/i,'Next exercise should become current automatically');
  assert.equal(transition.mediaVisible,true,'Next exercise media should open automatically');
  assert.equal(transition.imageLoaded,true,'Next exercise image must be fully loaded');
  assert.equal(transition.firstComplete,true,'Completed exercise should be visually marked complete');
  assert.equal(transition.detailsSeparated,true,'Completed exercise VER DETALLES must stay separated from its title');
  assert.match(transition.compact,/3\s*\/\s*15.*series/i,'Header progress must reach 3/15 after first exercise');
  assert.ok(transition.top<transition.vh-110,'Next current exercise should be brought into a usable viewport position');

  await page.screenshot({path:'artifacts/v105-active-session/04-next-exercise.png',fullPage:false});

  const modalOpen=await page.evaluate(()=>!!document.querySelector('.cvTechBackdrop.show,.cvPadBackdrop.show,[role="dialog"].show'));
  assert.equal(modalOpen,false,'Active logging flow must remain inline');
  assert.equal(errors.length,0,'Browser errors: '+errors.join(' | '));

  console.log('CV_ACTIVE_SESSION_V105_QA_OK',JSON.stringify({active,firstProgress,transition,rest:first.restState}));
}finally{
  await context.close().catch(()=>{});
  await browser.close().catch(()=>{});
}
