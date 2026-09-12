(function(){
  if(window.CVIOSKeyboardV72)return;
  const state={input:null,restoreY:0,token:0,timers:[],vvHeight:0};
  const isWorkoutInput=el=>el instanceof HTMLInputElement&&/^cv(w|r|ri)_/.test(el.id||'');
  const clearTimers=()=>{state.timers.splice(0).forEach(t=>clearTimeout(t))};
  const later=(fn,ms)=>{const t=setTimeout(fn,ms);state.timers.push(t);return t};
  const vv=()=>window.visualViewport;

  function safeBand(){
    const v=vv();
    const top=(v?.offsetTop||0)+96;
    const height=v?.height||window.innerHeight;
    return {top,bottom:(v?.offsetTop||0)+height-86};
  }
  function stabilize(token){
    if(token!==state.token||!state.input||document.activeElement!==state.input)return;
    const el=state.input,rect=el.getBoundingClientRect(),band=safeBand();
    let dy=0;
    if(rect.top<band.top)dy=rect.top-band.top;
    else if(rect.bottom>band.bottom)dy=rect.bottom-band.bottom;
    if(Math.abs(dy)>2)window.scrollBy(0,dy);
  }
  function multiStabilize(token){
    [190,330,520,760].forEach(ms=>later(()=>stabilize(token),ms));
  }
  function restore(token){
    if(token!==state.token||state.input)return;
    const y=Math.max(0,Number(state.restoreY)||0);
    window.scrollTo(0,y);
  }
  function multiRestore(token){
    // Safari can finish its native keyboard viewport animation after focusout.
    // Re-assert the pre-keyboard scroll position after each phase.
    [60,180,360,620].forEach(ms=>later(()=>restore(token),ms));
  }
  function begin(el){
    clearTimers();
    state.token+=1;
    state.input=el;
    state.restoreY=window.scrollY||window.pageYOffset||0;
    state.vvHeight=vv()?.height||window.innerHeight;
    document.body.classList.add('cvKeyboardEditingV72');
    try{el.enterKeyHint='done';el.setAttribute('enterkeyhint','done')}catch(_){}
    multiStabilize(state.token);
  }
  function end(el){
    if(state.input!==el)return;
    const token=state.token;
    state.input=null;
    document.body.classList.remove('cvKeyboardEditingV72');
    multiRestore(token);
  }

  document.addEventListener('focusin',e=>{if(isWorkoutInput(e.target))begin(e.target)},true);
  document.addEventListener('focusout',e=>{if(isWorkoutInput(e.target))end(e.target)},true);
  vv()?.addEventListener('resize',()=>{if(state.input){const token=state.token;later(()=>stabilize(token),60)}else if(state.token){const token=state.token;later(()=>restore(token),80)}},{passive:true});
  vv()?.addEventListener('scroll',()=>{if(state.input){const token=state.token;later(()=>stabilize(token),40)}},{passive:true});

  // Do not let a stale keyboard session survive a route/view change.
  document.addEventListener('cv:rendered',()=>{
    if(state.input&&!document.contains(state.input)){state.input=null;document.body.classList.remove('cvKeyboardEditingV72');clearTimers()}
  });

  window.CVIOSKeyboardV72={version:'v72',state:()=>({active:!!state.input,restoreY:state.restoreY,scrollY:window.scrollY,vvHeight:vv()?.height||window.innerHeight}),stabilize:()=>stabilize(state.token)};
})();
