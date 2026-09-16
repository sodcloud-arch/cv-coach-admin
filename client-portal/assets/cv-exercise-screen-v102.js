(()=>{
'use strict';

const CV_EXERCISE_SCREEN_V102_READY='CV_EXERCISE_SCREEN_V102_READY';
const CONTRACT_REVISION='V102.1_ACTIVE_FOCUS';
const QUERY_KEY='cv_v102';
const STORAGE_KEY='cv_v102_experiment';
const ROOT_CLASS='cvExerciseScreenV102Root';
const BODY_CLASS='cvExerciseScreenV102';
const CARD_CLASS='cvExerciseScreenCardV102';
const EXPANDED_CLASS='cvV102Expanded';
const COLLAPSED_CLASS='cvV102Collapsed';
const LEGACY_MAIN_CLASS='cvExerciseLegacyMainV102';
const STYLE_ID='cv-exercise-screen-v102-style';
let observer=null;
let scheduled=false;
let lastCurrentKey=null;
let hasAppliedActiveState=false;

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
html.${ROOT_CLASS}{scroll-snap-type:y proximity;scroll-padding-top:128px}
body.${BODY_CLASS}.cvWorkoutActiveV40 .${CARD_CLASS}{scroll-snap-align:start;scroll-snap-stop:normal;scroll-margin-top:128px!important}
body.${BODY_CLASS}.cvWorkoutActiveV40 .cvExecutionBtnV35{display:none!important}
body.${BODY_CLASS}.cvWorkoutActiveV40 .cvExerciseTitleRowV35{display:block!important;margin:0!important}
body.${BODY_CLASS}.cvWorkoutActiveV40 .cvExerciseTitleRowV35 h3{margin:1px 0 6px!important;cursor:default!important}
body.${BODY_CLASS}.cvWorkoutActiveV40 .cvExerciseTitleRowV35 h3:after,
body.${BODY_CLASS}.cvWorkoutActiveV40 .exerciseTop h3:after{display:none!important;content:none!important}
body.${BODY_CLASS}.cvWorkoutActiveV40 .${LEGACY_MAIN_CLASS}{display:none!important}

/* Only the active exercise owns the workout canvas. */
body.${BODY_CLASS}.cvWorkoutActiveV40 .${CARD_CLASS}.${EXPANDED_CLASS}{opacity:1!important}
body.${BODY_CLASS}.cvWorkoutActiveV40 .${CARD_CLASS}.${COLLAPSED_CLASS}{
  padding:12px 12px!important;
  min-height:0!important;
  opacity:.84!important;
  transform:none!important;
  box-shadow:0 9px 22px rgba(0,0,0,.18)!important;
}
body.${BODY_CLASS}.cvWorkoutActiveV40 .${CARD_CLASS}.${COLLAPSED_CLASS} .exerciseTop{margin:0!important;align-items:center!important}
body.${BODY_CLASS}.cvWorkoutActiveV40 .${CARD_CLASS}.${COLLAPSED_CLASS} .exerciseTop h3{font-size:21px!important;line-height:1.04!important;margin:0 0 4px!important}
body.${BODY_CLASS}.cvWorkoutActiveV40 .${CARD_CLASS}.${COLLAPSED_CLASS} .cvPrescription{margin:0!important}
body.${BODY_CLASS}.cvWorkoutActiveV40 .${CARD_CLASS}.${COLLAPSED_CLASS} .cvPrescriptionChip{min-height:21px!important;font-size:7.4px!important;padding:0 6px!important}
body.${BODY_CLASS}.cvWorkoutActiveV40 .${CARD_CLASS}.${COLLAPSED_CLASS}>.exerciseMedia,
body.${BODY_CLASS}.cvWorkoutActiveV40 .${CARD_CLASS}.${COLLAPSED_CLASS}>.cvRestText,
body.${BODY_CLASS}.cvWorkoutActiveV40 .${CARD_CLASS}.${COLLAPSED_CLASS}>.cvSetsHead,
body.${BODY_CLASS}.cvWorkoutActiveV40 .${CARD_CLASS}.${COLLAPSED_CLASS}>.cvSetRows,
body.${BODY_CLASS}.cvWorkoutActiveV40 .${CARD_CLASS}.${COLLAPSED_CLASS}>.cvAddSet,
body.${BODY_CLASS}.cvWorkoutActiveV40 .${CARD_CLASS}.${COLLAPSED_CLASS}>.cvExerciseProgress{display:none!important}
body.${BODY_CLASS}.cvWorkoutActiveV40 .${CARD_CLASS}.${COLLAPSED_CLASS} .cvExerciseStatusV31{margin-top:1px!important}

@media(max-width:699px){
  body.${BODY_CLASS}.cvWorkoutActiveV40 .${CARD_CLASS}.${EXPANDED_CLASS}{padding:14px 12px 14px!important}
  body.${BODY_CLASS}.cvWorkoutActiveV40 .${CARD_CLASS}.${EXPANDED_CLASS}>.exerciseMedia{
    display:grid!important;
    place-items:center!important;
    width:100%!important;
    height:min(244px,63vw)!important;
    min-height:min(244px,63vw)!important;
    max-height:244px!important;
    margin:10px 0 11px!important;
    padding:0!important;
    overflow:hidden!important;
    border:1px solid #2a3740!important;
    border-radius:13px!important;
    background:#030608!important;
    box-shadow:inset 0 1px 0 rgba(255,255,255,.025),0 10px 26px rgba(0,0,0,.22)!important;
  }
  body.${BODY_CLASS}.cvWorkoutActiveV40 .${CARD_CLASS}.${EXPANDED_CLASS}>.exerciseMedia:after{display:none!important;content:none!important}
  body.${BODY_CLASS}.cvWorkoutActiveV40 .${CARD_CLASS}.${EXPANDED_CLASS}>.exerciseMedia .photo{
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
  body.${BODY_CLASS}.cvWorkoutActiveV40 .${CARD_CLASS}.${EXPANDED_CLASS}>.exerciseMedia .cvV102MediaFallback{
    width:100%;height:100%;display:grid;place-items:center;text-align:center;padding:24px;
    color:#7f8c94;font-size:10px;font-weight:800;letter-spacing:.03em;line-height:1.45;
    background:radial-gradient(circle at 50% 45%,#11191e,#040708 70%);
  }
  body.${BODY_CLASS}.cvWorkoutActiveV40 .${CARD_CLASS}.${EXPANDED_CLASS}>.exerciseMedia .cvV102MediaFallback b{
    display:block;margin-bottom:5px;color:#dce2e5;font:900 28px/1 'Barlow Condensed',sans-serif;
  }
  body.${BODY_CLASS}.cvWorkoutActiveV40 .${CARD_CLASS}.${EXPANDED_CLASS}>.cvRestText{margin-left:0!important;margin-top:2px!important;margin-bottom:9px!important}
  body.${BODY_CLASS}.cvWorkoutActiveV40 .${CARD_CLASS}.${EXPANDED_CLASS}>.cvSetsHead,
  body.${BODY_CLASS}.cvWorkoutActiveV40 .${CARD_CLASS}.${EXPANDED_CLASS}>.cvSetRows,
  body.${BODY_CLASS}.cvWorkoutActiveV40 .${CARD_CLASS}.${EXPANDED_CLASS}>.cvAddSet{width:100%!important;margin-left:0!important;margin-right:0!important}
  body.${BODY_CLASS}.cvWorkoutActiveV40 .${CARD_CLASS}.${EXPANDED_CLASS} .exerciseTop{margin-bottom:0!important}
}

@media(max-width:390px){
  body.${BODY_CLASS}.cvWorkoutActiveV40 .${CARD_CLASS}.${EXPANDED_CLASS}>.exerciseMedia{
    height:min(232px,63vw)!important;
    min-height:min(232px,63vw)!important;
  }
  body.${BODY_CLASS}.cvWorkoutActiveV40 .${CARD_CLASS}.${COLLAPSED_CLASS} .exerciseTop h3{font-size:20px!important}
}

@media(max-width:350px){
  body.${BODY_CLASS}.cvWorkoutActiveV40 .${CARD_CLASS}.${EXPANDED_CLASS}>.exerciseMedia{
    height:min(216px,63vw)!important;
    min-height:min(216px,63vw)!important;
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

function ensureMedia(card,title){
  let media=card.querySelector('.exerciseMedia');
  if(media)return media;
  const src=String(card.getAttribute('data-tech-img')||'').trim();
  media=document.createElement('div');
  media.className='exerciseMedia';
  media.dataset.cvV102Generated='1';
  if(src){
    const img=document.createElement('img');
    img.className='photo';
    img.loading='eager';
    img.decoding='async';
    img.alt=title?.textContent?.trim()||card.getAttribute('data-tech-name')||'Ejercicio';
    img.src=src;
    media.appendChild(img);
  }
  return media;
}

function isWorkoutActive(){
  return document.body?.classList.contains('cvWorkoutActiveV40')===true;
}

function resolveCurrent(cards){
  const explicit=cards.find(card=>card.classList.contains('cvExerciseCurrent'));
  if(explicit)return explicit;
  return cards.find(card=>!card.classList.contains('cvExerciseComplete'))||cards[0]||null;
}

function cardKey(card,index){
  return `${index}:${card?.getAttribute('data-tech-name')||card?.querySelector('.exerciseTop h3')?.textContent?.trim()||''}`;
}

function upgradeCard(card,index,currentCard){
  if(!(card instanceof HTMLElement))return;
  card.classList.add(CARD_CLASS);
  card.dataset.cvV102Index=String(index+1);

  const active=isWorkoutActive();
  const expanded=active&&card===currentCard;
  card.classList.toggle(EXPANDED_CLASS,expanded);
  card.classList.toggle(COLLAPSED_CLASS,active&&!expanded);
  card.setAttribute('aria-expanded',expanded?'true':'false');

  const top=card.querySelector('.exerciseTop');
  const title=top?.querySelector('h3');
  const legacyMain=card.querySelector('.exerciseMain');

  if(active){
    card.querySelectorAll('.cvExecutionBtnV35').forEach(button=>button.remove());
    if(title){
      title.removeAttribute('title');
      title.removeAttribute('onclick');
      title.onclick=null;
      title.setAttribute('aria-label',title.textContent?.trim()||`Ejercicio ${index+1}`);
    }
  }

  if(expanded&&top){
    const media=ensureMedia(card,title);
    if(media.parentElement!==card||media.previousElementSibling!==top){
      top.insertAdjacentElement('afterend',media);
    }
    media.dataset.cvV102Media='1';
    bindImageState(media,title?.textContent?.trim());
  }

  if(legacyMain){
    legacyMain.classList.add(LEGACY_MAIN_CLASS);
    legacyMain.setAttribute('aria-hidden',active?'true':'false');
  }
}

function maybeAdvance(cards,currentCard){
  if(!isWorkoutActive()||!currentCard)return;
  const index=cards.indexOf(currentCard);
  const key=cardKey(currentCard,index);
  if(!hasAppliedActiveState){
    hasAppliedActiveState=true;
    lastCurrentKey=key;
    return;
  }
  if(lastCurrentKey&&lastCurrentKey!==key){
    const behavior=window.matchMedia?.('(prefers-reduced-motion: reduce)')?.matches?'auto':'smooth';
    setTimeout(()=>currentCard.scrollIntoView({behavior,block:'start'}),90);
  }
  lastCurrentKey=key;
}

function clearFocusState(cards){
  cards.forEach(card=>{
    card.classList.remove(EXPANDED_CLASS,COLLAPSED_CLASS);
    card.removeAttribute('aria-expanded');
  });
  hasAppliedActiveState=false;
  lastCurrentKey=null;
}

function apply(){
  scheduled=false;
  if(!document.body?.classList.contains(BODY_CLASS))return;
  if(!document.body.classList.contains('cvFastWorkout'))return;
  const cards=[...document.querySelectorAll('.cvHevyExercise,.workoutExercise')];
  if(!cards.length)return;
  if(!isWorkoutActive()){
    clearFocusState(cards);
    return;
  }
  const currentCard=resolveCurrent(cards);
  cards.forEach((card,index)=>upgradeCard(card,index,currentCard));
  maybeAdvance(cards,currentCard);
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
    observer.observe(document.body,{childList:true,subtree:true,attributes:true,attributeFilter:['class']});
  }
}

function disable(){
  document.documentElement.classList.remove(ROOT_CLASS);
  document.body?.classList.remove(BODY_CLASS);
  observer?.disconnect();observer=null;
  const cards=[...document.querySelectorAll(`.${CARD_CLASS}`)];
  clearFocusState(cards);
}

const enabled=resolveExperiment();
if(enabled)enable();

window.CVExerciseScreenV102={
  version:'102.1',
  contract_revision:CONTRACT_REVISION,
  ready:true,
  enabled,
  enableExperiment(){localStorage.setItem(STORAGE_KEY,'1');location.reload()},
  disableExperiment(){localStorage.removeItem(STORAGE_KEY);location.reload()},
  refresh:schedule
};
console.info(CV_EXERCISE_SCREEN_V102_READY,CONTRACT_REVISION,enabled?'ENABLED':'DISABLED');
})();
