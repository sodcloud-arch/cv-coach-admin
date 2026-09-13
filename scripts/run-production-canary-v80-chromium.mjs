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
  await page.locator('.cvHevyExercise').first().waitFor({state:'visible',timeout:20000});
  const v80Cards=await page.locator('.cvHevyExercise').evaluateAll(nodes=>nodes.map(node=>({
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
    const imageResponse=await fetch(card.image,{redirect:'follow'});
    const contentType=imageResponse.headers.get('content-type')||'';
    if(!imageResponse.ok||!contentType.startsWith('image/'))throw new Error('V80 image HTTP failure for '+card.name+': '+imageResponse.status+' '+contentType);
  }
  console.log('CV_CANARY_V80_LIBRARY_CARDS_OK',JSON.stringify(v80Cards.map(({name,image})=>({name,image}))));

  const techniqueButton=page.locator('.cvExecutionBtnV35').first();
  await tap(page,techniqueButton,'v80-open-technique');
  await page.locator('#cvTechBackdrop.show').waitFor({state:'visible',timeout:10000});
  const techniqueImage=page.locator('#cvTechMedia img');
  await techniqueImage.waitFor({state:'visible',timeout:15000});
  const techniqueLoaded=await techniqueImage.evaluate(img=>img.complete&&img.naturalWidth>0&&img.naturalHeight>0);
  if(!techniqueLoaded)throw new Error('V80 technique modal image did not decode');
  console.log('CV_CANARY_V80_TECHNIQUE_MODAL_OK');
  await tap(page,page.locator('.cvTechClose'),'v80-close-technique');

  const active=await latestActiveSession(athleteAccessToken,canaryClientId);`;
code=replaceOnce(code,flowNeedle,flowReplacement,'V80 library assertions');

await writeFile(generatedUrl,code,'utf8');
try{
  await import(`${generatedUrl.href}?run=${Date.now()}`);
}finally{
  await unlink(generatedUrl).catch(()=>{});
}
