(()=>{
'use strict';

const CV_EXERCISE_SCREEN_V102_READY='CV_EXERCISE_SCREEN_V102_READY';
const QUERY_KEY='cv_v102';
const STORAGE_KEY='cv_v102_experiment';
const ROOT_CLASS='cvExerciseScreenV102Root';
const BODY_CLASS='cvExerciseScreenV102';
const CARD_CLASS='cvExerciseScreenCardV102';
const LEGACY_MAIN_CLASS='cvExerciseLegacyMainV102';
const STYLE_ID='cv-exercise-screen-v102-style';
let observer=null;
let scheduled=false;

function resolveExperiment(){
  try{
    const url=new URL(location.href);
    const requested=url.searchParams.get(QUERY_KEY);
    if(requested==='1')localStorage.setItem(STORAGE_KEY,'1');
    if(requested==='0')localStorage.removeItem(STORAGE_KEY);
    return localStorage.getItem(STORAGE_KEY)==='1';
  }catch(_){return false;}
}

function css(){return `
html.${ROOT_CLASS}{scroll-snap-type:y proximity;scroll-padding-top:82px}
body.${BODY_CLASS}.cvFastWorkout .${CARD_CLASS}{scroll-snap-align:start;scroll-snap-stop:normal;scroll-margin-top:82px!important}
body.${BODY_CLASS}.cvFastWorkout .cvExecutionBtnV35{display:none!important}
body.${BODY_CLASS}.cvFastWorkout .cvExerciseTitleRowV35{display:block!important;margin:0!important}
body.${BODY_CLASS}.cvFastWorkout .cvExerciseTitleRowV35 h3{margin:1px 0 6px!important;cursor:default!important}
body.${BODY_CLASS}.cvFastWorkout .cvExerciseTitleRowV35 h3:after,
body.${BODY_CLASS}.cvFastWorkout .exerciseTop h3:after{display:none!important;content:none!important}
body.${BODY_CLASS}.cvFastWorkout .${LEGACY_MAIN_CLASS}{display:none!important}

@media(max-width:699px){
  body.${BODY_CLASS}.cvFastWorkout .${CARD_CLASS}{padding:14px 12px 14px!important}
  body.${BODY_CLASS}.cvFastWorkout .${CARD_CLASS}>.exerciseMedia{
    display:grid!important;
    place-items:center!important;
    width:100%!important;
    height:min(240px,62vw)!important;
    min-height:min(240px,62vw)!important;
    max-height:240px!important;
    margin:10px 0 10px!important;
    padding:0!important;
    overflow:hidden!important;
    border:1px solid #2a3740!important;
    border-radius:13px!important;
    background:#030608!important;
    box-shadow:inset 0 1px 0 rgba(255,255,255,.025),0 10px 26px rgba(0,0,0,.22)!important;
  }
  body.${BODY_CLASS}.cvFastWorkout .${CARD_CLASS}>.exerciseMedia:after{display:none!important;content:none!important}
  body.${BODY_CLASS}.cvFastWorkout .${CARD_CLASS}>.exerciseMedia .photo{
    display:block!important;
    width:100%!important;
    height:100%!important;
    min-height:0!important;
    max-height:none!important;
    aspect-ratio:auto!important;
    object-fit:contain!important;
    object-position:center!important;
    margin:0!important;
    border:0!important;
    border-radius:0!important;
    background:#030608!important;
  }
  body.${BODY_CLASS}.cvFastWorkout .${CARD_CLASS}>.exerciseMedia .cvV102MediaFallback{
    width:100%;height:100%;display:grid;place-items:center;text-align:center;padding:24px;
    color:#7f8c94;font-size:10px;font-weight:800;letter-spacing:.03em;line-height:1.45;
    background:radial-gradient(circle at 50% 45%,#11191e,#040708 70%);
  }
  body.${BODY_CLASS}.cvFastWorkout .${CARD_CLASS}>.exerciseMedia .cvV102MediaFallback b{
    display:block;margin-bottom:5px;color:#dce2e5;font:900 28px/1 'Barlow Condensed',sans-serif;
  }
  body.${BODY_CLASS}.cvFastWorkout .${CARD_CLASS}>.cvRestText{margin-left:0!important;margin-top:2px!important;margin-bottom:9px!important}
  body.${BODY_CLASS}.cvFastWorkout .${CARD_CLASS}>.cvSetsHead,
  body.${BODY_CLASS}.cvFastWorkout .${CARD_CLASS}>.cvSetRows,
  body.${BODY_CLASS}.cvFastWorkout .${CARD_CLASS}>.cvAddSet{width:100%!important;margin-left:0!important;margin-right:0!important}
  body.${BODY_CLASS}.cvFastWorkout .${CARD_CLASS} .exerciseTop{margin-bottom:0!important}
}

@media(max-width:390px){
  body.${BODY_CLASS}.cvFastWorkout .${CARD_CLASS}>.exerciseMedia{
    height:min(232px,62vw)!important;
    min-height:min(232px,62vw)!important;
  }
}

@media(max-width:350px){
  body.${BODY_CLASS}.cvFastWorkout .${CARD_CLASS}>.exerciseMedia{
    height:min(216px,62vw)!important;
    min-height:min(216px,62vw)!important;
  }
}
`}

function injectStyle(){
  if(document.getElementById(STYLE_ID))return;
  const style=document.createElement('style');
  style.id=STYLE_ID;
  style.textContent=css();
  document.head.appendChild(style);
}

function ensureFallback(media,name){
  if(!media||media.querySelector('.photo'))return;
  if(media.querySelector('.cvV102MediaFallback'))return;
  const fallback=document.createElement('div');
  fallback.className='cvV102MediaFallback';
  fallback.innerHTML=`<div><b>CV</b>${String(name||'Lámina del ejercicio').replace(/[<>]/g,'')}</div>`;
  media.appendChild(fallback);
}

function bindImageState(media,name){
  const img=media?.querySelector('.photo');
  if(!img){ensureFallback(media,name);return;}
  if(img.dataset.cvV102Bound==='1')return;
  img.dataset.cvV102Bound='1';
  img.addEventListener('error',()=>{
    img.style.display='none';
    ensureFallback(media,'Lámina no disponible');
  },{once:true});
}

function upgradeCard(card,index){
  if(!(card instanceof HTMLElement))return;
  card.classList.add(CARD_CLASS);
  card.dataset.cvV102Index=String(index+1);

  const top=card.querySelector('.exerciseTop');
  const title=top?.querySelector('h3');
  const media=card.querySelector('.exerciseMedia');
  const legacyMain=card.querySelector('.exerciseMain');

  card.querySelectorAll('.cvExecutionBtnV35').forEach(button=>button.remove());
  if(title){
    title.removeAttribute('title');
    title.setAttribute('aria-label',title.textContent?.trim()||`Ejercicio ${index+1}`);
  }

  if(media&&top){
    if(media.parentElement!==card||media.previousElementSibling!==top){
      top.insertAdjacentElement('afterend',media);
    }
    media.dataset.cvV102Media='1';
    bindImageState(media,title?.textContent?.trim());
  }

  if(legacyMain){
    legacyMain.classList.add(LEGACY_MAIN_CLASS);
    legacyMain.setAttribute('aria-hidden','true');
  }
}

function apply(){
  scheduled=false;
  if(!document.body?.classList.contains(BODY_CLASS))return;
  if(!document.body.classList.contains('cvFastWorkout'))return;
  const cards=[...document.querySelectorAll('.cvHevyExercise,.workoutExercise')];
  cards.forEach((card,index)=>upgradeCard(card,index));
}

function schedule(){
  if(scheduled)return;
  scheduled=true;
  requestAnimationFrame(apply);
}

function enable(){
  injectStyle();
  document.documentElement.classList.add(ROOT_CLASS);
  document.body?.classList.add(BODY_CLASS);
  schedule();
  if(!observer){
    observer=new MutationObserver(schedule);
    observer.observe(document.body,{childList:true,subtree:true});
  }
}

function disable(){
  document.documentElement.classList.remove(ROOT_CLASS);
  document.body?.classList.remove(BODY_CLASS);
  observer?.disconnect();observer=null;
}

const enabled=resolveExperiment();
if(enabled)enable();

window.CVExerciseScreenV102={
  version:'102',
  ready:true,
  enabled,
  enableExperiment(){localStorage.setItem(STORAGE_KEY,'1');location.reload()},
  disableExperiment(){localStorage.removeItem(STORAGE_KEY);location.reload()},
  refresh:schedule
};
console.info(CV_EXERCISE_SCREEN_V102_READY,enabled?'ENABLED':'DISABLED');
})();
