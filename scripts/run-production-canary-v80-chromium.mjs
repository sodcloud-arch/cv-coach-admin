import { readFile, writeFile, unlink } from 'node:fs/promises';

const sourceUrl=new URL('./test-production-canary-v76.mjs',import.meta.url);
const generatedUrl=new URL('./.test-production-canary-v80-chromium.generated.mjs',import.meta.url);

function replaceOnce(source,needle,replacement,label){
  const first=source.indexOf(needle);
  if(first<0)throw new Error(`V80 transform missing ${label}`);
  if(source.indexOf(needle,first+needle.length)>=0)throw new Error(`V80 transform ambiguous ${label}`);
  return source.slice(0,first)+replacement+source.slice(first+needle.length);
}

let code=await readFile(sourceUrl,'utf8');
code=replaceOnce(
  code,
  "import { webkit, devices } from 'playwright';",
  "import { chromium, devices } from 'playwright';",
  'playwright import',
);
code=replaceOnce(
  code,
  "const RUN_ID=`${process.env.GITHUB_RUN_ID||'local'}-${process.env.GITHUB_RUN_ATTEMPT||'1'}`;",
  "const RUN_ID=`${process.env.GITHUB_RUN_ID||'local'}-${process.env.GITHUB_RUN_ATTEMPT||'1'}-chromium`;",
  'run id',
);
code=replaceOnce(
  code,
  'browser=await webkit.launch({headless:true});',
  'browser=await chromium.launch({headless:true});',
  'browser launch',
);

const flowNeedle="  await startWorkoutFromCurrentView(page);\n\n  const active=await latestActiveSession(athleteAccessToken,canaryClientId);";
const flowReplacement=`  await startWorkoutFromCurrentView(page);

  const expectedV80Names=['Hack squat','Press banca con barra','Jalón al pecho agarre neutro','Pallof press','Dead bug'];
  await page.waitForFunction(expectedNames=>{
    const cards=Array.from(document.querySelectorAll('.cvHevyExercise'));
    if(cards.length!==expectedNames.length)return false;
    return cards.every((node,index)=>{
      const name=(node.getAttribute('data-tech-name')||'').trim();
      const image=(node.getAttribute('data-tech-img')||'').trim();
      return name===expectedNames[index]&&image.startsWith('https://');
    });
  },expectedV80Names,{timeout:25000});
  console.log('CV_CANARY_V80_LIVE_EXERCISES_READY');

  const exerciseCards=page.locator('.cvHevyExercise');
  await exerciseCards.first().waitFor({state:'visible',timeout:20000});
  const v80Cards=await exerciseCards.evaluateAll(nodes=>nodes.map(node=>({
    name:(node.getAttribute('data-tech-name')||'').trim(),
    image:(node.getAttribute('data-tech-img')||'').trim(),
    instructions:(node.getAttribute('data-tech-instructions')||'').trim(),
    tempo:(node.getAttribute('data-tech-tempo')||'').trim(),
  })));
  if(v80Cards.length!==expectedV80Names.length)throw new Error('V80 expected 5 exercise cards, got '+v80Cards.length);
  for(let i=0;i<expectedV80Names.length;i++){
    const card=v80Cards[i];
    if(card.name!==expectedV80Names[i])throw new Error('V80 exercise order mismatch at '+i+': '+card.name);
    if(!card.image.startsWith('https://'))throw new Error('V80 missing technique image for '+card.name);
    if(!card.instructions)throw new Error('V80 missing instructions for '+card.name);
    if(!card.tempo)throw new Error('V80 missing tempo for '+card.name);
  }
  console.log('CV_CANARY_V80_LIBRARY_CARDS_OK',JSON.stringify(v80Cards.map(({name,image})=>({name,image}))));

  for(let i=0;i<expectedV80Names.length;i++){
    const card=v80Cards[i];
    const exerciseCard=exerciseCards.nth(i);
    const techniqueButton=exerciseCard.locator('.cvExecutionBtnV35');
    await tap(page,techniqueButton,'v80-open-technique-'+(i+1));
    const backdrop=page.locator('#cvTechBackdrop.show');
    await backdrop.waitFor({state:'visible',timeout:10000});
    const techniqueImage=page.locator('#cvTechMedia img');
    await techniqueImage.waitFor({state:'visible',timeout:15000});
    await techniqueImage.evaluate(async img=>{
      if(img.complete)return;
      await new Promise((resolve,reject)=>{
        const onLoad=()=>resolve();
        const onError=()=>reject(new Error('image-error'));
        img.addEventListener('load',onLoad,{once:true});
        img.addEventListener('error',onError,{once:true});
      });
    });
    const imageState=await techniqueImage.evaluate(img=>({
      complete:img.complete,
      naturalWidth:img.naturalWidth,
      naturalHeight:img.naturalHeight,
      src:img.currentSrc||img.src||'',
    }));
    if(!imageState.complete||imageState.naturalWidth<1||imageState.naturalHeight<1){
      throw new Error('V80 technique image did not decode for '+card.name+': '+JSON.stringify(imageState));
    }
    console.log('CV_CANARY_V80_TECHNIQUE_OK',JSON.stringify({name:card.name,width:imageState.naturalWidth,height:imageState.naturalHeight,src:imageState.src}));
    await tap(page,page.locator('.cvTechClose'),'v80-close-technique-'+(i+1));
    await page.locator('#cvTechBackdrop.show').waitFor({state:'hidden',timeout:10000});
  }
  console.log('CV_CANARY_V80_ALL_TECHNIQUE_IMAGES_OK');

  const active=await latestActiveSession(athleteAccessToken,canaryClientId);`;
code=replaceOnce(code,flowNeedle,flowReplacement,'V80 library assertions');

const verifyNeedle="  const verification=await control('verify',{expected_weight:EXPECTED_WEIGHT,expected_reps:EXPECTED_REPS});";
const verifyReplacement=`  const verifyResponse=await fetch(BASE+'/rest/v1/rpc/verify_production_canary_v80',{
    method:'POST',
    headers:{apikey:KEY,Authorization:'Bearer '+athleteAccessToken,'Content-Type':'application/json'},
    body:JSON.stringify({p_run_id:RUN_ID,p_expected_weight:EXPECTED_WEIGHT,p_expected_reps:EXPECTED_REPS}),
  });
  const verification=await verifyResponse.json().catch(()=>({}));
  if(!verifyResponse.ok||verification?.error)throw new Error('V80 canonical verify: '+(verification?.error||verifyResponse.status));
  if(!verification?.feedback_v2_ok)throw new Error('V80 canonical feedback contract incomplete');`;
code=replaceOnce(code,verifyNeedle,verifyReplacement,'V80 canonical feedback verifier');

await writeFile(generatedUrl,code,'utf8');
try{
  await import(`${generatedUrl.href}?run=${Date.now()}`);
}finally{
  await unlink(generatedUrl).catch(()=>{});
}
