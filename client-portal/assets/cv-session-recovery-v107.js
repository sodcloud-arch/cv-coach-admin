(()=>{
  'use strict';

  const VERSION='107';
  const READY='CV_SESSION_RECOVERY_V107_READY';
  const STORAGE_KEY='cv_workout_recovery_v107';
  const TTL_MS=12*60*60*1000;
  const PROMPT_ID='cvSessionRecoveryV107';
  let persistTimer=null;
  let restoring=false;
  let promptedSavedAt=null;
  let observer=null;

  function safeContext(){
    try{
      const bridged=window.CVWorkoutContextV107?.();
      if(bridged){
        return {
          mode:bridged.mode||'real',
          workout:bridged.workout||null,
          user:bridged.user||null
        };
      }
    }catch(_){}
    const fallbackMode=document.querySelector('#modeBadge .demoBadge,.demoBadge')?'demo':'real';
    return {mode:fallbackMode,workout:null,user:null};
  }

  function visible(el){
    if(!el)return false;
    const r=el.getBoundingClientRect(),s=getComputedStyle(el);
    return r.width>0&&r.height>0&&s.display!=='none'&&s.visibility!=='hidden';
  }

  function appVisible(){
    const app=document.getElementById('app');
    return !!app&&!app.classList.contains('hidden')&&visible(app);
  }

  function active(){
    const {workout}=safeContext();
    return !!workout?.sessionId&&document.body.classList.contains('cvWorkoutActiveV40');
  }

  function setState(){
    const rows=[...document.querySelectorAll('.cvSetRow')];
    const total=rows.length;
    const done=rows.filter(row=>row.classList.contains('done')).length;
    return {total,done,pending:Math.max(0,total-done),pct:total?Math.round(done/total*100):0};
  }

  function demoExercises(){
    if(typeof window.cvExercises!=='function')return null;
    try{
      const source=window.cvExercises()||[];
      return source.map(ex=>({
        session_exercise_id:ex.session_exercise_id??null,
        program_exercise_id:ex.program_exercise_id??null,
        exercise_id:ex.exercise_id??null,
        name:String(ex.name||''),
        order:Number(ex.order)||0,
        instructions:ex.instructions??null,
        image_path:ex.image_path??null,
        target_sets:Number(ex.target_sets)||0,
        rep_min:ex.rep_min??null,
        rep_max:ex.rep_max??null,
        prescription_unit:ex.prescription_unit||'reps',
        rir_target:ex.rir_target??null,
        tempo:ex.tempo??null,
        rest_seconds:Number(ex.rest_seconds)||0,
        sets:(ex.sets||[]).map(s=>({
          set_log_id:s.set_log_id??null,
          set_number:Number(s.set_number)||0,
          suggested_weight_kg:s.suggested_weight_kg??null,
          suggested_reps:s.suggested_reps??null,
          suggested_duration_seconds:s.suggested_duration_seconds??null,
          previous_weight_kg:s.previous_weight_kg??null,
          previous_reps:s.previous_reps??null,
          previous_duration_seconds:s.previous_duration_seconds??null,
          reference_weight_kg:s.reference_weight_kg??null,
          reference_reps:s.reference_reps??null,
          reference_duration_seconds:s.reference_duration_seconds??null,
          weight_kg:s.weight_kg??null,
          reps:s.reps??null,
          duration_seconds:s.duration_seconds??null,
          rir:s.rir??null,
          completed:!!s.completed,
          suggestion_source:s.suggestion_source??null
        }))
      }));
    }catch(error){
      console.warn('CV V107 demo snapshot failed',error);
      return null;
    }
  }

  function read(){
    try{
      const raw=localStorage.getItem(STORAGE_KEY);
      if(!raw)return null;
      const parsed=JSON.parse(raw);
      if(!parsed||parsed.version!==VERSION||!parsed.savedAt||Date.now()-parsed.savedAt>TTL_MS){
        localStorage.removeItem(STORAGE_KEY);
        return null;
      }
      return parsed;
    }catch(_){
      try{localStorage.removeItem(STORAGE_KEY)}catch(__){}
      return null;
    }
  }

  function clear(){
    clearTimeout(persistTimer);
    persistTimer=null;
    try{localStorage.removeItem(STORAGE_KEY)}catch(_){}
    promptedSavedAt=null;
  }

  function persistNow(){
    if(restoring)return null;
    const ctx=safeContext();
    if(!active()||!ctx.workout?.dayId)return null;
    const progress=setState();
    if(!progress.total||progress.pending<=0)return null;
    const payload={
      version:VERSION,
      savedAt:Date.now(),
      mode:ctx.mode==='demo'?'demo':'real',
      userId:ctx.mode==='demo'?null:(ctx.user?.id||null),
      dayId:String(ctx.workout.dayId),
      started:Number(ctx.workout.started)||Date.now(),
      done:progress.done,
      total:progress.total,
      pct:progress.pct,
      demoExercises:ctx.mode==='demo'?demoExercises():null
    };
    try{
      localStorage.setItem(STORAGE_KEY,JSON.stringify(payload));
      return payload;
    }catch(error){
      console.warn('CV V107 recovery checkpoint failed',error);
      return null;
    }
  }

  function schedulePersist(delay=120){
    if(persistTimer)return;
    persistTimer=setTimeout(()=>{
      persistTimer=null;
      persistNow();
    },delay);
  }

  function elapsedLabel(savedAt){
    const minutes=Math.max(0,Math.round((Date.now()-Number(savedAt||Date.now()))/60000));
    if(minutes<1)return 'guardada hace menos de 1 min';
    if(minutes===1)return 'guardada hace 1 min';
    if(minutes<60)return `guardada hace ${minutes} min`;
    const hours=Math.round(minutes/60);
    return `guardada hace ${hours} h`;
  }

  function injectStyle(){
    if(document.getElementById('cvSessionRecoveryV107Style'))return;
    const style=document.createElement('style');
    style.id='cvSessionRecoveryV107Style';
    style.textContent=`
      .cvSessionRecoveryV107Backdrop{
        position:fixed;inset:0;z-index:410;display:flex;align-items:flex-end;justify-content:center;
        padding:14px;background:rgba(0,0,0,.88);backdrop-filter:blur(12px);
      }
      .cvSessionRecoveryV107Card{
        width:min(560px,100%);padding:18px;border:1px solid #30414a;border-radius:20px;
        background:linear-gradient(155deg,#0d151a,#070b0f);box-shadow:0 28px 90px rgba(0,0,0,.72);
      }
      .cvSessionRecoveryV107Ey{color:#69cfff;font-size:8px;font-weight:900;letter-spacing:.15em}
      .cvSessionRecoveryV107Card h2{margin:5px 0 7px;font-size:30px;line-height:1.01}
      .cvSessionRecoveryV107Sub{color:#aab6bc;font-size:11px;line-height:1.45}
      .cvSessionRecoveryV107Status{
        margin-top:15px;padding:13px;border:1px solid #293840;border-radius:14px;background:#060b0f;
      }
      .cvSessionRecoveryV107Top{display:flex;align-items:end;justify-content:space-between;gap:12px}
      .cvSessionRecoveryV107Top b{font:900 25px/1 'Barlow Condensed',Inter,sans-serif;color:#fff}
      .cvSessionRecoveryV107Top span{color:#8d9ba2;font-size:9px;font-weight:800;text-align:right}
      .cvSessionRecoveryV107Track{height:6px;margin-top:9px;overflow:hidden;border-radius:999px;background:#182128}
      .cvSessionRecoveryV107Fill{height:100%;border-radius:inherit;background:linear-gradient(90deg,#2ba8f3,#50cbd3,#5ee3a5)}
      .cvSessionRecoveryV107Note{
        margin-top:11px;padding:10px 11px;border:1px solid rgba(105,207,255,.22);border-radius:11px;
        background:rgba(105,207,255,.055);color:#bec9ce;font-size:9.5px;line-height:1.45;
      }
      .cvSessionRecoveryV107Actions{display:grid;grid-template-columns:1fr;gap:8px;margin-top:14px}
      .cvSessionRecoveryV107Actions button{min-height:48px;border-radius:12px;font-weight:900}
      #cvSessionRecoveryResumeV107{
        border:1px solid #54c7ff;background:linear-gradient(180deg,#35b9f7,#168fda);color:#fff;
      }
      #cvSessionRecoveryDismissV107{
        border:1px solid #37434a;background:#091015;color:#cbd4d8;
      }
      .cvSessionRecoveredV107{
        position:fixed;z-index:405;left:50%;top:calc(78px + env(safe-area-inset-top));transform:translateX(-50%);
        width:min(480px,calc(100% - 24px));padding:9px 12px;border:1px solid rgba(82,227,161,.34);
        border-radius:12px;background:rgba(7,24,16,.96);color:#89efb9;text-align:center;
        font-size:8.5px;font-weight:900;letter-spacing:.055em;box-shadow:0 15px 38px rgba(0,0,0,.45);
      }
      @media(min-width:700px){
        .cvSessionRecoveryV107Backdrop{align-items:center}
        .cvSessionRecoveryV107Actions{grid-template-columns:1.3fr 1fr}
      }
    `;
    document.head.appendChild(style);
  }

  function closePrompt(){
    document.getElementById(PROMPT_ID)?.remove();
  }

  function recoveredToast(snapshot){
    document.querySelector('.cvSessionRecoveredV107')?.remove();
    const el=document.createElement('div');
    el.className='cvSessionRecoveredV107';
    el.textContent=`SESIÓN RECUPERADA · ${snapshot.done}/${snapshot.total} SERIES CONSERVADAS`;
    document.body.appendChild(el);
    setTimeout(()=>el.remove(),3200);
  }

  async function restore(snapshot){
    if(restoring)return;
    restoring=true;
    closePrompt();
    try{
      if(typeof window.openDay!=='function'||typeof window.startWorkout!=='function')throw new Error('workout runtime unavailable');
      await window.openDay(snapshot.dayId);
      await window.startWorkout();

      const ctx=safeContext();
      if(snapshot.mode==='demo'){
        if(!ctx.workout)throw new Error('demo workout state unavailable');
        if(Array.isArray(snapshot.demoExercises)&&snapshot.demoExercises.length){
          ctx.workout.liveExercises=JSON.parse(JSON.stringify(snapshot.demoExercises));
        }
        ctx.workout.sessionId='demo';
        ctx.workout.started=Number(snapshot.started)||Date.now();
        try{if(typeof render==='function')render()}catch(_){try{window.render?.()}catch(__){}}
        try{if(typeof startTimer==='function')startTimer()}catch(_){}
      }

      await new Promise(resolve=>setTimeout(resolve,80));
      const state=setState();
      if(snapshot.done>0&&state.done<snapshot.done&&snapshot.mode==='demo')throw new Error('demo recovery state mismatch');
      recoveredToast(snapshot);
      promptedSavedAt=null;
      schedulePersist(40);
    }catch(error){
      console.error('CV V107 recovery failed',error);
      clear();
      const message=document.createElement('div');
      message.className='cvSessionRecoveredV107';
      message.style.borderColor='rgba(255,87,105,.45)';
      message.style.background='rgba(42,8,13,.96)';
      message.style.color='#ff9ba7';
      message.textContent='NO PUDIMOS RECUPERAR ESTA SESIÓN · ABRE TU RUTINA PARA CONTINUAR';
      document.body.appendChild(message);
      setTimeout(()=>message.remove(),4200);
    }finally{
      restoring=false;
    }
  }

  function dismiss(snapshot){
    closePrompt();
    if(snapshot.mode==='demo')clear();
    else promptedSavedAt=snapshot.savedAt;
  }

  function showPrompt(snapshot){
    if(document.getElementById(PROMPT_ID)||!appVisible())return;
    if(promptedSavedAt===snapshot.savedAt)return;
    const ctx=safeContext();
    if(snapshot.mode==='demo'&&ctx.mode!=='demo')return;
    if(snapshot.mode==='real'){
      if(ctx.mode==='demo')return;
      if(snapshot.userId&&ctx.user?.id&&snapshot.userId!==ctx.user.id){
        clear();
        return;
      }
      if(snapshot.userId&&!ctx.user?.id)return;
    }

    promptedSavedAt=snapshot.savedAt;
    injectStyle();
    const overlay=document.createElement('div');
    overlay.id=PROMPT_ID;
    overlay.className='cvSessionRecoveryV107Backdrop';
    const secondary=snapshot.mode==='demo'?'DESCARTAR BORRADOR':'AHORA NO';
    const note=snapshot.mode==='demo'
      ?'DEMO guardó estas series solo en este dispositivo. No se enviaron datos a Supabase.'
      :'Tus series reales siguen protegidas en Supabase. Este aviso solo te devuelve al entrenamiento activo.';
    overlay.innerHTML=`
      <section class="cvSessionRecoveryV107Card" role="dialog" aria-modal="true" aria-labelledby="cvSessionRecoveryTitleV107">
        <div class="cvSessionRecoveryV107Ey">SESIÓN INTERRUMPIDA</div>
        <h2 id="cvSessionRecoveryTitleV107">Tu entrenamiento sigue disponible</h2>
        <div class="cvSessionRecoveryV107Sub">Detectamos una sesión que no alcanzaste a cerrar.</div>
        <div class="cvSessionRecoveryV107Status">
          <div class="cvSessionRecoveryV107Top">
            <b>${snapshot.done} / ${snapshot.total} SERIES</b>
            <span>${snapshot.pct}% · ${elapsedLabel(snapshot.savedAt)}</span>
          </div>
          <div class="cvSessionRecoveryV107Track"><div class="cvSessionRecoveryV107Fill" style="width:${snapshot.pct}%"></div></div>
        </div>
        <div class="cvSessionRecoveryV107Note">${note}</div>
        <div class="cvSessionRecoveryV107Actions">
          <button id="cvSessionRecoveryResumeV107" type="button">REANUDAR SESIÓN</button>
          <button id="cvSessionRecoveryDismissV107" type="button">${secondary}</button>
        </div>
      </section>`;
    document.body.appendChild(overlay);
    overlay.querySelector('#cvSessionRecoveryResumeV107').onclick=()=>restore(snapshot);
    overlay.querySelector('#cvSessionRecoveryDismissV107').onclick=()=>dismiss(snapshot);
    requestAnimationFrame(()=>overlay.querySelector('#cvSessionRecoveryResumeV107')?.focus());
  }

  function maybePrompt(){
    if(restoring||active()||!appVisible())return;
    const snapshot=read();
    if(snapshot)showPrompt(snapshot);
  }

  function onFinishObserved(){
    const result=document.getElementById('cvWorkoutResultModal');
    if(result&&visible(result)&&!document.body.classList.contains('cvWorkoutActiveV40'))clear();
  }

  document.addEventListener('input',event=>{
    if(event.target?.matches?.('.cvSetRow input'))schedulePersist(80);
  },true);

  document.addEventListener('click',event=>{
    if(event.target?.closest?.('.cvSetCheck'))setTimeout(()=>schedulePersist(20),220);
  },true);

  window.addEventListener('pagehide',()=>{if(active())persistNow()});

  window.addEventListener('beforeunload',event=>{
    if(!active())return;
    const progress=setState();
    if(!progress.total||progress.pending<=0)return;
    persistNow();
    event.preventDefault();
    event.returnValue='';
  });

  function boot(){
    injectStyle();
    schedulePersist(250);
    setTimeout(maybePrompt,350);
    if(!observer){
      observer=new MutationObserver(()=>{
        if(active())schedulePersist(140);
        else setTimeout(maybePrompt,80);
        onFinishObserved();
      });
      observer.observe(document.body,{childList:true,subtree:true,attributes:true,attributeFilter:['class']});
    }
  }

  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});
  else boot();

  window.CVSessionRecoveryV107={
    version:VERSION,
    ready:true,
    marker:READY,
    storageKey:STORAGE_KEY,
    ttlMs:TTL_MS,
    read,
    clear,
    persist:persistNow,
    prompt:maybePrompt,
    restore
  };
  document.documentElement.setAttribute('data-cv-session-recovery','107');
  console.info(READY,VERSION);
})();