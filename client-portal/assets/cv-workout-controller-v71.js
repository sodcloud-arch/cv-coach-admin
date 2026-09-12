(function(){
  if(window.CVWorkoutControllerV71)return;
  const START_TIMEOUT_MS=12000;
  let activeStart=null;

  const sleepReject=(ms,message)=>new Promise((_,reject)=>setTimeout(()=>reject(new Error(message)),ms));
  const bounded=(p,ms,message)=>Promise.race([Promise.resolve(p),sleepReject(ms,message)]);
  const isWorkoutView=()=>{try{return view==='workout'&&!!workout?.dayId}catch(_){return false}};
  const isDemo=()=>{try{return mode==='demo'}catch(_){return false}};

  function snapshotInputs(){
    const out=new Map();
    document.querySelectorAll('input[id^="cvw_"],input[id^="cvr_"],input[id^="cvri_"]').forEach(inp=>{
      const m=inp.id.match(/^cv(w|r|ri)_(\d+)_(\d+)$/);if(!m)return;
      const key=`${m[2]}_${m[3]}`,row=out.get(key)||{};row[m[1]]=inp.value;out.set(key,row)
    });
    return out
  }
  function applySnapshot(exercises,snap){
    if(!Array.isArray(exercises))return;
    for(const [key,d] of snap.entries()){
      const [i,j]=key.split('_').map(Number),ex=exercises?.[i],s=ex?.sets?.[j];if(!s)continue;
      const unit=ex.prescription_unit||'reps';
      if(unit==='reps'&&d.w!==undefined&&d.w!=='')s.weight_kg=Number(d.w);
      if(d.r!==undefined&&d.r!==''){
        if(unit==='seconds'){s.duration_seconds=Math.round(Number(d.r));s.reps=null;s.weight_kg=null}
        else{s.reps=Math.round(Number(d.r));s.duration_seconds=null}
      }
      if(d.ri!==undefined&&d.ri!=='')s.rir=Number(d.ri)
    }
  }
  function setStartUI(active){
    document.querySelectorAll('.cvWorkoutStartV40,.workoutTop button').forEach(btn=>{
      if(!/INICIAR|INICIANDO/i.test(String(btn.textContent||''))&&!btn.classList.contains('cvWorkoutStartV40'))return;
      if(active){if(!btn.dataset.cv71Label)btn.dataset.cv71Label=btn.textContent||'INICIAR ENTRENAMIENTO';btn.textContent='INICIANDO…';btn.disabled=true;btn.setAttribute('aria-busy','true')}
      else{btn.disabled=false;btn.removeAttribute('aria-busy');if(btn.dataset.cv71Label){btn.textContent=btn.dataset.cv71Label;delete btn.dataset.cv71Label}}
    })
  }
  function finalizeVisual(){
    try{document.body.classList.toggle('cvWorkoutActiveV40',!!workout?.sessionId);document.body.classList.toggle('cvWorkoutPrestartV40',!workout?.sessionId&&isWorkoutView())}catch(_){}
    try{if(typeof render==='function')render()}catch(e){console.warn('CV V71 render',e)}
    try{if(typeof startTimer==='function'&&workout?.started)startTimer()}catch(_){}
  }
  async function ensureAuth(){
    if(isDemo())return true;
    if(typeof sb==='undefined')throw new Error('CV Coach no pudo conectar con el servidor.');
    let q=await bounded(sb.auth.getSession(),4000,'No pude validar tu sesión.');
    if(q?.error)throw q.error;
    if(q?.data?.session?.access_token)return true;
    q=await bounded(sb.auth.refreshSession(),5000,'No pude renovar tu sesión.');
    if(q?.error||!q?.data?.session?.access_token)throw new Error('Tu sesión expiró. Sal y vuelve a ingresar.');
    return true
  }
  async function invokeStart(dayId){
    await ensureAuth();
    let q=await bounded(sb.functions.invoke('start-workout',{body:{program_day_id:dayId}}),8000,'El servidor tardó demasiado en iniciar la rutina.');
    const authLike=x=>/(401|unauthor|jwt|token|session|sesión|auth)/i.test(String(x?.message||x?.detail||x?.error||x||''));
    if(q?.error||q?.data?.error){
      const detail=q?.data?.detail||q?.data?.error||q?.error?.message||'No pude iniciar el entrenamiento.';
      if(authLike(detail)){
        const r=await bounded(sb.auth.refreshSession(),5000,'No pude renovar tu sesión.');
        if(!r?.error&&r?.data?.session?.access_token)q=await bounded(sb.functions.invoke('start-workout',{body:{program_day_id:dayId}}),8000,'El servidor no respondió al reintentar.');
      }
    }
    if(q?.error||q?.data?.error)throw new Error(q?.data?.detail||q?.data?.error||q?.error?.message||'No pude iniciar el entrenamiento.');
    return q?.data||null
  }
  async function recover(dayId){
    if(isDemo()||typeof sb==='undefined'||!user?.id)return null;
    const q=await bounded(sb.from('workout_sessions').select('id,program_day_id,started_at,status').eq('client_id',user.id).eq('status','in_progress').order('started_at',{ascending:false}).limit(1).maybeSingle(),4500,'No pude verificar la sesión activa.');
    if(q?.error||!q?.data?.id)return null;
    if(q.data.program_day_id!==dayId)return {session_id:q.data.id,program_day_id:q.data.program_day_id,started_at:q.data.started_at,exercises:null,idempotent:true};
    try{return await invokeStart(dayId)}catch(_){return {session_id:q.data.id,program_day_id:q.data.program_day_id,started_at:q.data.started_at,exercises:null,idempotent:true}}
  }
  async function hydrateReferences(exercises){
    if(isDemo()||!Array.isArray(exercises)||typeof sb==='undefined')return;
    const sets=exercises.flatMap(e=>Array.isArray(e.sets)?e.sets:[]),ids=[...new Set(sets.map(s=>s.reference_set_log_id).filter(Boolean))];if(!ids.length)return;
    try{const q=await bounded(sb.from('set_logs').select('id,weight_kg,reps,duration_seconds,completed_at').in('id',ids),5000,'history timeout');if(q?.error)return;const map=new Map((q.data||[]).map(r=>[r.id,r]));for(const s of sets){const r=map.get(s.reference_set_log_id);if(r){s.reference_weight_kg=r.weight_kg;s.reference_reps=r.reps;s.reference_duration_seconds=r.duration_seconds;s.reference_completed_at=r.completed_at}}}catch(_){}
  }
  async function canonicalStart(){
    if(!isWorkoutView())return false;
    if(workout?.sessionId){finalizeVisual();return true}
    if(activeStart)return activeStart;
    const target=workout,requestedDay=target.dayId,snap=snapshotInputs();
    setStartUI(true);
    activeStart=(async()=>{
      try{
        if(isDemo()){
          const ex=typeof window.cvExercises==='function'?window.cvExercises():[];
          target.sessionId='demo';target.started=Date.now();target.liveExercises=Array.isArray(ex)?ex:[];
          target.liveExercises.forEach((e,ei)=>(e.sets||[]).forEach((s,si)=>{s.set_log_id=s.set_log_id||`demo_${ei}_${si}`}));
          applySnapshot(target.liveExercises,snap);finalizeVisual();toast?.('Entrenamiento iniciado');return true
        }
        let payload=null;
        try{payload=await bounded(invokeStart(requestedDay),START_TIMEOUT_MS,'El inicio del entrenamiento no respondió a tiempo.')}catch(first){payload=await recover(requestedDay);if(!payload)throw first}
        if(!payload?.session_id)throw new Error('El servidor no confirmó la sesión de entrenamiento.');
        const effectiveDay=payload.program_day_id||requestedDay;
        if(effectiveDay!==requestedDay){target.dayId=effectiveDay;toast?.('Recuperé la sesión que ya estaba activa.')}
        target.sessionId=payload.session_id;target.started=payload.started_at?new Date(payload.started_at).getTime():Date.now();
        target.liveExercises=Array.isArray(payload.exercises)?payload.exercises:(typeof window.cvExercises==='function'?window.cvExercises():[]);
        if(effectiveDay===requestedDay)applySnapshot(target.liveExercises,snap);
        await hydrateReferences(target.liveExercises);finalizeVisual();toast?.(payload.idempotent?'Sesión reanudada':'Entrenamiento iniciado');return true
      }catch(err){console.error('CV V71 start failed',err);toast?.(err?.message||'No pude iniciar el entrenamiento.');return false}
      finally{const started=!!target.sessionId;if(!started)setStartUI(false);activeStart=null}
    })();
    return activeStart
  }

  /* V71 owns workout start only. Keyboard/viewport behavior belongs exclusively to V72. */
  window.startWorkout=canonicalStart;

  window.CVWorkoutControllerV71={version:'v71',start:canonicalStart,diagnose:()=>({mode:typeof mode==='undefined'?null:mode,view:typeof view==='undefined'?null:view,dayId:workout?.dayId||null,sessionId:workout?.sessionId||null,started:workout?.started||null,busy:!!activeStart})};
})();
