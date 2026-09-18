(()=>{
  'use strict';

  const VERSION='105';
  const READY='CV_GUIDED_SET_LOGGING_V105_READY';
  const STYLE_ID='cv-guided-set-logging-v105-style';
  const ROW_SELECTOR='.cvSetRow';
  const INPUT_SELECTOR='input[id^="cvw_"],input[id^="cvr_"]';
  let scheduled=false;
  let observer=null;

  function isVisible(el){
    if(!(el instanceof Element))return false;
    const r=el.getBoundingClientRect();
    return r.width>0&&r.height>0&&getComputedStyle(el).visibility!=='hidden';
  }

  function isSetInput(el){
    return el instanceof HTMLInputElement&&/^cv[wr]_\d+_\d+$/.test(el.id||'');
  }

  function parseInput(el){
    const match=/^cv([wr])_(\d+)_(\d+)$/.exec(el?.id||'');
    return match?{kind:match[1]==='w'?'weight':'reps',exercise:Number(match[2]),set:Number(match[3])}:null;
  }

  function rowInputs(row){
    return {
      weight:row?.querySelector('input[id^="cvw_"]')||null,
      reps:row?.querySelector('input[id^="cvr_"]')||null,
      check:row?.querySelector('.cvSetCheck')||null
    };
  }

  function seriesLabel(row,index){
    const raw=row?.querySelector('.cvSetNo')?.textContent?.trim();
    return raw||String(index+1);
  }

  function injectStyle(){
    if(document.getElementById(STYLE_ID))return;
    const style=document.createElement('style');
    style.id=STYLE_ID;
    style.textContent=`
      body.cvFastWorkout.cvGuidedSetLoggingV105 .cvSetRow{
        position:relative;
        border-left:2px solid transparent;
        transition:background .16s ease,border-color .16s ease,box-shadow .16s ease,opacity .16s ease;
      }
      body.cvFastWorkout.cvGuidedSetLoggingV105 .cvSetRow.cvV105Next:not(.done){
        border-left-color:#ff334b!important;
        background:linear-gradient(90deg,rgba(255,51,75,.085),rgba(255,51,75,.018) 46%,transparent)!important;
        box-shadow:inset 12px 0 24px rgba(255,32,55,.025);
      }
      body.cvFastWorkout.cvGuidedSetLoggingV105 .cvSetRow.cvV105Active{
        border-left-color:#ff5a6e!important;
        background:linear-gradient(90deg,rgba(255,55,80,.13),rgba(255,55,80,.025) 55%,transparent)!important;
      }
      body.cvFastWorkout.cvGuidedSetLoggingV105 .cvSetRow.done{
        border-left-color:rgba(84,229,156,.52)!important;
      }
      body.cvFastWorkout.cvGuidedSetLoggingV105 .cvSetRow.done input{
        color:#ccefdc!important;
      }
      body.cvFastWorkout.cvGuidedSetLoggingV105 .cvSetRow input[data-cv-v105="1"]{
        min-height:42px!important;
        font-size:20px!important;
        font-weight:900!important;
        letter-spacing:-.015em!important;
        caret-color:#ff4057;
      }
      body.cvFastWorkout.cvGuidedSetLoggingV105 .cvSetRow input[data-cv-v105="1"]:focus{
        border-color:#ff4057!important;
        background:#0d1115!important;
        box-shadow:0 0 0 2px rgba(255,64,87,.14),0 8px 22px rgba(0,0,0,.18)!important;
      }
      body.cvFastWorkout.cvGuidedSetLoggingV105 .cvSetCheck{
        min-width:42px!important;
        min-height:42px!important;
      }
      body.cvFastWorkout.cvGuidedSetLoggingV105 .cvSetRow.cvV105Next:not(.done) .cvSetNo{
        border-color:rgba(255,64,87,.58)!important;
        color:#fff!important;
        box-shadow:0 0 0 2px rgba(255,64,87,.08),0 0 16px rgba(255,32,55,.08);
      }
      body.cvFastWorkout.cvGuidedSetLoggingV105 .cvV105LoggingHint{
        margin:1px 3px 6px;
        color:#6f7d84;
        font-size:8.5px;
        font-weight:700;
        line-height:1.35;
        text-align:right;
      }
      @media(max-width:390px){
        body.cvFastWorkout.cvGuidedSetLoggingV105 .cvSetRow input[data-cv-v105="1"]{font-size:19px!important}
        body.cvFastWorkout.cvGuidedSetLoggingV105 .cvV105LoggingHint{font-size:8px}
      }
    `;
    document.head.appendChild(style);
  }

  function decorateExercise(card){
    const rows=[...card.querySelectorAll(ROW_SELECTOR)].filter(isVisible);
    if(!rows.length)return;

    const current=rows.find(row=>!row.classList.contains('done'))||null;
    rows.forEach((row,index)=>{
      row.classList.toggle('cvV105Next',row===current);
      row.dataset.cvV105='1';

      const label=seriesLabel(row,index);
      const {weight,reps,check}=rowInputs(row);
      if(weight){
        weight.dataset.cvV105='1';
        weight.setAttribute('aria-label',`Peso de la serie ${label} en kilogramos`);
      }
      if(reps){
        reps.dataset.cvV105='1';
        reps.setAttribute('aria-label',`Repeticiones o tiempo de la serie ${label}`);
      }
      if(check){
        check.setAttribute('aria-label',row.classList.contains('done')?`Serie ${label} completada`:`Completar serie ${label}`);
      }
    });

    const head=card.querySelector('.cvSetsHead');
    if(head&&!card.querySelector('.cvV105LoggingHint')){
      const hint=document.createElement('div');
      hint.className='cvV105LoggingHint';
      hint.textContent='Toca un valor para editar · “Siguiente” avanza de campo';
      head.insertAdjacentElement('afterend',hint);
    }
  }

  function apply(){
    scheduled=false;
    injectStyle();
    document.body?.classList.add('cvGuidedSetLoggingV105');
    document.documentElement?.setAttribute('data-cv-guided-set-logging','105');
    document.querySelectorAll('.cvHevyExercise,.workoutExercise').forEach(decorateExercise);
  }

  function schedule(){
    if(scheduled)return;
    scheduled=true;
    requestAnimationFrame(apply);
  }

  function moveForward(el,event){
    if(event.key!=='Enter'||!isSetInput(el))return;
    const meta=parseInput(el);
    if(!meta)return;
    const row=el.closest(ROW_SELECTOR);
    const {weight,reps,check}=rowInputs(row);
    if(meta.kind==='weight'&&reps&&!reps.disabled){
      event.preventDefault();
      reps.focus();
      try{reps.select()}catch(_){}
      return;
    }
    if(meta.kind==='reps'&&check&&!check.disabled){
      event.preventDefault();
      el.blur();
      check.focus({preventScroll:true});
    }
  }

  document.addEventListener('focusin',event=>{
    const el=event.target;
    if(!isSetInput(el))return;
    document.querySelectorAll(`${ROW_SELECTOR}.cvV105Active`).forEach(row=>row.classList.remove('cvV105Active'));
    el.closest(ROW_SELECTOR)?.classList.add('cvV105Active');
  },true);

  document.addEventListener('focusout',event=>{
    const row=event.target?.closest?.(ROW_SELECTOR);
    if(!row)return;
    requestAnimationFrame(()=>{
      if(!row.contains(document.activeElement))row.classList.remove('cvV105Active');
    });
  },true);

  document.addEventListener('keydown',event=>moveForward(event.target,event),true);

  document.addEventListener('click',event=>{
    if(event.target?.closest?.('.cvSetCheck')){
      setTimeout(schedule,0);
      setTimeout(schedule,180);
    }
  },true);

  function enable(){
    injectStyle();
    schedule();
    if(!observer){
      observer=new MutationObserver(schedule);
      observer.observe(document.body,{childList:true,subtree:true,attributes:true,attributeFilter:['class']});
    }
  }

  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',enable,{once:true});
  else enable();

  window.CVGuidedSetLoggingV105={version:VERSION,ready:true,refresh:schedule,marker:READY};
  console.info(READY,VERSION);
})();