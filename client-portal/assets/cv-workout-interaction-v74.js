(function(){
  if(window.CVWorkoutInteractionV74)return;

  const VERSION='v74';
  const pending=new Map();
  let installedToggle=null;
  let installedRender=null;

  function key(i,j){return String(i)+':'+String(j)}
  function exercises(){
    try{return typeof window.cvExercises==='function'?(window.cvExercises()||[]):[]}
    catch(_){return []}
  }
  function state(i,j){return !!exercises()?.[i]?.sets?.[j]?.completed}
  function rowFor(i,j){
    const input=document.getElementById('cvw_'+i+'_'+j)||document.getElementById('cvr_'+i+'_'+j);
    return input?.closest('.cvSetRow')||null
  }
  function buttonFor(i,j){return rowFor(i,j)?.querySelector('.cvSetCheck')||null}

  function ensureStyle(){
    if(document.getElementById('cv-workout-interaction-v74-css'))return;
    const style=document.createElement('style');
    style.id='cv-workout-interaction-v74-css';
    style.textContent='body.cvFastWorkout .cvSetRow.cv74Pending{background:linear-gradient(90deg,rgba(84,229,156,.12),transparent 84%)!important}body.cvFastWorkout .cvSetCheck.cv74Pending{position:relative;pointer-events:none!important;opacity:1!important;transform:scale(.96)}body.cvFastWorkout .cvSetCheck.cv74Pending:before{content:"";position:absolute;inset:5px;border:2px solid rgba(255,255,255,.20);border-top-color:#d9fff0;border-radius:50%;animation:cv74Spin .62s linear infinite}@keyframes cv74Spin{to{transform:rotate(360deg)}}';
    document.head.appendChild(style)
  }

  function paint(i,j,target,isPending){
    const row=rowFor(i,j),btn=buttonFor(i,j);
    if(!row||!btn)return;
    row.classList.toggle('done',!!target);
    row.classList.toggle('cv74Pending',!!isPending);
    btn.classList.toggle('done',!!target);
    btn.classList.toggle('cv74Pending',!!isPending);
    btn.setAttribute('aria-pressed',target?'true':'false');
    if(isPending){
      btn.disabled=true;
      btn.setAttribute('aria-busy','true');
    }else{
      btn.disabled=false;
      btn.removeAttribute('aria-busy');
    }
  }

  function repaintPending(){
    for(const [k,p] of pending){
      const [i,j]=k.split(':').map(Number);
      paint(i,j,p.target,true)
    }
  }

  function settle(i,j){paint(i,j,state(i,j),false)}

  function dataReady(){
    try{return typeof data!=='undefined'&&data!==null}
    catch(_){return false}
  }

  function installRenderGuard(){
    const current=window.render;
    if(typeof current!=='function'||current.__cv74RenderGuard)return;
    const base=current;
    const wrapped=function(){
      if(!dataReady())return false;
      const result=base.apply(this,arguments);
      if(pending.size)requestAnimationFrame(repaintPending);
      return result
    };
    wrapped.__cv74RenderGuard=true;
    wrapped.__cv74Base=base;
    window.render=wrapped;
    installedRender=wrapped
  }

  function installToggleGuard(){
    const current=window.cvToggleSet;
    if(typeof current!=='function'||current.__cv74Interaction)return;
    const base=current;
    const wrapped=async function(i,j){
      const k=key(i,j);
      if(pending.has(k))return false;

      const before=state(i,j),target=!before;
      pending.set(k,{target,startedAt:Date.now()});
      paint(i,j,target,true);

      let result;
      try{
        result=await base.apply(this,arguments);
      }catch(error){
        pending.delete(k);
        settle(i,j);
        throw error
      }

      const after=state(i,j);
      pending.delete(k);
      settle(i,j);

      if(after!==target){
        try{toast?.('No se confirmó la serie. Intenta nuevamente.')}catch(_){}
        return false
      }
      return result===false?false:true
    };
    wrapped.__cv74Interaction=true;
    wrapped.__cv74Base=base;
    window.cvToggleSet=wrapped;
    installedToggle=wrapped
  }

  function install(){
    ensureStyle();
    installRenderGuard();
    installToggleGuard();
    repaintPending()
  }

  const observer=new MutationObserver(()=>{
    if(pending.size)requestAnimationFrame(repaintPending)
  });
  observer.observe(document.getElementById('content')||document.body,{childList:true,subtree:true});

  install();
  setTimeout(install,250);
  setTimeout(install,1200);
  window.addEventListener('pageshow',install);
  document.addEventListener('visibilitychange',()=>{if(!document.hidden)install()});

  window.CVWorkoutInteractionV74={
    version:VERSION,
    install,
    pending,
    state,
    dataReady,
    diagnose:()=>({
      version:VERSION,
      pending:[...pending.keys()],
      toggleInstalled:window.cvToggleSet===installedToggle||!!window.cvToggleSet?.__cv74Interaction,
      renderInstalled:window.render===installedRender||!!window.render?.__cv74RenderGuard,
      dataReady:dataReady()
    })
  };
})();
