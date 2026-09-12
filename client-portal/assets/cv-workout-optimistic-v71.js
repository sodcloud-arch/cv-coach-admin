(function(){
  if(window.CVWorkoutOptimisticV71)return;
  const VERSION='v71';
  const pending=new Map();
  let installedToggle=null;

  function exercises(){
    try{return typeof window.cvExercises==='function'?(window.cvExercises()||[]):[]}
    catch(_){return []}
  }
  function key(i,j){return String(i)+':'+String(j)}
  function state(i,j){return !!exercises()?.[i]?.sets?.[j]?.completed}
  function rowFor(i,j){
    const input=document.getElementById('cvw_'+i+'_'+j)||document.getElementById('cvr_'+i+'_'+j);
    return input?.closest('.cvSetRow')||null
  }
  function ensureStyle(){
    if(document.getElementById('cv-workout-optimistic-v71-css'))return;
    const style=document.createElement('style');
    style.id='cv-workout-optimistic-v71-css';
    style.textContent='body.cvFastWorkout .cvSetRow.cv71Pending{background:linear-gradient(90deg,rgba(94,227,165,.105),transparent 82%)!important}body.cvFastWorkout .cvSetCheck.cv71Pending{position:relative;opacity:1!important;pointer-events:none!important}body.cvFastWorkout .cvSetCheck.cv71Pending:before{content:"";position:absolute;inset:4px;border:2px solid rgba(255,255,255,.20);border-top-color:#d9fff0;border-radius:50%;animation:cv71Spin .65s linear infinite}body.cvFastWorkout .cvSetCheck.cv71Pending.done:after{opacity:.82}@keyframes cv71Spin{to{transform:rotate(360deg)}}';
    document.head.appendChild(style)
  }
  function paint(i,j,target,isPending){
    const row=rowFor(i,j),btn=row?.querySelector('.cvSetCheck');
    if(!row||!btn)return;
    row.classList.toggle('done',!!target);
    row.classList.toggle('cv71Pending',!!isPending);
    btn.classList.toggle('done',!!target);
    btn.classList.toggle('cv71Pending',!!isPending);
    btn.setAttribute('aria-pressed',target?'true':'false');
    btn.disabled=!!isPending;
    if(isPending)btn.setAttribute('aria-busy','true');else btn.removeAttribute('aria-busy')
  }
  function syncProgress(){
    try{
      const exs=exercises(),cards=[...document.querySelectorAll('.cvHevyExercise')];
      let currentFound=false,totalSets=0,doneSets=0,doneExercises=0;
      cards.forEach((card,i)=>{
        const sets=Array.isArray(exs[i]?.sets)?exs[i].sets:[];
        const rows=[...card.querySelectorAll('.cvSetRow')];
        const total=sets.length||rows.length;
        const done=sets.length?sets.filter(s=>s.completed).length:rows.filter(r=>r.classList.contains('done')).length;
        const complete=total>0&&done>=total;
        const current=!complete&&!currentFound;
        if(current)currentFound=true;
        totalSets+=total;doneSets+=done;if(complete)doneExercises++;
        card.classList.toggle('cvExerciseCurrent',current);
        card.classList.toggle('cvExerciseComplete',complete);
        card.classList.toggle('cvExercisePending',!complete);
        let badge=card.querySelector('.cvExerciseStatusV31');
        if(!badge){badge=document.createElement('span');badge.className='cvExerciseStatusV31';card.querySelector('.exerciseTop .grow')?.appendChild(badge)}
        if(badge){badge.className='cvExerciseStatusV31 '+(complete?'complete':current?'current':'pending');badge.textContent=complete?'COMPLETADO':current?'AHORA':'PENDIENTE'}
      });
      const totalExercises=cards.length,pct=totalSets?Math.round(doneSets/totalSets*100):0;
      const fill=document.querySelector('.cvWorkoutProgressFill');if(fill)fill.style.width=pct+'%';
      const copy=document.querySelector('.cvWorkoutProgressCopy');
      if(copy)copy.innerHTML='<span><b>'+doneSets+' / '+totalSets+'</b> series completadas</span><span><b>'+doneExercises+' / '+totalExercises+'</b> ejercicios · '+pct+'%</span>';
      const compact=document.querySelector('.cvWorkoutCompactCopyV40 span:not(.cvWorkoutCompactProgressV40)');
      if(compact){
        const time=compact.querySelector('em')?.textContent||document.getElementById('cvCompactTimerV40')?.textContent||'00:00';
        let volume=0;exs.forEach(e=>(e.sets||[]).forEach(s=>{if(s.completed&&(e.prescription_unit||'reps')==='reps')volume+=(Number(s.weight_kg)||0)*(Number(s.reps)||0)}));
        compact.innerHTML='<b>'+doneSets+'/'+totalSets+'</b> series · '+Math.round(volume).toLocaleString('es-CL')+' kg · <em id="cvCompactTimerV40">'+time+'</em> · '+pct+'%'
      }
    }catch(err){console.warn('CV V71 progress sync',err)}
  }
  function repaintPending(){for(const [k,p] of pending){const [i,j]=k.split(':').map(Number);paint(i,j,p.target,true)}}
  function settle(i,j){paint(i,j,state(i,j),false);syncProgress()}

  function install(){
    ensureStyle();
    const current=window.cvToggleSet;
    if(typeof current!=='function'||current.__cv71Optimistic)return;
    const base=current;
    const wrapped=async function(i,j){
      const k=key(i,j);
      if(pending.has(k))return false;
      const before=state(i,j),target=!before;
      pending.set(k,{target,startedAt:Date.now()});
      paint(i,j,target,true);
      try{navigator.vibrate?.(12)}catch(_){}
      let result,error=null;
      try{result=await base.apply(this,arguments)}catch(err){error=err}
      const after=state(i,j),ok=after===target;
      pending.delete(k);settle(i,j);
      if(ok){
        try{navigator.vibrate?.(target?35:18)}catch(_){}
        document.dispatchEvent(new CustomEvent('cv:v71-set-settled',{detail:{i,j,completed:after}}));
        return result
      }
      if(error){console.warn('CV V71 set toggle failed',error);try{toast?.(String(error?.message||'No pude guardar la serie.'))}catch(_){}}
      else{try{toast?.('No se confirmó la serie. Intenta nuevamente.')}catch(_){}}
      return false
    };
    wrapped.__cv71Optimistic=true;wrapped.__cv71Base=base;
    window.cvToggleSet=wrapped;installedToggle=wrapped
  }

  const observer=new MutationObserver(()=>{if(pending.size)requestAnimationFrame(repaintPending)});
  observer.observe(document.getElementById('content')||document.body,{childList:true,subtree:true});
  install();setTimeout(install,250);setTimeout(install,1200);
  document.addEventListener('cv:rendered',()=>{if(window.cvToggleSet!==installedToggle&&!window.cvToggleSet?.__cv71Optimistic)install();if(pending.size)repaintPending()});
  window.addEventListener('pageshow',()=>{install();repaintPending();syncProgress()});
  document.addEventListener('visibilitychange',()=>{if(!document.hidden){install();repaintPending();syncProgress()}});
  window.CVWorkoutOptimisticV71={version:VERSION,install,repaintPending,syncProgress,pending};
})();
