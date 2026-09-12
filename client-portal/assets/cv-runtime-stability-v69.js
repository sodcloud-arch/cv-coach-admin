(function(){
  if(window.CVRuntimeStabilityV69)return;
  const RANK_IMPACT_MS=2480;
  const RANK_FINAL_MS=3900;
  const RANK_FAILSAFE_MS=5200;
  const START_TIMEOUT_MS=11000;
  let startBusy=false;
  let installedStart=null;

  function addBackdrop(node){
    if(!node||node.querySelector('.cv69Backdrop'))return;
    const bg=document.createElement('div');bg.className='cv69Backdrop';bg.setAttribute('aria-hidden','true');
    const core=document.createElement('i');core.className='cv69EnergyCore';
    const sparks=document.createElement('i');sparks.className='cv69SparkField';
    bg.append(core,sparks);node.insertBefore(bg,node.firstChild)
  }
  function forceRankFinal(node){
    if(!node||!node.isConnected)return;
    node.classList.add('cv66Impact','cv69Final');
    const btn=node.querySelector('.cv66Continue');
    if(btn){btn.disabled=false;btn.style.pointerEvents='auto';btn.removeAttribute('aria-disabled')}
  }
  function armCelebration(node){
    if(!(node instanceof Element)||!node.classList.contains('cv66Ascend')||node.dataset.cv69Managed==='1')return;
    node.dataset.cv69Managed='1';node.classList.add('cv69Managed');addBackdrop(node);
    const rankUp=node.classList.contains('rank_up');
    if(rankUp){
      /* Visual clock is authoritative. Audio may accompany it, but cannot block it. */
      node.classList.add('cv66AudioPlaying');
      setTimeout(()=>{if(node.isConnected)node.classList.add('cv66Impact')},RANK_IMPACT_MS)
    }
    setTimeout(()=>forceRankFinal(node),RANK_FINAL_MS);
    setTimeout(()=>forceRankFinal(node),RANK_FAILSAFE_MS)
  }
  function scanCelebrations(root=document){
    if(root instanceof Element&&root.matches?.('.cv66Ascend'))armCelebration(root);
    root.querySelectorAll?.('.cv66Ascend').forEach(armCelebration)
  }
  const celebrationObserver=new MutationObserver(records=>{
    for(const rec of records)for(const n of rec.addedNodes)if(n instanceof Element)scanCelebrations(n)
  });
  celebrationObserver.observe(document.documentElement,{childList:true,subtree:true});
  scanCelebrations();

  function startButtons(){
    return Array.from(document.querySelectorAll('.cvWorkoutStartV40,.workoutTop button')).filter(b=>/INICIAR/i.test(String(b.textContent||''))||b.classList.contains('cvWorkoutStartV40'))
  }
  function setStartUi(active){
    for(const btn of startButtons()){
      if(active){
        if(!btn.dataset.cv69Label)btn.dataset.cv69Label=btn.textContent||'INICIAR ENTRENAMIENTO';
        btn.textContent='INICIANDO';btn.disabled=true;btn.classList.add('cv69Starting');btn.setAttribute('aria-busy','true')
      }else{
        btn.classList.remove('cv69Starting');btn.removeAttribute('aria-busy');btn.disabled=false;
        if(btn.dataset.cv69Label){btn.textContent=btn.dataset.cv69Label;delete btn.dataset.cv69Label}
      }
    }
  }
  function delayReject(ms,message){return new Promise((_,reject)=>setTimeout(()=>reject(new Error(message)),ms))}
  function bounded(p,ms,message){return Promise.race([Promise.resolve(p),delayReject(ms,message)])}
  async function recoverActiveWorkout(){
    try{
      if(typeof mode!=='undefined'&&mode==='demo')return false;
      if(typeof sb==='undefined'||typeof user==='undefined'||!user?.id||typeof workout==='undefined'||!workout?.dayId)return false;
      const q=await bounded(
        sb.from('workout_sessions').select('id,started_at,status').eq('client_id',user.id).eq('program_day_id',workout.dayId).eq('status','in_progress').order('started_at',{ascending:false}).limit(1).maybeSingle(),
        3800,
        'No pude verificar la sesión activa.'
      );
      if(q?.error||!q?.data?.id)return false;
      workout.sessionId=q.data.id;
      workout.started=q.data.started_at?new Date(q.data.started_at).getTime():Date.now();
      workout.cvResumed=true;
      try{
        const r=await bounded(sb.functions.invoke('start-workout',{body:{program_day_id:workout.dayId}}),4500,'resume timeout');
        if(!r?.error&&!r?.data?.error&&Array.isArray(r?.data?.exercises))workout.liveExercises=r.data.exercises
      }catch(_){}
      try{if(!workout.liveExercises&&typeof cvPrestartExercises==='function')workout.liveExercises=cvPrestartExercises()}catch(_){}
      try{if(typeof render==='function')render()}catch(_){}
      try{if(typeof startTimer==='function')startTimer()}catch(_){}
      try{if(typeof hydrateHistory==='function')Promise.resolve(hydrateHistory()).catch(()=>{})}catch(_){}
      try{toast?.('Sesión recuperada · continuamos donde quedaste')}catch(_){}
      return true
    }catch(err){console.warn('CV V69 workout recovery',err);return false}
  }
  function installStartGuard(){
    const current=window.startWorkout;
    if(typeof current!=='function'||current.__cv69Guard)return;
    const guarded=async function(){
      if(startBusy)return false;
      try{if(typeof workout!=='undefined'&&workout?.sessionId)return current.apply(this,arguments)}catch(_){}
      startBusy=true;setStartUi(true);
      try{
        const result=await bounded(current.apply(this,arguments),START_TIMEOUT_MS,'El inicio del entrenamiento no respondió a tiempo.');
        try{if(typeof workout!=='undefined'&&workout?.sessionId)return result}catch(_){}
        if(await recoverActiveWorkout())return true;
        return result
      }catch(err){
        if(await recoverActiveWorkout())return true;
        const msg=String(err?.message||'No pude iniciar el entrenamiento.');
        try{toast?.(msg.includes('tiempo')?'El inicio tardó demasiado. Revisa tu conexión e inténtalo otra vez.':msg)}catch(_){}
        return false
      }finally{
        startBusy=false;
        let started=false;try{started=!!workout?.sessionId}catch(_){}
        if(!started)setStartUi(false)
      }
    };
    guarded.__cv69Guard=true;guarded.__cv69Base=current;
    window.startWorkout=guarded;installedStart=guarded
  }
  installStartGuard();
  setTimeout(installStartGuard,250);
  setTimeout(installStartGuard,1200);
  document.addEventListener('cv:rendered',()=>{if(window.startWorkout!==installedStart&&!window.startWorkout?.__cv69Guard)installStartGuard()});

  window.CVRuntimeStabilityV69={version:'v69',armCelebration,forceRankFinal,installStartGuard,recoverActiveWorkout,rankImpactMs:RANK_IMPACT_MS,rankFinalMs:RANK_FINAL_MS,startTimeoutMs:START_TIMEOUT_MS};
})();
