(()=>{
  'use strict';
  const VERSION='104';
  const READY='CV_INLINE_SET_ENTRY_V104_READY';
  if(window.CVInlineSetEntryV104?.ready)return;

  function isSetInput(el){
    return el instanceof HTMLInputElement && /^cv[wr]_\d+_\d+$/.test(el.id||'');
  }
  function kind(el){return /^cvw_/.test(el.id||'')?'weight':'reps'}
  function normalize(el){
    if(!isSetInput(el))return;
    let v=String(el.value??'');
    if(kind(el)==='weight'){
      v=v.replace(/,/g,'.').replace(/[^0-9.]/g,'');
      const p=v.indexOf('.');
      if(p>=0)v=v.slice(0,p+1)+v.slice(p+1).replace(/\./g,'');
      const [a,b]=v.split('.');
      v=b!==undefined?`${a}.${b.slice(0,2)}`:a;
    }else{
      v=v.replace(/[^0-9]/g,'').slice(0,3);
    }
    if(el.value!==v)el.value=v;
  }
  function enhanceInput(el){
    if(!isSetInput(el)||el.dataset.cvInlineV104==='1')return;
    el.dataset.cvInlineV104='1';
    // Use text + inputmode so mobile shows a keyboard without native number pickers/sheets.
    el.type='text';
    el.autocomplete='off';
    el.spellcheck=false;
    el.setAttribute('enterkeyhint',kind(el)==='weight'?'next':'done');
    el.setAttribute('inputmode',kind(el)==='weight'?'decimal':'numeric');
    el.setAttribute('pattern',kind(el)==='weight'?'[0-9]*[.,]?[0-9]*':'[0-9]*');
    el.removeAttribute('min');
    el.removeAttribute('max');
    el.removeAttribute('step');
  }
  function enhance(root=document){
    root.querySelectorAll?.('input[id^="cvw_"],input[id^="cvr_"]').forEach(enhanceInput);
    document.body?.classList.add('cvInlineSetEntryV104');
    document.documentElement?.setAttribute('data-cv-inline-set-entry','104');
  }
  function injectStyle(){
    if(document.getElementById('cv-v104-inline-style'))return;
    const s=document.createElement('style');
    s.id='cv-v104-inline-style';
    s.textContent=`
      body.cvInlineSetEntryV104 .cvSetRow input[data-cv-inline-v104="1"]{
        -webkit-appearance:none!important;appearance:none!important;
        margin:0!important;touch-action:manipulation!important;
      }
      body.cvInlineSetEntryV104 .cvSetRow input[data-cv-inline-v104="1"]:focus{
        border-color:#ff4057!important;
        box-shadow:0 0 0 2px rgba(255,64,87,.12)!important;
      }
      body.cvInlineSetEntryV104 .cvSetRow:focus-within{
        position:relative;z-index:2;
      }
    `;
    document.head.appendChild(s);
  }

  // Prevent any ancestor/card click behavior from turning a set edit into another sheet/modal.
  ['pointerdown','click'].forEach(type=>document.addEventListener(type,e=>{
    const el=e.target;
    if(!isSetInput(el))return;
    e.stopPropagation();
  },true));

  document.addEventListener('input',e=>{if(isSetInput(e.target))normalize(e.target)},true);
  document.addEventListener('focusin',e=>{
    const el=e.target;if(!isSetInput(el))return;
    enhanceInput(el);
    requestAnimationFrame(()=>{try{el.select()}catch(_){}});
  },true);

  const observer=new MutationObserver(mutations=>{
    for(const m of mutations){
      for(const node of m.addedNodes){if(node.nodeType===1)enhance(node)}
    }
  });

  injectStyle();
  enhance();
  if(document.documentElement)observer.observe(document.documentElement,{childList:true,subtree:true});
  document.addEventListener('DOMContentLoaded',()=>{injectStyle();enhance()},{once:true});

  window.CVInlineSetEntryV104={version:VERSION,ready:true,enhance,marker:READY};
  console.info(READY);
})();
