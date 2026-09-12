import { webkit } from 'playwright';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const base=process.env.CV_TEST_URL||'http://127.0.0.1:4173';
const here=path.dirname(fileURLToPath(import.meta.url));
const repo=path.resolve(here,'..');
const v72Source=await fs.readFile(path.join(repo,'client-portal/assets/cv-ios-keyboard-v72.js'),'utf8');

async function keyboardKernelTest(){
  const browser=await webkit.launch();
  const context=await browser.newContext({viewport:{width:390,height:844},isMobile:true,hasTouch:true,serviceWorkers:'block'});
  const page=await context.newPage();
  try{
    await page.setContent(`<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><style>html,body{margin:0}body{min-height:2600px;background:#030506}.spacer{height:980px}.card{height:500px;padding:24px}.field{display:block;width:120px;height:64px;font-size:28px}</style></head><body><div class="spacer"></div><div class="card"><input id="cvw_0_0" class="field" inputmode="decimal" value="20"><input id="cvr_0_0" class="field" inputmode="numeric" value="8"></div></body></html>`,{waitUntil:'domcontentloaded'});
    await page.addScriptTag({content:v72Source});
    assert.equal(await page.evaluate(()=>window.CVIOSKeyboardV72?.version),'v72','V72 kernel did not load');

    await page.evaluate(()=>window.scrollTo(0,760));
    await page.waitForTimeout(40);
    const before=await page.evaluate(()=>window.scrollY);
    await page.evaluate(()=>document.getElementById('cvw_0_0').focus({preventScroll:true}));
    await page.waitForTimeout(40);
    const focused=await page.evaluate(()=>window.CVIOSKeyboardV72.state());
    assert.equal(focused.active,true,'V72 did not own focused workout input');
    assert.ok(Math.abs(focused.restoreY-before)<=2,`V72 captured wrong pre-keyboard scroll: ${focused.restoreY} vs ${before}`);

    // Headless WebKit does not expose the native iOS keyboard. Simulate the page displacement
    // that Safari can retain while the numeric keyboard is closing, then exercise the real
    // focusout/Listo restoration logic from V72.
    await page.evaluate(()=>window.scrollBy(0,170));
    const shifted=await page.evaluate(()=>window.scrollY);
    assert.ok(shifted>=before+150,`Synthetic keyboard displacement failed: ${before} -> ${shifted}`);
    await page.evaluate(()=>document.activeElement.blur());
    await page.waitForTimeout(700);
    const after=await page.evaluate(()=>window.scrollY);
    const ended=await page.evaluate(()=>window.CVIOSKeyboardV72.state());
    assert.equal(ended.active,false,'V72 remained active after Listo/focusout');
    assert.ok(Math.abs(after-before)<=8,`V72 Listo restore failed: before=${before} after=${after}`);
    console.log(`CV_IOS_KEYBOARD_V72_WEBKIT_OK before=${before} shifted=${shifted} after=${after}`);
  } finally {
    await context.close().catch(()=>{});
    await browser.close().catch(()=>{});
  }
}

async function appStartTest({autoSet=false}={}){
  const browser=await webkit.launch();
  const context=await browser.newContext({viewport:{width:390,height:844},isMobile:true,hasTouch:true,serviceWorkers:'block'});
  const page=await context.newPage();
  const errors=[];
  page.on('pageerror',e=>errors.push(String(e?.message||e)));
  try{
    // Keep this integration path short and deterministic; keyboard behavior is covered above
    // with the exact production V72 source in a minimal WebKit harness.
    await page.addInitScript(()=>{try{localStorage.setItem('cv_sound_enabled','false')}catch(_){}});
    await page.route(/\.(?:png|jpe?g|webp|woff2?)(?:\?.*)?$/i,route=>route.abort());
    await page.goto(base,{waitUntil:'domcontentloaded',timeout:20000});
    await page.evaluate(()=>document.getElementById('demoBtn')?.click());
    await page.waitForFunction(()=>!document.getElementById('app')?.classList.contains('hidden'),null,{timeout:5000});
    await page.evaluate(()=>window.openDay('d1'));
    await page.waitForFunction(()=>!!document.getElementById('cvw_0_0')&&!!window.CVWorkoutControllerV71&&!!window.CVIOSKeyboardV72,null,{timeout:5000});
    const diag=await page.evaluate(()=>({v71:window.CVWorkoutControllerV71?.version,v72:window.CVIOSKeyboardV72?.version,session:window.CVWorkoutControllerV71?.diagnose?.().sessionId,view:document.body.dataset.cvView}));
    assert.deepEqual(diag,{v71:'v71',v72:'v72',session:null,view:'workout'},'pre-start app contract failed');

    const values=autoSet?{w:'22.5',r:'9'}:{w:'20',r:'8'};
    await page.evaluate(({w,r})=>{
      const set=(id,value)=>{const el=document.getElementById(id);if(!el)throw new Error(`${id} missing`);el.value=value;el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}))};
      set('cvw_0_0',w);set('cvr_0_0',r);
    },values);

    if(autoSet){
      const check=await page.evaluate(()=>document.querySelector('.cvSetCheck')?.outerHTML||null);
      assert.ok(check,'first set check control missing');
      await page.evaluate(()=>document.querySelector('.cvSetCheck')?.click());
      await page.waitForFunction(()=>window.CVWorkoutControllerV71?.diagnose?.().sessionId==='demo'&&window.cvExercises?.()?.[0]?.sets?.[0]?.completed===true,null,{timeout:5000});
      const got=await page.evaluate(()=>{const s=window.cvExercises()?.[0]?.sets?.[0];return {w:s?.weight_kg,r:s?.reps,c:s?.completed}});
      assert.deepEqual(got,{w:22.5,r:9,c:true},'first-set auto-start lost values or completion');
      console.log('CV_DEMO_AUTO_START_WEBKIT_OK');
    }else{
      const started=await page.evaluate(()=>window.startWorkout());
      assert.equal(started,true,'explicit start did not resolve true');
      await page.waitForFunction(()=>window.CVWorkoutControllerV71?.diagnose?.().sessionId==='demo',null,{timeout:5000});
      const got=await page.evaluate(()=>{const s=window.cvExercises()?.[0]?.sets?.[0];return {w:s?.weight_kg,r:s?.reps}});
      assert.deepEqual(got,{w:20,r:8},'explicit start lost pre-start values');
      console.log('CV_DEMO_EXPLICIT_START_WEBKIT_OK');
    }
    assert.equal(errors.length,0,'App page errors: '+errors.join(' | '));
  } finally {
    await context.close().catch(()=>{});
    await browser.close().catch(()=>{});
  }
}

await keyboardKernelTest();
await appStartTest({autoSet:false});
await appStartTest({autoSet:true});
console.log('CV_MOBILE_WEBKIT_V71_V72_OK');
