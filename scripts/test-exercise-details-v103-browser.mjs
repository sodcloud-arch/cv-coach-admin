import { webkit } from 'playwright';
import assert from 'node:assert/strict';

const base=(process.env.CV_TEST_URL||'http://127.0.0.1:4173').replace(/\/$/,'');
const target=`${base}/?cv_v102=1&v=103`;

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

await page.route('**/rest/v1/rpc/get_exercise_technique_v103',async route=>{
  let name='Ejercicio';
  try{name=route.request().postDataJSON()?.p_name||name}catch(_){/* noop */}
  const payload={
    name,
    slug:'test-exercise',
    primary_muscle:'espalda',
    equipment:'polea',
    movement_pattern:'vertical_pull',
    difficulty:'beginner',
    instructions:'Mantén el torso estable y controla todo el recorrido.',
    default_tempo:'2-1-2',
    default_rest_sec:90,
    image_path:null,
    video_path:null,
    technique_details:{
      version:1,
      quality:'curated',
      summary:'Objetivo técnico de prueba.',
      setup:['Ajusta la posición antes de iniciar.'],
      grip:{type:'Pronado',width:'Ligeramente más ancho que hombros',arm_spacing:'Separación adaptada a la antropometría.',hands:'Muñecas neutras.'},
      body_position:{torso:'Torso estable.',shoulders:'Hombros controlados.',head:'Cabeza neutra.'},
      execution_steps:[
        {number:1,title:'Posición inicial',detail:'Fija el tronco.'},
        {number:2,title:'Ejecuta',detail:'Mueve los codos con control.'}
      ],
      tempo:{notation:'2-1-2',phases:[
        {label:'Tirón',seconds:2,cue:'Sin impulso.'},
        {label:'Pausa',seconds:1,cue:'Mantén tensión.'},
        {label:'Retorno',seconds:2,cue:'Controla la vuelta.'}
      ],note:'Prioriza el control.'},
      breathing:'Exhala en el esfuerzo e inhala al regresar.',
      range_of_motion:'Usa un rango cómodo y controlado.',
      cues:['Codos hacia abajo.'],
      common_errors:['Balancear el torso.'],
      safety:['Detén el ejercicio si aparece dolor articular.'],
      coach_note:'Ajusta el agarre según comodidad y proporciones corporales.'
    }
  };
  await route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(payload)});
});

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

  await page.waitForFunction(()=>{
    const cards=[...document.querySelectorAll('.cvHevyExercise,.workoutExercise')];
    const buttons=[...document.querySelectorAll('.cvDetailsLinkV103')];
    return cards.length>=2&&buttons.length===cards.length;
  },null,{timeout:7000,polling:100});

  const pre=await page.evaluate(()=>{
    const card=document.querySelector('.cvHevyExercise,.workoutExercise');
    const title=card?.querySelector('.exerciseTop h3');
    const button=card?.querySelector('.cvDetailsLinkV103');
    return {
      cardTitle:title?.textContent?.trim()||'',
      buttonText:button?.textContent?.trim()||'',
      sharesTitleRow:!!title&&!!button&&title.parentElement===button.parentElement,
      buttonVisible:!!button&&getComputedStyle(button).display!=='none'&&button.getBoundingClientRect().width>0
    };
  });
  assert.equal(pre.buttonText,'Ver detalles','Explicit detail link text is wrong');
  assert.equal(pre.sharesTitleRow,true,'Detail link is not beside the exercise title');
  assert.equal(pre.buttonVisible,true,'Detail link is not visible');

  await page.locator('.cvDetailsLinkV103').first().click();
  await page.waitForFunction(()=>{
    const backdrop=document.getElementById('cvTechniqueDetailsV103');
    const content=backdrop?.querySelector('#cvV103Content')?.textContent||'';
    return backdrop?.classList.contains('show')&&content.includes('Agarre, separación y postura')&&content.includes('Tiempos de ejecución')&&content.includes('Ejecución paso a paso');
  },null,{timeout:7000,polling:100});

  const state=await page.evaluate(()=>{
    const backdrop=document.getElementById('cvTechniqueDetailsV103');
    const sheet=backdrop?.querySelector('.cvTechSheet');
    const content=backdrop?.querySelector('#cvV103Content')?.textContent||'';
    const phases=[...backdrop?.querySelectorAll('.cvV103TempoPhase')||[]];
    return {
      open:backdrop?.classList.contains('show')||false,
      title:backdrop?.querySelector('#cvV103Title')?.textContent?.trim()||'',
      sheetHeight:sheet?.getBoundingClientRect().height||0,
      hasGrip:content.includes('Agarre, separación y postura'),
      hasSteps:content.includes('Ejecución paso a paso'),
      hasTempo:content.includes('Tiempos de ejecución'),
      hasErrors:content.includes('Errores frecuentes'),
      hasSafety:content.includes('Seguridad y ajustes'),
      tempoPhases:phases.length,
      seconds:[...backdrop?.querySelectorAll('.cvV103Seconds')||[]].map(x=>x.textContent?.trim()||'')
    };
  });

  assert.equal(state.open,true,'V103 detail sheet did not open');
  assert.equal(state.title,pre.cardTitle,'Detail sheet title does not match exercise');
  assert.ok(state.sheetHeight>300,`Detail sheet is not visibly sized: ${state.sheetHeight}`);
  assert.equal(state.hasGrip,true,'Grip/spacing section missing');
  assert.equal(state.hasSteps,true,'Execution steps section missing');
  assert.equal(state.hasTempo,true,'Tempo section missing');
  assert.equal(state.hasErrors,true,'Common errors section missing');
  assert.equal(state.hasSafety,true,'Safety section missing');
  assert.equal(state.tempoPhases,3,'Expected three explicit tempo phases');
  assert.ok(state.seconds.some(x=>x.includes('2')),'Tempo seconds are not visible');
  assert.equal(errors.length,0,'Browser errors: '+errors.join(' | '));

  await page.locator('#cvTechniqueDetailsV103 .cvTechClose').click();
  await page.waitForFunction(()=>!document.getElementById('cvTechniqueDetailsV103')?.classList.contains('show'),null,{timeout:2000});

  console.log('CV_V103_BROWSER_STATE',JSON.stringify(state));
  console.log('CV_EXERCISE_DETAILS_V103_BROWSER_WEBKIT_OK');
} finally {
  await context.close().catch(()=>{});
  await browser.close().catch(()=>{});
}
