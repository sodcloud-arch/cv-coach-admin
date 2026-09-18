import { chromium } from 'playwright';
import assert from 'node:assert/strict';

const base=(process.env.CV_PRODUCTION_URL||'https://cv-coach-roan.vercel.app').replace(/\/$/,'');
const expectedSha=(process.env.CV_EXPECTED_SHA||'').trim();
const browser=await chromium.launch();
const context=await browser.newContext({
  viewport:{width:390,height:844},
  isMobile:true,
  hasTouch:true,
  serviceWorkers:'block'
});
const page=await context.newPage();
const errors=[];
page.on('pageerror',error=>errors.push(String(error?.message||error)));

async function openWithRetry(){
  let lastError;
  for(let attempt=1;attempt<=6;attempt++){
    try{
      const response=await page.goto(`${base}/?cv_v102=1&v=105&qa=production&ts=${Date.now()}`,{
        waitUntil:'domcontentloaded',
        timeout:30000
      });
      if(response?.status()===200)return response;
      lastError=new Error(`Unexpected HTTP status ${response?.status()}`);
    }catch(error){
      lastError=error;
    }
    await page.waitForTimeout(5000);
  }
  throw lastError||new Error('Production did not become reachable');
}

try{
  const response=await openWithRetry();
  assert.equal(response.status(),200,'Production root must return HTTP 200');

  const build=await page.evaluate(async()=>{
    try{
      const response=await fetch('/build.json',{cache:'no-store'});
      if(!response.ok)return null;
      return await response.json();
    }catch(_){
      return null;
    }
  });
  assert.ok(build,'Production build.json must be reachable');
  assert.equal(build.version,'105.4','Production must expose canonical V105.4 build metadata');
  if(expectedSha)assert.equal(build.git_sha,expectedSha,'Production must match the commit that passed QA');

  await page.waitForFunction(()=>window.CVInlineSetEntryV104?.version==='104',null,{timeout:10000});
  await page.waitForFunction(()=>window.CVGuidedSetLoggingV105?.revision==='105.4',null,{timeout:10000});
  await page.waitForSelector('#demoBtn',{state:'visible',timeout:10000});
  await page.evaluate(()=>document.getElementById('demoBtn')?.click());
  await page.waitForFunction(()=>!document.getElementById('app')?.classList.contains('hidden'),null,{timeout:7000});

  await page.evaluate(async()=>{
    if(typeof window.openDay==='function')await window.openDay('d1');
  });
  await page.waitForFunction(()=>document.body.classList.contains('cvWorkoutPrestartV40'),null,{timeout:7000});
  await page.waitForSelector('.cvWorkoutStartV40',{state:'visible',timeout:7000});
  await page.waitForFunction(()=>{
    const img=document.querySelector('.cvV105ExerciseOpen > .exerciseMedia .photo');
    return !!img&&img.complete&&img.naturalWidth>0;
  },null,{timeout:10000});

  const state=await page.evaluate(()=>({
    supabaseLoaded:typeof window.supabase!=='undefined',
    demoVisible:!!document.getElementById('demoBtn'),
    appVisible:!document.getElementById('app')?.classList.contains('hidden'),
    currentExercise:document.querySelector('.cvV105ExerciseOpen .exerciseTop h3')?.textContent?.trim()||'',
    imageLoaded:(()=>{const img=document.querySelector('.cvV105ExerciseOpen > .exerciseMedia .photo');return !!img&&img.complete&&img.naturalWidth>0})(),
    prestart:document.body.classList.contains('cvWorkoutPrestartV40')
  }));

  assert.equal(state.supabaseLoaded,true,'Supabase client must load in production');
  assert.equal(state.appVisible,true,'Demo app must become visible');
  assert.equal(state.imageLoaded,true,'Current exercise image must load in production');
  assert.equal(state.prestart,true,'Workout must enter prestart state');
  assert.ok(state.currentExercise.length>0,'Current exercise must have a title');
  assert.equal(errors.length,0,'Production browser errors: '+errors.join(' | '));

  console.log('CV_PRODUCTION_VALIDATION_OK',JSON.stringify({base,build,state}));
}finally{
  await context.close().catch(()=>{});
  await browser.close().catch(()=>{});
}
