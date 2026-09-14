(function(){
  if(window.CVWorkoutSetGuardV74)return;
  const VERSION='v74';
  const MIN_LOCK_MS=420;
  const pending=new Map();
  let installed=null;
  let renderInstalled=null;
  const NUMPAD_SELECTOR='input[id^="cvw_"],input[id^="cvr_"]';

  function ensureSetInputBridge(){
    if(typeof window.cvSetFromInputs==='function')return window.cvSetFromInputs;
    const bridge=function(i,j){
      const exs=typeof window.cvExercises==='function'?(window.cvExercises()||[]):[];
      const ex=exs?.[i],s=ex?.sets?.[j];
      if(!s)return null;
      const unit=ex.prescription_unit||'reps';
      const w=document.getElementById('cvw_'+i+'_'+j),r=document.getElementById('cvr_'+i+'_'+j),ri=document.getElementById('cvri_'+i+'_'+j);
      const wt=unit==='reps'&&w&&w.value!==''?Number(w.value):null;
      const target=r&&r.value!==''?Number(r.value):null;
      const rir=ri&&ri.value!==''?Number(ri.value):null;
      if(wt!=null&&!Number.isFinite(wt))return null;
      if(target!=null&&(!Number.isFinite(target)||target<0))return null;
      if(rir!=null&&(!Number.isFinite(rir)||rir<0||rir>10))return null;
      s.weight_kg=unit==='reps'?wt:null;
      if(unit==='seconds'){
        s.duration_seconds=target==null?null:Math.round(target);
        s.reps=null;
      }else{
        s.reps=target==null?null:Math.round(target);
        s.duration_seconds=null;
      }
      s.rir=rir;
      return {ex,s,unit,weight_kg:s.weight_kg,reps:s.reps,duration_seconds:s.duration_seconds,rir,target}
    };
    bridge.__cvSetInputBridgeV80=true;
    window.cvSetFromInputs=bridge;
    return bridge
  }

  function key(i,j){return String(i)+':'+String(j)}
  function rowFor(i,j){
    const input=document.getElementById('cvw_'+i+'_'+j)||document.getElementById('cvr_'+i+'_'+j);
    return input?.closest('.cvSetRow')||null
  }
  function paint(i,j,busy){
    const row=rowFor(i,j),btn=row?.querySelector('.cvSetCheck');
    row?.classList.toggle('cv74SetPending',!!busy);
    if(!btn)return;
    btn.classList.toggle('cv74SetPending',!!busy);
    btn.disabled=!!busy;
    if(busy)btn.setAttribute('aria-busy','true');else btn.removeAttribute('aria-busy')
  }
  function release(k,i,j){
    pending.delete(k);
    paint(i,j,false)
  }
  function ensureStyle(){
    if(document.getElementById('cv-workout-set-guard-v74-css'))return;
    const style=document.createElement('style');
    style.id='cv-workout-set-guard-v74-css';
    style.textContent='.cvSetCheck.cv74SetPending{pointer-events:none!important;opacity:.78!important}.cvSetRow.cv74SetPending{will-change:contents}';
    document.head.appendChild(style)
  }

  function ownInput(el){
    if(!(el instanceof HTMLInputElement)||!/^cv[wr]_\d+_\d+$/.test(el.id||'')||el.disabled)return false;
    let changed=false;
    if(!el.readOnly){el.readOnly=true;changed=true}
    if(!el.hasAttribute('readonly')){el.setAttribute('readonly','');changed=true}
    if(el.getAttribute('inputmode')!=='none'){el.setAttribute('inputmode','none');changed=true}
    if(el.getAttribute('enterkeyhint')!=='done'){el.setAttribute('enterkeyhint','done');changed=true}
    if(el.getAttribute('aria-haspopup')!=='dialog'){el.setAttribute('aria-haspopup','dialog');changed=true}
    if(el.getAttribute('role')!=='button'){el.setAttribute('role','button');changed=true}
    if(el.dataset.cvPadV73!=='1'){el.dataset.cvPadV73='1';changed=true}
    return changed
  }
  function enforceNumpadOwnership(root=document){
    try{
      if(root instanceof HTMLInputElement)ownInput(root);
      root?.querySelectorAll?.(NUMPAD_SELECTOR).forEach(ownInput);
      if(window.CVWorkoutNumpadV73?.decorate)window.CVWorkoutNumpadV73.decorate()
    }catch(_){}
  }
  function installRenderOwnership(){
    const current=window.render;
    if(typeof current!=='function')return false;
    if(current.__cvNumpadOwnershipV76){renderInstalled=current;return true}
    const base=current;
    const guarded=function(){
      const result=base.apply(this,arguments);
      enforceNumpadOwnership(document);
      return result
    };
    guarded.__cvNumpadOwnershipV76=true;
    guarded.__cvNumpadOwnershipBase=base;
    window.render=guarded;
    renderInstalled=guarded;
    return true
  }

  function install(){
    ensureSetInputBridge();
    ensureStyle();
    installRenderOwnership();
    enforceNumpadOwnership(document);
    const current=window.cvToggleSet;
    if(typeof current!=='function'||current.__cvSetGuardV74)return false;
    const base=current;
    const guarded=async function(i,j){
      const k=key(i,j);
      if(pending.has(k))return false;
      const startedAt=Date.now();
      pending.set(k,{startedAt});
      paint(i,j,true);
      let result;
      try{
        result=await base.apply(this,arguments)
      }catch(err){
        release(k,i,j);
        throw err
      }
      const left=MIN_LOCK_MS-(Date.now()-startedAt);
      if(left>0)setTimeout(()=>release(k,i,j),left);else release(k,i,j);
      return result
    };
    guarded.__cvSetGuardV74=true;
    guarded.__cvSetGuardBase=base;
    window.cvToggleSet=guarded;
    installed=guarded;
    return true
  }

  const observer=new MutationObserver(records=>{
    if(window.cvToggleSet!==installed&&!window.cvToggleSet?.__cvSetGuardV74)install();
    if(window.render!==renderInstalled&&!window.render?.__cvNumpadOwnershipV76)installRenderOwnership();
    for(const rec of records)for(const node of rec.addedNodes){
      if(node instanceof Element)enforceNumpadOwnership(node)
    }
    for(const k of pending.keys()){
      const [i,j]=k.split(':').map(Number);paint(i,j,true)
    }
  });
  observer.observe(document.getElementById('content')||document.body,{childList:true,subtree:true});
  ensureSetInputBridge();
  install();
  setTimeout(install,250);
  setTimeout(install,1200);
  document.addEventListener('cv:rendered',()=>{install();enforceNumpadOwnership(document)});
  document.addEventListener('pointerdown',e=>{if(e.target instanceof HTMLInputElement)ownInput(e.target)},true);
  document.addEventListener('touchstart',e=>{if(e.target instanceof HTMLInputElement)ownInput(e.target)},{capture:true,passive:true});
  window.addEventListener('pageshow',()=>{install();enforceNumpadOwnership(document)});
  window.CVWorkoutSetGuardV74={version:VERSION,minLockMs:MIN_LOCK_MS,pending,install,enforceNumpadOwnership,ensureSetInputBridge};
})();
