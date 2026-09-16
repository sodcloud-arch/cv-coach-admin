(()=>{
'use strict';

const READY='CV_EXERCISE_DETAILS_V103_READY';
const VERSION='103';
const STYLE_ID='cv-exercise-details-v103-style';
const BACKDROP_ID='cvTechniqueDetailsV103';
const BUTTON_CLASS='cvDetailsLinkV103';
const TITLE_ROW_CLASS='cvDetailsTitleRowV103';
let scheduled=false;
let observer=null;
let requestSerial=0;

function injectStyle(){
  if(document.getElementById(STYLE_ID))return;
  const style=document.createElement('style');
  style.id=STYLE_ID;
  style.textContent=`
  .cvDetailsTitleRowV103,.cvExerciseTitleRowV35{display:flex!important;align-items:baseline!important;gap:9px!important;flex-wrap:wrap!important}
  .cvDetailsTitleRowV103>h3,.cvExerciseTitleRowV35>h3{flex:0 1 auto!important;min-width:0!important;margin-right:0!important}
  .cvDetailsLinkV103{appearance:none;border:0;background:transparent;color:#69cfff;font:800 9.5px/1 Inter,system-ui,sans-serif;letter-spacing:.055em;text-transform:uppercase;padding:7px 0 6px;cursor:pointer;text-decoration:underline;text-decoration-color:rgba(105,207,255,.42);text-underline-offset:3px;white-space:nowrap;touch-action:manipulation;-webkit-tap-highlight-color:transparent}
  .cvDetailsLinkV103:active{opacity:.62}
  .cvTechBackdrop.cvV103Backdrop{z-index:260!important;background:rgba(0,0,0,.82)!important;backdrop-filter:blur(8px)!important}
  .cvV103Backdrop .cvTechSheet{width:min(620px,100%)!important;max-height:92dvh!important;padding:12px 16px calc(28px + env(safe-area-inset-bottom))!important;background:linear-gradient(165deg,#0b1217,#05090c 72%)!important;border-color:#2b3a43!important}
  .cvV103Eyebrow{margin:0 0 5px;color:#5fc9fb;font-size:8px;font-weight:900;letter-spacing:.16em;text-transform:uppercase}
  .cvV103Meta{display:flex;flex-wrap:wrap;gap:6px;margin:2px 0 13px}
  .cvV103Chip{display:inline-flex;align-items:center;min-height:25px;padding:0 9px;border:1px solid #2b3b45;border-radius:999px;background:#0d151a;color:#aebbc2;font-size:8.5px;font-weight:800;letter-spacing:.02em}
  .cvV103Chip strong{color:#eff7fa;font-weight:900;margin-left:4px}
  .cvV103HeroMedia{position:relative;min-height:180px;margin:0 0 14px;border:1px solid #27353e;border-radius:16px;background:#020507;overflow:hidden;display:grid;place-items:center}
  .cvV103HeroMedia img{display:block;width:100%;height:auto;max-height:48vh;object-fit:contain;background:#020507}
  .cvV103HeroMedia .cvTechLoading{font-size:11px;padding:40px 16px;text-align:center}
  .cvV103Section{margin:11px 0 0;padding:14px;border:1px solid #27343c;border-radius:14px;background:linear-gradient(180deg,#0a1014,#070b0e)}
  .cvV103Section h4{margin:0 0 9px;color:#ff5b70;font-size:10px;font-weight:900;letter-spacing:.12em;text-transform:uppercase}
  .cvV103Section p{margin:0;color:#dde5e9;font-size:13.5px;line-height:1.58}
  .cvV103Section p+p{margin-top:8px}
  .cvV103List{list-style:none;margin:0;padding:0;display:grid;gap:8px}
  .cvV103List li{position:relative;padding-left:17px;color:#d8e0e4;font-size:12.5px;line-height:1.5}
  .cvV103List li:before{content:'•';position:absolute;left:2px;top:-1px;color:#67d3ff;font-size:18px;line-height:1}
  .cvV103Steps{display:grid;gap:8px}
  .cvV103Step{display:grid;grid-template-columns:30px minmax(0,1fr);gap:9px;padding:9px;border:1px solid #223039;border-radius:11px;background:#080e12}
  .cvV103StepNo{width:30px;height:30px;border-radius:9px;display:grid;place-items:center;background:#0a2330;border:1px solid #225572;color:#7bd9ff;font:900 14px 'Barlow Condensed',sans-serif}
  .cvV103Step b{display:block;color:#f0f5f7;font-size:12px;margin:1px 0 3px}.cvV103Step span{display:block;color:#aeb9bf;font-size:11px;line-height:1.48}
  .cvV103Grid{display:grid;grid-template-columns:1fr;gap:8px}
  .cvV103Fact{padding:10px 11px;border:1px solid #223039;border-radius:11px;background:#080e12}
  .cvV103Fact small{display:block;margin-bottom:4px;color:#6ecff8;font-size:8px;font-weight:900;letter-spacing:.10em;text-transform:uppercase}
  .cvV103Fact b{display:block;color:#edf3f5;font-size:12px;line-height:1.45}.cvV103Fact span{display:block;color:#a8b4ba;font-size:10.5px;line-height:1.48;margin-top:4px}
  .cvV103Tempo{display:grid;gap:8px}
  .cvV103TempoPhase{display:grid;grid-template-columns:minmax(0,1fr) auto;gap:10px;align-items:center;padding:10px 11px;border:1px solid #263740;border-radius:11px;background:#081015}
  .cvV103TempoPhase b{display:block;color:#f1f6f8;font-size:11.5px}.cvV103TempoPhase span{display:block;margin-top:3px;color:#9fadb4;font-size:9.5px;line-height:1.42}.cvV103Seconds{min-width:46px;text-align:center;color:#74d9ff;font:900 21px 'Barlow Condensed',sans-serif}.cvV103Seconds small{display:block;color:#77909b;font:800 7px Inter,sans-serif;letter-spacing:.08em;text-transform:uppercase}
  .cvV103TempoNote{margin-top:9px!important;color:#9faeb5!important;font-size:10.5px!important}
  .cvV103Coach{border-color:#5a3d19!important;background:linear-gradient(180deg,#171006,#0b0a08)!important}.cvV103Coach h4{color:#ffc46d!important}
  .cvV103Warning{border-color:#4a2d34!important;background:linear-gradient(180deg,#140b0e,#0a0809)!important}.cvV103Warning h4{color:#ff8091!important}
  .cvV103Fallback{padding:11px 12px;border:1px dashed #35444d;border-radius:11px;color:#93a2a9;font-size:10.5px;line-height:1.5;background:#070b0e}
  .cvV103Loading{padding:18px 0;text-align:center;color:#87969e;font-size:11px}
  @media(min-width:520px){.cvV103Grid.cvV103Two{grid-template-columns:repeat(2,minmax(0,1fr))}}
  @media(max-width:390px){.cvDetailsLinkV103{font-size:9px}.cvV103Backdrop .cvTechSheet{padding-left:13px!important;padding-right:13px!important}.cvV103Section{padding:12px}.cvV103Section p{font-size:13px}.cvV103List li{font-size:12px}}
  `;
  document.head.appendChild(style);
}

function text(value){return value==null?'':String(value)}
function hasObject(value){return value&&typeof value==='object'&&!Array.isArray(value)&&Object.keys(value).length>0}
function array(value){return Array.isArray(value)?value.filter(Boolean):[]}
function node(tag,className,content){const el=document.createElement(tag);if(className)el.className=className;if(content!=null)el.textContent=text(content);return el}

function ensureSheet(){
  let backdrop=document.getElementById(BACKDROP_ID);
  if(backdrop)return backdrop;
  backdrop=node('div','cvTechBackdrop cvV103Backdrop');
  backdrop.id=BACKDROP_ID;
  const sheet=node('div','cvTechSheet');
  sheet.setAttribute('role','dialog');sheet.setAttribute('aria-modal','true');sheet.setAttribute('aria-labelledby','cvV103Title');
  const handle=node('div','cvTechHandle');
  const head=node('div','cvTechHead');
  const titleWrap=node('div','grow');
  titleWrap.append(node('div','cvV103Eyebrow','TÉCNICA DETALLADA'));
  const title=node('h2','', 'Ejercicio');title.id='cvV103Title';titleWrap.append(title);
  const close=node('button','cvTechClose','×');close.type='button';close.setAttribute('aria-label','Cerrar detalles del ejercicio');
  head.append(titleWrap,close);
  const meta=node('div','cvV103Meta');meta.id='cvV103Meta';
  const media=node('div','cvV103HeroMedia');media.id='cvV103Media';
  const content=node('div','');content.id='cvV103Content';
  sheet.append(handle,head,meta,media,content);backdrop.append(sheet);document.body.append(backdrop);
  const closeSheet=()=>{backdrop.classList.remove('show');document.body.style.overflow='';};
  close.addEventListener('click',closeSheet);
  backdrop.addEventListener('click',event=>{if(event.target===backdrop)closeSheet()});
  document.addEventListener('keydown',event=>{if(event.key==='Escape'&&backdrop.classList.contains('show'))closeSheet()});
  return backdrop;
}

function addChip(parent,label,value){if(!value)return;const chip=node('span','cvV103Chip');chip.append(document.createTextNode(label+' '));chip.append(node('strong','',value));parent.append(chip)}
function section(title,className=''){const box=node('section','cvV103Section '+className);box.append(node('h4','',title));return box}
function addList(box,items){const vals=array(items);if(!vals.length)return false;const ul=node('ul','cvV103List');vals.forEach(item=>ul.append(node('li','',typeof item==='string'?item:(item.detail||item.title||''))));box.append(ul);return true}
function addParagraph(box,value){if(!value)return false;box.append(node('p','',value));return true}
function addFact(grid,label,value,detail){if(!value&&!detail)return;const fact=node('div','cvV103Fact');fact.append(node('small','',label));if(value)fact.append(node('b','',value));if(detail)fact.append(node('span','',detail));grid.append(fact)}

function humanTempo(raw){
  const value=text(raw).trim();if(!value)return 'Movimiento controlado, sin rebotes ni impulso.';
  if(/isom/i.test(value))return 'Mantén la posición durante el tiempo indicado sin perder tensión.';
  if(/continuo/i.test(value))return 'Mantén un ritmo continuo, estable y controlado.';
  const parts=value.split('-').map(Number);
  if(parts.length>=3&&parts.every(Number.isFinite))return `Tempo ${value}: controla cada fase según la prescripción de tu coach.`;
  return value;
}

function renderMedia(media,src,name){
  media.replaceChildren();
  if(!src){media.append(node('div','cvTechLoading','Lámina no disponible.'));return;}
  const img=new Image();img.alt=name||'Ejercicio';img.decoding='async';img.loading='eager';
  img.onload=()=>{media.replaceChildren(img)};
  img.onerror=()=>{media.replaceChildren(node('div','cvTechLoading','No se pudo cargar la lámina.'))};
  media.append(node('div','cvTechLoading','Cargando lámina…'));img.src=src;
}

function renderTempo(content,details,tempoRaw){
  const tempo=hasObject(details?.tempo)?details.tempo:null;
  const box=section('Tiempos de ejecución');
  if(tempo&&array(tempo.phases).length){
    const wrap=node('div','cvV103Tempo');
    array(tempo.phases).forEach(phase=>{
      const row=node('div','cvV103TempoPhase');const copy=node('div','');copy.append(node('b','',phase.label||'Fase'));if(phase.cue)copy.append(node('span','',phase.cue));
      const seconds=node('div','cvV103Seconds',phase.seconds!=null?phase.seconds:'—');seconds.append(node('small','','segundos'));
      row.append(copy,seconds);wrap.append(row);
    });
    box.append(wrap);
    if(tempo.notation)box.append(node('p','cvV103TempoNote',`Tempo de referencia: ${tempo.notation}.`));
    if(tempo.note)box.append(node('p','cvV103TempoNote',tempo.note));
  }else{
    addParagraph(box,humanTempo(tempoRaw));
    box.append(node('div','cvV103Fallback','Esta ficha todavía usa el tempo general del ejercicio. Cuando exista una ficha curada, cada fase aparecerá separada con sus segundos y cues específicos.'));
  }
  content.append(box);
}

function renderDetails(info,card){
  const backdrop=ensureSheet(),details=hasObject(info?.technique_details)?info.technique_details:{};
  const title=backdrop.querySelector('#cvV103Title'),meta=backdrop.querySelector('#cvV103Meta'),media=backdrop.querySelector('#cvV103Media'),content=backdrop.querySelector('#cvV103Content');
  const name=info?.name||card?.getAttribute('data-tech-name')||'Ejercicio';
  title.textContent=name;meta.replaceChildren();content.replaceChildren();
  addChip(meta,'Músculo',info?.primary_muscle);addChip(meta,'Equipo',info?.equipment);addChip(meta,'Nivel',info?.difficulty);if(info?.default_rest_sec)addChip(meta,'Descanso',`${info.default_rest_sec} s`);
  renderMedia(media,card?.getAttribute('data-tech-img')||info?.image_path||'',name);

  const intro=section('Objetivo técnico');
  addParagraph(intro,details.summary||info?.instructions||card?.getAttribute('data-tech-instructions')||'Sigue la técnica indicada por tu coach.');content.append(intro);

  if(hasObject(details.grip)||hasObject(details.body_position)){
    const box=section('Agarre, separación y postura');const grid=node('div','cvV103Grid cvV103Two');
    const g=details.grip||{},b=details.body_position||{};
    addFact(grid,'Tipo de agarre',g.type,g.hands);addFact(grid,'Separación',g.width,g.arm_spacing);addFact(grid,'Torso',b.torso);addFact(grid,'Hombros',b.shoulders);addFact(grid,'Cabeza',b.head);
    box.append(grid);content.append(box);
  }

  if(array(details.setup).length){const box=section('Ajuste de la máquina y posición inicial');addList(box,details.setup);content.append(box)}
  if(array(details.execution_steps).length){const box=section('Ejecución paso a paso');const steps=node('div','cvV103Steps');array(details.execution_steps).forEach((step,index)=>{const row=node('div','cvV103Step');row.append(node('div','cvV103StepNo',step.number||index+1));const copy=node('div','');copy.append(node('b','',step.title||`Paso ${index+1}`));copy.append(node('span','',step.detail||''));row.append(copy);steps.append(row)});box.append(steps);content.append(box)}

  renderTempo(content,details,info?.default_tempo||card?.getAttribute('data-tech-tempo'));

  if(details.breathing||details.range_of_motion){const box=section('Respiración y recorrido');const grid=node('div','cvV103Grid');addFact(grid,'Respiración',details.breathing);addFact(grid,'Rango de movimiento',details.range_of_motion);box.append(grid);content.append(box)}
  if(array(details.cues).length){const box=section('Cues rápidos');addList(box,details.cues);content.append(box)}
  if(array(details.common_errors).length){const box=section('Errores frecuentes','cvV103Warning');addList(box,details.common_errors);content.append(box)}
  if(array(details.safety).length){const box=section('Seguridad y ajustes','cvV103Warning');addList(box,details.safety);content.append(box)}
  if(details.coach_note){const box=section('Nota del coach','cvV103Coach');addParagraph(box,details.coach_note);content.append(box)}

  if(!hasObject(details)){
    const fallback=section('Ficha avanzada');fallback.append(node('div','cvV103Fallback','Este ejercicio ya muestra instrucciones, tempo y descanso. Su ficha técnica avanzada todavía no ha sido curada con separación, postura, pasos, cues y errores específicos.'));content.append(fallback);
  }
}

function fallbackInfo(card){return {
  name:card?.getAttribute('data-tech-name')||'Ejercicio',instructions:card?.getAttribute('data-tech-instructions')||'',default_tempo:card?.getAttribute('data-tech-tempo')||'',image_path:card?.getAttribute('data-tech-img')||'',technique_details:{}
}}

async function fetchInfo(name,card){
  try{
    if(typeof sb!=='undefined'&&sb?.rpc){
      const {data,error}=await sb.rpc('get_exercise_technique_v103',{p_name:name});
      if(!error&&data)return data;
    }
  }catch(_){/* fallback below */}
  return fallbackInfo(card);
}

async function openDetails(index){
  const cards=[...document.querySelectorAll('.cvHevyExercise,.workoutExercise')];const card=cards[index];if(!card)return;
  const backdrop=ensureSheet(),name=card.getAttribute('data-tech-name')||card.querySelector('.exerciseTop h3')?.textContent?.trim()||'Ejercicio';
  const serial=++requestSerial;renderDetails(fallbackInfo(card),card);backdrop.classList.add('show');document.body.style.overflow='hidden';
  const content=backdrop.querySelector('#cvV103Content');const loading=node('div','cvV103Loading','Cargando ficha técnica completa…');content.prepend(loading);
  const info=await fetchInfo(name,card);if(serial!==requestSerial)return;renderDetails(info||fallbackInfo(card),card);
}

function ensureButton(card,index){
  if(!(card instanceof HTMLElement))return;
  const top=card.querySelector('.exerciseTop'),title=top?.querySelector('h3');if(!top||!title)return;
  let row=title.closest('.cvExerciseTitleRowV35,.cvDetailsTitleRowV103');
  if(!row){row=node('div',TITLE_ROW_CLASS);const parent=title.parentElement;if(!parent)return;parent.insertBefore(row,title);row.append(title)}
  let button=row.querySelector(`.${BUTTON_CLASS}`);
  if(!button){button=node('button',BUTTON_CLASS,'Ver detalles');button.type='button';row.append(button)}
  button.dataset.cvDetailsIndex=String(index);button.setAttribute('aria-label',`Ver detalles de ${card.getAttribute('data-tech-name')||title.textContent?.trim()||'ejercicio'}`);
  if(button.dataset.cvBound!=='1'){
    button.dataset.cvBound='1';button.addEventListener('click',event=>{event.preventDefault();event.stopPropagation();openDetails(Number(button.dataset.cvDetailsIndex||0))});
  }
}

function apply(){scheduled=false;document.querySelectorAll('.cvHevyExercise,.workoutExercise').forEach((card,index)=>ensureButton(card,index))}
function schedule(){if(scheduled)return;scheduled=true;requestAnimationFrame(apply)}
function enable(){injectStyle();schedule();if(!observer){observer=new MutationObserver(schedule);observer.observe(document.body,{childList:true,subtree:true})}}

enable();
window.cvOpenTechnique=openDetails;
window.CVExerciseDetailsV103={version:VERSION,ready:true,refresh:schedule,open:openDetails};
console.info(READY,VERSION);
})();
