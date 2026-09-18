import { webkit } from 'playwright';
import assert from 'node:assert/strict';

const base=(process.env.CV_TEST_URL||'http://127.0.0.1:4173').replace(/\/$/,'');
const target=`${base}/?cv_v102=1&v=1041`;
const browser=await webkit.launch();
const context=await browser.newContext({viewport:{width:390,height:844},isMobile:true,hasTouch:true,serviceWorkers:'block'});
const page=await context.newPage();
const errors=[];page.on('pageerror',e=>errors.push(String(e?.message||e)));

try{
  await page.goto(target,{waitUntil:'domcontentloaded',timeout:30000});
  await page.waitForFunction(()=>window.CVInlineSetEntryV104?.version==='104',null,{timeout:10000});
  await page.evaluate(()=>document.getElementById('demoBtn')?.click());
  await page.waitForFunction(()=>!document.getElementById('app')?.classList.contains('hidden'),null,{timeout:5000});
  await page.waitForFunction(()=>{
    try{
      if(document.querySelector('.cvSetRow'))return true;
      if(typeof window.openDay==='function')window.openDay('d1');
      return !!document.querySelector('.cvSetRow');
    }catch(_){return false}
  },null,{timeout:7000,polling:100});

  const weight=page.locator('input[id^="cvw_"]:visible').first();
  const reps=page.locator('input[id^="cvr_"]:visible').first();
  await weight.waitFor({state:'visible',timeout:5000});
  await reps.waitFor({state:'visible',timeout:5000});
  await weight.scrollIntoViewIfNeeded();
  const weightId=await weight.getAttribute('id');
  const repsId=await reps.getAttribute('id');

  await weight.tap({timeout:5000});
  await weight.fill('62,5');
  await page.waitForTimeout(100);
  let state=await page.evaluate(id=>{
    const w=document.getElementById(id);
    return {
      activeId:document.activeElement?.id||'',
      type:w?.type,
      inputmode:w?.getAttribute('inputmode'),
      value:w?.value||'',
      sheetOpen:!!document.querySelector('.cvTechBackdrop.show [role="dialog"],.cvTechBackdrop.show,.cvPadBackdrop.show [role="dialog"],.cvPadBackdrop.show')
    };
  },weightId);
  assert.equal(state.activeId,weightId,'Weight edit must remain in the row');
  assert.equal(state.type,'text','Weight field must avoid native number picker UI');
  assert.equal(state.inputmode,'decimal');
  assert.equal(state.value,'62.5','Decimal comma must normalize inline');
  assert.equal(state.sheetOpen,false,'Editing weight must not open a modal/sheet');

  await reps.scrollIntoViewIfNeeded();
  await reps.tap({timeout:5000});
  await reps.fill('10');
  state=await page.evaluate(id=>{
    const r=document.getElementById(id);
    return {
      activeId:document.activeElement?.id||'',
      type:r?.type,
      inputmode:r?.getAttribute('inputmode'),
      value:r?.value||'',
      sheetOpen:!!document.querySelector('.cvTechBackdrop.show [role="dialog"],.cvTechBackdrop.show,.cvPadBackdrop.show [role="dialog"],.cvPadBackdrop.show')
    };
  },repsId);
  assert.equal(state.activeId,repsId,'Reps edit must remain in the row');
  assert.equal(state.type,'text');
  assert.equal(state.inputmode,'numeric');
  assert.equal(state.value,'10');
  assert.equal(state.sheetOpen,false,'Editing reps must not open a modal/sheet');
  assert.equal(errors.length,0,'Browser errors: '+errors.join(' | '));
  console.log('CV_INLINE_SET_ENTRY_V104_BROWSER_OK',JSON.stringify(state));
} finally {
  await context.close().catch(()=>{});
  await browser.close().catch(()=>{});
}
