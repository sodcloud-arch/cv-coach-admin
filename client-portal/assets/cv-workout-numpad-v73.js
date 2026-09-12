(function(){
  if(window.CVWorkoutNumpadV73)return;

  const state={input:null,raw:'',original:'',restoreY:0,kind:'weight',exercise:'',setNo:'',open:false};
  const selector='input[id^="cvw_"],input[id^="cvr_"],input[id^="cvri_"]';
  const isEditable=el=>el instanceof HTMLInputElement&&/^cv(w|r|ri)_\d+_\d+$/.test(el.id||'')&&!el.disabled;
  const esc=s=>String(s??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));

  function parseMeta(el){
    const m=(el.id||'').match(/^cv(w|r|ri)_(\d+)_(\d+)$/);if(!m)return null;
    const row=el.closest('.cvSetRow'),card=el.closest('.cvHevyExercise');
    const exercise=(card?.getAttribute('data-tech-name')||card?.querySelector('.exerciseTop h3')?.textContent||'Ejercicio').trim();
    const setNo=(row?.querySelector('.cvSetNo')?.textContent||String(Number(m[3])+1)).trim();
    const kind=m[1]==='w'?'weight':m[1]==='r'?'reps':'rir';
    return {kind,exercise,setNo,i:Number(m[2]),j:Number(m[3])};
  }
  function rules(){
    if(state.kind==='weight')return {title:'EDITAR PESO',unit:'kg',step:.5,decimals:true,min:0,max:999};
    if(state.kind==='rir')return {title:'EDITAR RIR',unit:'RIR',step:.5,decimals:true,min:0,max:10};
    return {title:'EDITAR REPETICIONES',unit:'reps',step:1,decimals:false,min:0,max:999};
  }
  function numericRaw(){
    const n=Number(String(state.raw||'').replace(',','.'));
    return Number.isFinite(n)?n:null;
  }
  function normalizedRaw(value){
    if(value==null||value==='')return '';
    let s=String(value).replace(',','.').replace(/[^0-9.]/g,'');
    const first=s.indexOf('.');if(first>=0)s=s.slice(0,first+1)+s.slice(first+1).replace(/\./g,'');
    return s;
  }
  function displayValue(){
    const r=rules();
    if(state.raw==='')return '—';
    return state.raw.replace('.',',')+(r.unit?` ${r.unit}`:'');
  }
  function ensure(){
    let root=document.getElementById('cvNumpadV73');if(root)return root;
    root=document.createElement('div');root.id='cvNumpadV73';root.className='cvNumpadV73 hidden';root.setAttribute('aria-hidden','true');
    root.innerHTML=`<div class="cvPadBackdropV73" data-pad-action="cancel"></div><section class="cvPadSheetV73" role="dialog" aria-modal="true" aria-labelledby="cvPadTitleV73"><div class="cvPadHandleV73"></div><div class="cvPadHeadV73"><div><div class="cvPadEyebrowV73" id="cvPadTitleV73">EDITAR</div><div class="cvPadContextV73" id="cvPadContextV73"></div></div><button type="button" class="cvPadCloseV73" data-pad-action="cancel" aria-label="Cerrar">×</button></div><div class="cvPadDisplayV73"><button type="button" class="cvPadStepV73" data-pad-action="minus" aria-label="Disminuir">−</button><div class="cvPadValueV73" id="cvPadValueV73">—</div><button type="button" class="cvPadStepV73" data-pad-action="plus" aria-label="Aumentar">+</button></div><div class="cvPadKeysV73"><button type="button" data-key="1">1</button><button type="button" data-key="2">2</button><button type="button" data-key="3">3</button><button type="button" data-key="4">4</button><button type="button" data-key="5">5</button><button type="button" data-key="6">6</button><button type="button" data-key="7">7</button><button type="button" data-key="8">8</button><button type="button" data-key="9">9</button><button type="button" data-key="decimal" class="cvPadDecimalV73">,</button><button type="button" data-key="0">0</button><button type="button" data-key="back" aria-label="Borrar">⌫</button></div><div class="cvPadActionsV73"><button type="button" class="cvPadCancelV73" data-pad-action="cancel">CANCELAR</button><button type="button" class="cvPadDoneV73" data-pad-action="done">LISTO ✓</button></div></section>`;
    document.body.append(root);
    root.addEventListener('click',onPadClick);
    return root
  }
  function renderPad(){
    const root=ensure(),r=rules();
    const title=root.querySelector('#cvPadTitleV73'),ctx=root.querySelector('#cvPadContextV73'),value=root.querySelector('#cvPadValueV73'),dec=root.querySelector('.cvPadDecimalV73');
    if(title)title.textContent=r.title;
    if(ctx)ctx.textContent=`${state.exercise} · Serie ${state.setNo}`;
    if(value)value.textContent=displayValue();
    if(dec){dec.disabled=!r.decimals;dec.classList.toggle('is-disabled',!r.decimals)}
    root.querySelectorAll('.cvPadStepV73').forEach(b=>{b.dataset.step=String(r.step)});
  }
  function decorate(){
    document.querySelectorAll(selector).forEach(el=>{
      if(el.dataset.cvPadV73==='1')return;
      el.dataset.cvPadV73='1';
      if(!el.disabled){
        el.readOnly=true;el.setAttribute('readonly','');el.setAttribute('inputmode','none');el.setAttribute('enterkeyhint','done');el.setAttribute('aria-haspopup','dialog');el.setAttribute('role','button');el.tabIndex=0;
      }
    })
  }
  function openFor(el){
    if(!isEditable(el))return false;
    const meta=parseMeta(el);if(!meta)return false;
    if(document.activeElement===el)try{el.blur()}catch(_){}
    state.input=el;state.original=String(el.value??'');state.raw=normalizedRaw(el.value);state.restoreY=window.scrollY||window.pageYOffset||0;state.kind=meta.kind;state.exercise=meta.exercise;state.setNo=meta.setNo;state.open=true;
    const root=ensure();renderPad();
    document.body.classList.add('cvPadOpenV73');el.classList.add('cvPadEditingV73');root.classList.remove('hidden');root.setAttribute('aria-hidden','false');
    try{navigator.vibrate?.(8)}catch(_){}
    return true
  }
  function close({restore=true}={}){
    const root=ensure(),el=state.input;
    root.classList.add('hidden');root.setAttribute('aria-hidden','true');document.body.classList.remove('cvPadOpenV73');el?.classList.remove('cvPadEditingV73');
    state.input=null;state.open=false;
    if(restore){const y=Math.max(0,Number(state.restoreY)||0);requestAnimationFrame(()=>window.scrollTo(0,y));setTimeout(()=>window.scrollTo(0,y),80)}
  }
  function clampValue(n){const r=rules();return Math.min(r.max,Math.max(r.min,n))}
  function setFromNumber(n){
    const r=rules();n=clampValue(n);
    if(!r.decimals)n=Math.round(n);
    else n=Math.round(n*2)/2;
    state.raw=String(n).replace(/\.0$/,'');renderPad()
  }
  function addDigit(k){
    if(k==='back'){state.raw=state.raw.slice(0,-1);renderPad();return}
    const r=rules();
    if(k==='decimal'){
      if(!r.decimals||state.raw.includes('.'))return;
      state.raw=state.raw===''?'0.':state.raw+'.';renderPad();return
    }
    if(!/^\d$/.test(k))return;
    let next=state.raw+k;
    if(next.length>7)return;
    if(/^0\d/.test(next)&&!next.startsWith('0.'))next=String(Number(next));
    state.raw=next;renderPad()
  }
  async function commit(){
    const el=state.input;if(!el)return close();
    const r=rules();let n=numericRaw();
    if(n==null&&state.raw!=='')return;
    if(n!=null){n=clampValue(n);if(!r.decimals)n=Math.round(n);else n=Math.round(n*2)/2;el.value=String(n)}else el.value='';
    el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}));
    try{navigator.vibrate?.(18)}catch(_){}
    close();
  }
  function onPadClick(e){
    const key=e.target.closest('[data-key]')?.dataset.key;if(key){e.preventDefault();addDigit(key);return}
    const action=e.target.closest('[data-pad-action]')?.dataset.padAction;if(!action)return;
    e.preventDefault();
    if(action==='cancel'){if(state.input)state.input.value=state.original;close();return}
    if(action==='done'){commit();return}
    const current=numericRaw()??0,step=rules().step;
    if(action==='minus')setFromNumber(current-step);if(action==='plus')setFromNumber(current+step)
  }

  function intercept(e){
    const el=e.target;if(!isEditable(el))return;
    e.preventDefault();e.stopPropagation();openFor(el)
  }
  document.addEventListener('pointerdown',intercept,true);
  document.addEventListener('touchstart',intercept,{capture:true,passive:false});
  document.addEventListener('click',intercept,true);
  document.addEventListener('focusin',e=>{const el=e.target;if(!isEditable(el))return;try{el.blur()}catch(_){};openFor(el)},true);
  document.addEventListener('keydown',e=>{
    if(state.open){
      if(e.key==='Escape'){e.preventDefault();close();return}
      if(e.key==='Enter'){e.preventDefault();commit();return}
      if(e.key==='Backspace'){e.preventDefault();addDigit('back');return}
      if(/^\d$/.test(e.key)){e.preventDefault();addDigit(e.key);return}
      if((e.key==='.'||e.key===',')&&rules().decimals){e.preventDefault();addDigit('decimal');return}
      return
    }
    const el=e.target;if(isEditable(el)&&(e.key==='Enter'||e.key===' ')){e.preventDefault();openFor(el)}
  },true);

  const observer=new MutationObserver(()=>requestAnimationFrame(decorate));
  const boot=()=>{ensure();decorate();observer.observe(document.body,{subtree:true,childList:true});};
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();

  window.CVWorkoutNumpadV73={version:'v73',open:id=>{const el=document.getElementById(id);return openFor(el)},close:()=>close(),state:()=>({open:state.open,inputId:state.input?.id||null,raw:state.raw,restoreY:state.restoreY,kind:state.kind}),decorate};
})();
