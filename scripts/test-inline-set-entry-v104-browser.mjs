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
  await page.waitForFunction(()=>[...document.querySelectorAll('input[id^="cvw_"]')].some(el=>el.offsetWidth>0&&el.offsetHeight>0),null,{timeout:5000});

  const weightState=await page.evaluate(()=>{
    const w=[...document.querySelectorAll('input[id^="cvw_"]')].find(el=>el.offsetWidth>0&&el.offsetHeight>0);
    if(!w)throw new Error('No visible weight input');
    w.dispatchEvent(new PointerEvent('pointerdown',{bubbles:true,pointerType:'touch'}));
    w.focus();
    w.click();
    w.value='62,5';
    w.dispatchEvent(new Event('input',{bubbles:true}));
    return {
      id:w.id,
      activeId:document.activeElement?.id||'',
      type:w.type,
      inputmode:w.getAttribute('inputmode'),
      value:w.value,
      readOnly:w.readOnly,
      role:w.getAttribute('role'),
      ariaHaspopup:w.getAttribute('aria-haspopup'),
      v73:w.dataset.cvPadV73||null,
      sheetOpen:!!document.querySelector('.cvTechBackdrop.show,.cvPadBackdrop.show,[role="dialog"].show')
    };
  });
  assert.equal(weightState.activeId,weightState.id,'Weight edit must remain in the row');
  assert.equal(weightState.type,'text');
  assert.equal(weightState.inputmode,'decimal');
  assert.equal(weightState.value,'62.5','Decimal comma must normalize inline');
  assert.equal(weightState.readOnly,false,'Weight input must be editable');
  assert.equal(weightState.role,null,'Weight input must not masquerade as a button');
  assert.equal(weightState.ariaHaspopup,null,'Weight input must not advertise a custom dialog');
  assert.equal(weightState.v73,null,'V73 keypad ownership must be absent');
  assert.equal(weightState.sheetOpen,false,'Editing weight must not open a modal/sheet');

  const repsState=await page.evaluate(()=>{
    const r=[...document.querySelectorAll('input[id^="cvr_"]')].find(el=>el.offsetWidth>0&&el.offsetHeight>0);
    if(!r)throw new Error('No visible reps input');
    r.dispatchEvent(new PointerEvent('pointerdown',{bubbles:true,pointerType:'touch'}));
    r.focus();
    r.click();
    r.value='10';
    r.dispatchEvent(new Event('input',{bubbles:true}));
    return {
      id:r.id,
      activeId:document.activeElement?.id||'',
      type:r.type,
      inputmode:r.getAttribute('inputmode'),
      value:r.value,
      readOnly:r.readOnly,
      role:r.getAttribute('role'),
      ariaHaspopup:r.getAttribute('aria-haspopup'),
      v73:r.dataset.cvPadV73||null,
      sheetOpen:!!document.querySelector('.cvTechBackdrop.show,.cvPadBackdrop.show,[role="dialog"].show')
    };
  });
  assert.equal(repsState.activeId,repsState.id,'Reps edit must remain in the row');
  assert.equal(repsState.type,'text');
  assert.equal(repsState.inputmode,'numeric');
  assert.equal(repsState.value,'10');
  assert.equal(repsState.readOnly,false);
  assert.equal(repsState.role,null);
  assert.equal(repsState.ariaHaspopup,null);
  assert.equal(repsState.v73,null);
  assert.equal(repsState.sheetOpen,false,'Editing reps must not open a modal/sheet');
  assert.equal(errors.length,0,'Browser errors: '+errors.join(' | '));
  console.log('CV_INLINE_SET_ENTRY_V104_BROWSER_OK',JSON.stringify({weightState,repsState}));
} finally {
  await context.close().catch(()=>{});
  await browser.close().catch(()=>{});
}
