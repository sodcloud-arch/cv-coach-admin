import { webkit } from 'playwright';
import assert from 'node:assert/strict';

const base=(process.env.CV_TEST_URL||'http://127.0.0.1:4173').replace(/\/$/,'');
const target=`${base}/?cv_v102=1&v=1023`;

const browser=await webkit.launch();
const context=await browser.newContext({
  viewport:{width:390,height:844},
  isMobile:true,
  hasTouch:true,
  serviceWorkers:'block'
});
const page=await context.newPage();
const errors=[];
page.on('pageerror',e=>errors.push(String(e?.message||e)));

try{
  await page.goto(target,{waitUntil:'domcontentloaded',timeout:30000});
  await page.waitForFunction(()=>window.CVExerciseScreenV102?.version==='102.2',null,{timeout:10000});

  await page.evaluate(()=>document.getElementById('demoBtn')?.click());
  await page.waitForFunction(()=>!document.getElementById('app')?.classList.contains('hidden'),null,{timeout:5000});
  await page.waitForFunction(()=>{
    try{
      if(document.querySelector('.cvHevyExercise,.workoutExercise'))return true;
      if(typeof window.openDay==='function')window.openDay('d1');
      return !!document.querySelector('.cvHevyExercise,.workoutExercise');
    }catch(_){return false}
  },null,{timeout:7000,polling:100});

  await page.waitForFunction(()=>
    document.body.classList.contains('cvV102WorkoutReady') &&
    document.body.dataset.cvV102==='102.2' &&
    document.querySelectorAll('.cvV102Expanded').length===1,
    null,{timeout:7000,polling:100}
  );

  const state=await page.evaluate(()=>{
    const cards=[...document.querySelectorAll('.cvHevyExercise,.workoutExercise')];
    const expanded=[...document.querySelectorAll('.cvV102Expanded')];
    const collapsed=[...document.querySelectorAll('.cvV102Collapsed')];
    const current=document.querySelector('.cvExerciseCurrent') || cards.find(card=>!card.classList.contains('cvExerciseComplete')) || null;
    const focused=expanded[0]||null;
    const media=focused?.querySelector(':scope > .exerciseMedia')||null;
    const image=media?.querySelector('.photo')||null;
    const mediaStyle=media?getComputedStyle(media):null;
    const mediaRect=media?.getBoundingClientRect()||null;
    const collapsedSetRows=collapsed.map(card=>{
      const rows=card.querySelector(':scope > .cvSetRows');
      return rows?getComputedStyle(rows).display:null;
    });
    return {
      version:window.CVExerciseScreenV102?.version||'',
      contract:window.CVExerciseScreenV102?.contract_revision||'',
      bodyReady:document.body.classList.contains('cvV102WorkoutReady'),
      marker:document.body.dataset.cvV102||'',
      legacyStarted:document.body.classList.contains('cvWorkoutActiveV40'),
      cardCount:cards.length,
      expandedCount:expanded.length,
      collapsedCount:collapsed.length,
      currentIsExpanded:!!current&&current===focused,
      mediaPresent:!!media,
      imagePresent:!!image,
      mediaDisplay:mediaStyle?.display||'',
      mediaHeight:mediaRect?.height||0,
      collapsedSetRows,
      focusedTitle:focused?.querySelector('.exerciseTop h3')?.textContent?.trim()||''
    };
  });

  assert.equal(state.version,'102.2','V102.2 runtime not loaded');
  assert.equal(state.contract,'V102.2_SELF_CONTAINED_FOCUS','Wrong V102 contract');
  assert.equal(state.bodyReady,true,'V102.2 did not establish its own ready state');
  assert.equal(state.marker,'102.2','V102.2 runtime marker missing');
  assert.ok(state.cardCount>=2,`Expected >=2 workout cards, got ${state.cardCount}`);
  assert.equal(state.expandedCount,1,`Expected exactly one expanded card, got ${state.expandedCount}`);
  assert.equal(state.collapsedCount,state.cardCount-1,'Every non-current card must be collapsed');
  assert.equal(state.currentIsExpanded,true,'Current exercise is not the expanded card');
  assert.equal(state.mediaPresent,true,'Expanded exercise has no inline media container');
  assert.equal(state.imagePresent,true,'Expanded exercise has no inline exercise image');
  assert.notEqual(state.mediaDisplay,'none','Expanded exercise media is still hidden by legacy CSS');
  assert.ok(state.mediaHeight>100,`Expanded exercise media is not visibly sized: ${state.mediaHeight}`);
  assert.ok(state.collapsedSetRows.every(v=>v===null||v==='none'),'A collapsed exercise still shows set rows');
  assert.equal(errors.length,0,'Browser errors: '+errors.join(' | '));

  console.log('CV_V102_BROWSER_STATE',JSON.stringify(state));
  console.log('CV_MOBILE_EXERCISE_V102_BROWSER_WEBKIT_OK');
} finally {
  await context.close().catch(()=>{});
  await browser.close().catch(()=>{});
}
