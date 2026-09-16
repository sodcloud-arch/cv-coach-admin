import { webkit } from 'playwright';
import assert from 'node:assert/strict';

const base=(process.env.CV_TEST_URL||'https://cv-coach-roan.vercel.app').replace(/\/$/,'');
const target=`${base}/?cv_v102=1&v=103-live`;
const browser=await webkit.launch();
const context=await browser.newContext({viewport:{width:390,height:844},isMobile:true,hasTouch:true,serviceWorkers:'block'});
const page=await context.newPage();
const errors=[];
page.on('pageerror',e=>errors.push(String(e?.message||e)));

try{
  await page.goto(target,{waitUntil:'domcontentloaded',timeout:30000});
  await page.waitForFunction(()=>window.CVExerciseScreenV102?.version==='102.2'&&window.CVExerciseDetailsV103?.version==='103',null,{timeout:10000});
  await page.evaluate(()=>document.getElementById('demoBtn')?.click());
  await page.waitForFunction(()=>!document.getElementById('app')?.classList.contains('hidden'),null,{timeout:5000});
  await page.waitForFunction(()=>{
    try{
      if(document.querySelector('.cvHevyExercise,.workoutExercise'))return true;
      if(typeof window.openDay==='function')window.openDay('d1');
      return !!document.querySelector('.cvHevyExercise,.workoutExercise');
    }catch(_){return false}
  },null,{timeout:7000,polling:100});
  await page.waitForFunction(()=>document.querySelectorAll('.cvDetailsLinkV103').length>0,null,{timeout:5000});

  await page.evaluate(()=>{
    const card=document.querySelector('.cvHevyExercise,.workoutExercise');
    if(!card)throw new Error('No workout card available for live V103 canary');
    card.setAttribute('data-tech-name','Jalón al pecho');
    card.setAttribute('data-tech-img','');
    card.setAttribute('data-tech-instructions','');
    card.setAttribute('data-tech-tempo','2-1-2');
    const title=card.querySelector('.exerciseTop h3');
    if(title)title.textContent='Jalón al pecho';
    const button=card.querySelector('.cvDetailsLinkV103');
    if(button)button.dataset.cvDetailsIndex='0';
  });

  await page.locator('.cvDetailsLinkV103').first().click();
  await page.waitForFunction(()=>{
    const b=document.getElementById('cvTechniqueDetailsV103');
    const text=b?.querySelector('#cvV103Content')?.textContent||'';
    return b?.classList.contains('show')&&text.includes('Ligeramente más ancho que los hombros')&&text.includes('Tirón hacia el pecho')&&text.includes('Errores frecuentes');
  },null,{timeout:10000,polling:150});

  const state=await page.evaluate(()=>{
    const b=document.getElementById('cvTechniqueDetailsV103');
    const text=b?.querySelector('#cvV103Content')?.textContent||'';
    return {
      title:b?.querySelector('#cvV103Title')?.textContent?.trim()||'',
      phases:[...b?.querySelectorAll('.cvV103TempoPhase')||[]].map(x=>x.textContent?.replace(/\s+/g,' ').trim()||''),
      hasGrip:text.includes('Ligeramente más ancho que los hombros'),
      hasArmSpacing:text.includes('antropometría'),
      hasBreathing:text.includes('Exhala durante el tirón'),
      hasRange:text.includes('Rango de movimiento'),
      hasCoach:text.includes('Nota del coach'),
      advancedFallback:text.includes('todavía no ha sido curada')
    };
  });

  assert.equal(state.title,'Jalón al pecho');
  assert.equal(state.hasGrip,true,'Live RPC did not return curated grip width');
  assert.equal(state.hasArmSpacing,true,'Live RPC did not return arm-spacing guidance');
  assert.equal(state.hasBreathing,true,'Live RPC did not return breathing guidance');
  assert.equal(state.hasRange,true,'Live RPC did not return range guidance');
  assert.equal(state.hasCoach,true,'Live RPC did not return coach note');
  assert.equal(state.advancedFallback,false,'Curated Jalón unexpectedly rendered fallback detail state');
  assert.equal(state.phases.length,3,'Curated Jalón must expose three tempo phases');
  assert.ok(state.phases.some(x=>x.includes('Tirón hacia el pecho')&&x.includes('2')));
  assert.ok(state.phases.some(x=>x.includes('Pausa abajo')&&x.includes('1')));
  assert.ok(state.phases.some(x=>x.includes('Retorno')&&x.includes('2')));
  assert.equal(errors.length,0,'Browser errors: '+errors.join(' | '));

  console.log('CV_V103_PRODUCTION_STATE',JSON.stringify(state));
  console.log('CV_EXERCISE_DETAILS_V103_PRODUCTION_WEBKIT_OK');
} finally {
  await context.close().catch(()=>{});
  await browser.close().catch(()=>{});
}
