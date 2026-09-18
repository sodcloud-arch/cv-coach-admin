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
      body.cvFastWorkout.cvGuidedSetLoggingV105 .cvV105ExerciseOpen>.exerciseMedia,
      body.cvFastWorkout.cvGuidedSetLoggingV105.cvExerciseScreenV102.cvV102WorkoutReady .cvV105ExerciseOpen.cvV102Expanded>.exerciseMedia{
        display:grid!important;
        place-items:center!important;
        width:100%!important;
        height:min(204px,54vw)!important;
        min-height:min(204px,54vw)!important;
        max-height:204px!important;
        margin:8px 0 9px!important;
        padding:0!important;
        overflow:hidden!important;
        border:1px solid #2a3740!important;
        border-radius:13px!important;
        background:#030608!important;
        box-shadow:inset 0 1px 0 rgba(255,255,255,.025),0 10px 26px rgba(0,0,0,.22)!important;
      }
      body.cvFastWorkout.cvGuidedSetLoggingV105 .cvV105ExerciseOpen>.exerciseMedia:after,
      body.cvFastWorkout.cvGuidedSetLoggingV105.cvExerciseScreenV102.cvV102WorkoutReady .cvV105ExerciseOpen.cvV102Expanded>.exerciseMedia:after{
        display:none!important;
        content:none!important;
      }
      body.cvFastWorkout.cvGuidedSetLoggingV105 .cvV105ExerciseOpen>.exerciseMedia .photo,
      body.cvFastWorkout.cvGuidedSetLoggingV105.cvExerciseScreenV102.cvV102WorkoutReady .cvV105ExerciseOpen.cvV102Expanded>.exerciseMedia .photo{
        display:block!important;
        width:100%!important;
        height:100%!important;
        max-height:none!important;
        min-height:0!important;
        aspect-ratio:auto!important;
        object-fit:contain!important;
        object-position:center!important;
        margin:0!important;
        border:0!important;
        border-radius:0!important;
        background:#030608!important;
      }
      body.cvFastWorkout.cvGuidedSetLoggingV105 .cvV105ExerciseOpen .cvExecutionBtnV35{
        display:none!important;
      }
      body.cvFastWorkout.cvGuidedSetLoggingV105 .cvHevyExercise:not(.cvV105ExerciseOpen) .cvDetailsTitleRowV103,
      body.cvFastWorkout.cvGuidedSetLoggingV105 .cvHevyExercise:not(.cvV105ExerciseOpen) .cvExerciseTitleRowV35{
        display:grid!important;
        grid-template-columns:minmax(0,1fr) auto!important;
        align-items:center!important;
        gap:8px!important;
        width:100%!important;
        margin:0 0 3px!important;
      }
      body.cvFastWorkout.cvGuidedSetLoggingV105 .cvHevyExercise:not(.cvV105ExerciseOpen) .cvDetailsLinkV103{
        justify-self:end!important;
        min-height:24px!important;
        padding:0 8px!important;
        display:inline-flex!important;
        align-items:center!important;
        border:1px solid rgba(105,207,255,.20)!important;
        border-radius:999px!important;
        background:rgba(105,207,255,.045)!important;
        text-decoration:none!important;
        font-size:7.5px!important;
      }
      body.cvFastWorkout.cvGuidedSetLoggingV105 .cvV105ExerciseOpen .exerciseTop{
        align-items:flex-start!important;
        gap:10px!important;
        margin-bottom:0!important;
      }
      body.cvFastWorkout.cvGuidedSetLoggingV105 .cvV105ExerciseOpen .exerciseTop .grow{
        min-width:0!important;
        width:100%!important;
      }
      body.cvFastWorkout.cvGuidedSetLoggingV105 .cvV105ExerciseOpen .cvDetailsTitleRowV103,
      body.cvFastWorkout.cvGuidedSetLoggingV105 .cvV105ExerciseOpen .cvExerciseTitleRowV35{
        display:grid!important;
        grid-template-columns:minmax(0,1fr)!important;
        align-items:start!important;
        gap:4px!important;
        margin:0 0 5px!important;
      }
      body.cvFastWorkout.cvGuidedSetLoggingV105 .cvV105ExerciseOpen .cvDetailsTitleRowV103>h3,
      body.cvFastWorkout.cvGuidedSetLoggingV105 .cvV105ExerciseOpen .cvExerciseTitleRowV35>h3{
        width:100%!important;
        margin:0!important;
        line-height:1.02!important;
      }
      body.cvFastWorkout.cvGuidedSetLoggingV105 .cvV105ExerciseOpen .cvDetailsLinkV103{
        justify-self:start!important;
        min-height:27px!important;
        padding:0 9px!important;
        margin:0!important;
        display:inline-flex!important;
        align-items:center!important;
        border:1px solid rgba(105,207,255,.26)!important;
        border-radius:999px!important;
        background:rgba(105,207,255,.055)!important;
        text-decoration:none!important;
        font-size:8.5px!important;
        letter-spacing:.055em!important;
      }
      body.cvFastWorkout.cvGuidedSetLoggingV105 .cvV105ExerciseOpen .cvPrescription{
        margin-top:1px!important;
        margin-bottom:0!important;
      }
      body.cvFastWorkout.cvGuidedSetLoggingV105 .cvV105ExerciseOpen>.cvRestText{
        margin-top:0!important;
        margin-bottom:7px!important;
      }
      body.cvFastWorkout.cvGuidedSetLoggingV105 .cvV105ExerciseOpen>.cvSetsHead{
        margin-top:7px!important;
        padding-bottom:4px!important;
      }
      body.cvFastWorkout.cvGuidedSetLoggingV105 .cvV105ExerciseOpen>.cvAddSet{
        margin-top:7px!important;
      }
      body.cvFastWorkout.cvGuidedSetLoggingV105 .cvV105MediaFallback{
        width:100%;
        height:100%;
        display:grid;
        place-items:center;
        text-align:center;
        padding:24px;
        color:#7f8c94;
        font-size:10px;
        font-weight:800;
        line-height:1.45;
        background:radial-gradient(circle at 50% 45%,#11191e,#040708 70%);
      }
      body.cvFastWorkout.cvGuidedSetLoggingV105 .cvV105MediaFallback b{
        display:block;
        margin-bottom:5px;
        color:#dce2e5;
        font:900 28px/1 'Barlow Condensed',sans-serif;
      }
      @media(max-width:767px){
        body.cvWorkoutPrestartV40.cvFastWorkout.cvGuidedSetLoggingV105 .cvWorkoutHeroV31{
          margin:0 0 7px!important;
          padding:12px 13px 12px!important;
          border-radius:15px!important;
        }
        body.cvWorkoutPrestartV40.cvFastWorkout.cvGuidedSetLoggingV105 .cvWorkoutHeroTop{
          min-height:0!important;
          gap:6px!important;
        }
        body.cvWorkoutPrestartV40.cvFastWorkout.cvGuidedSetLoggingV105 .cvWorkoutHeroEy{
          font-size:8px!important;
          letter-spacing:.14em!important;
        }
        body.cvWorkoutPrestartV40.cvFastWorkout.cvGuidedSetLoggingV105 .cvWorkoutLivePill{
          padding:4px 7px!important;
          font-size:7px!important;
          letter-spacing:.055em!important;
        }
        body.cvWorkoutPrestartV40.cvFastWorkout.cvGuidedSetLoggingV105 .cvWorkoutHeroV31 h1{
          margin:5px 0 3px!important;
          font-size:28px!important;
          line-height:.96!important;
        }
        body.cvWorkoutPrestartV40.cvFastWorkout.cvGuidedSetLoggingV105 .cvWorkoutHeroFocus{
          font-size:10.5px!important;
          line-height:1.3!important;
          display:-webkit-box!important;
          -webkit-line-clamp:2;
          -webkit-box-orient:vertical;
          overflow:hidden!important;
        }
        body.cvWorkoutPrestartV40.cvFastWorkout.cvGuidedSetLoggingV105 .cvWorkoutHeroChips{
          gap:5px!important;
          margin-top:9px!important;
        }
        body.cvWorkoutPrestartV40.cvFastWorkout.cvGuidedSetLoggingV105 .cvWorkoutHeroChip{
          min-height:24px!important;
          padding:0 8px!important;
          font-size:8px!important;
        }
        body.cvWorkoutPrestartV40.cvFastWorkout.cvGuidedSetLoggingV105 .cvWorkoutProgressTrack{
          height:5px!important;
          margin-top:10px!important;
        }
        body.cvWorkoutPrestartV40.cvFastWorkout.cvGuidedSetLoggingV105 .cvWorkoutProgressCopy{
          margin-top:5px!important;
          font-size:8px!important;
        }
        body.cvWorkoutPrestartV40.cvFastWorkout.cvGuidedSetLoggingV105 .cvWorkoutStartV40{
          min-height:44px!important;
          margin-top:10px!important;
          border-radius:11px!important;
          font-size:11px!important;
        }
      }
      @media(max-width:390px){
        body.cvFastWorkout.cvGuidedSetLoggingV105 .cvSetRow input[data-cv-v105="1"]{font-size:19px!important}
        body.cvFastWorkout.cvGuidedSetLoggingV105 .cvV105ExerciseOpen>.exerciseMedia,
        body.cvFastWorkout.cvGuidedSetLoggingV105.cvExerciseScreenV102.cvV102WorkoutReady .cvV105ExerciseOpen.cvV102Expanded>.exerciseMedia{
          height:min(188px,52vw)!important;
          min-height:min(188px,52vw)!important;
          max-height:188px!important;
        }
      }
    `;
    document.head.appendChild(style);
  }

  function ensureExerciseMedia(card){
    let media=card.querySelector('.exerciseMedia');
    const title=card.querySelector('.exerciseTop h3')?.textContent?.trim()||card.getAttribute('data-tech-name')||'Ejercicio';
    const src=String(card.getAttribute('data-tech-img')||'').trim();

    if(!media){
      media=document.createElement('div');
      media.className='exerciseMedia';
      const top=card.querySelector('.exerciseTop');
      if(top)top.insertAdjacentElement('afterend',media);
      else card.prepend(media);
    }

    let img=media.querySelector('.photo');
    if(!img&&src){
      img=document.createElement('img');
      img.className='photo';
      img.alt=title;
      img.loading='eager';
      img.decoding='async';
      img.src=src;
      media.replaceChildren(img);
    }else if(img){
      img.loading='eager';
      img.decoding='async';
      if(!img.getAttribute('src')&&src)img.src=src;
    }

    if(img&&img.dataset.cvV105Bound!=='1'){
      img.dataset.cvV105Bound='1';
      img.addEventListener('error',()=>{
        const fallback=document.createElement('div');
        fallback.className='cvV105MediaFallback';
        fallback.innerHTML='<div><b>CV</b>Lámina no disponible</div>';
        media.replaceChildren(fallback);
      },{once:true});
    }

    if(!img&&!media.querySelector('.cvV105MediaFallback')){
      const fallback=document.createElement('div');
      fallback.className='cvV105MediaFallback';
      fallback.innerHTML='<div><b>CV</b>Imagen técnica en preparación</div>';
      media.appendChild(fallback);
    }
    return media;
  }

  function decorateExercise(card){
    const rows=[...card.querySelectorAll(ROW_SELECTOR)].filter(isVisible);
    if(!rows.length)return;

    const current=rows.find(row=>!row.classList.contains('done'))||null;
    const exerciseName=card.querySelector('.exerciseTop h3')?.textContent?.trim()||card.getAttribute('data-tech-name')||'';
    rows.forEach((row,index)=>{
      row.classList.toggle('cvV105Next',row===current);
      row.dataset.cvV105='1';

      const label=seriesLabel(row,index);
      const {weight,reps,check}=rowInputs(row);
      if(weight){
        weight.dataset.cvV105='1';
        if(!weight.getAttribute('aria-label'))weight.setAttribute('aria-label',`Peso de la serie ${label} en kilogramos`);
      }
      if(reps){
        reps.dataset.cvV105='1';
        if(!reps.getAttribute('aria-label'))reps.setAttribute('aria-label',`Repeticiones o tiempo de la serie ${label}`);
      }
      if(check){
        const done=row.classList.contains('done')||check.classList.contains('done');
        check.setAttribute('aria-pressed',done?'true':'false');
        const suffix=exerciseName?` de ${exerciseName}`:'';
        if(done){
          check.setAttribute('aria-label',`Serie ${label} completada${suffix}`);
        }else{
          const existing=check.getAttribute('aria-label')||'';
          if(!existing||/completada/i.test(existing))check.setAttribute('aria-label',`Completar serie ${label}${suffix}`);
        }
      }
    });

    card.querySelectorAll('.cvV105LoggingHint').forEach(hint=>hint.remove());
  }

  function apply(){
    scheduled=false;
    injectStyle();
    document.body?.classList.add('cvGuidedSetLoggingV105');
    document.documentElement?.setAttribute('data-cv-guided-set-logging','105.4');

    const cards=[...document.querySelectorAll('.cvHevyExercise,.workoutExercise')].filter(isVisible);
    cards.forEach(decorateExercise);

    const currentCard=cards.find(card=>[...card.querySelectorAll(ROW_SELECTOR)].some(row=>isVisible(row)&&!row.classList.contains('done')))||cards[0]||null;
    cards.forEach(card=>card.classList.toggle('cvV105ExerciseOpen',card===currentCard));

    if(currentCard){
      ensureExerciseMedia(currentCard);
      currentCard.querySelectorAll('.cvExecutionBtnV35').forEach(button=>button.setAttribute('aria-hidden','true'));
    }
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

  window.CVGuidedSetLoggingV105={version:VERSION,revision:'105.4',ready:true,refresh:schedule,marker:READY};
  console.info(READY,VERSION);
})();