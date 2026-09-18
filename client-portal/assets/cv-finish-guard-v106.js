(()=>{
  'use strict';

  const VERSION='106';
  const READY='CV_FINISH_GUARD_V106_READY';
  let bypass=false;

  function visible(el){
    if(!el)return false;
    const r=el.getBoundingClientRect(),s=getComputedStyle(el);
    return r.width>0&&r.height>0&&s.display!=='none'&&s.visibility!=='hidden';
  }

  function injectStyle(){
    if(document.getElementById('cvFinishGuardV106Style'))return;
    const style=document.createElement('style');
    style.id='cvFinishGuardV106Style';
    style.textContent=`
      .cvFinishGuardV106Backdrop{
        position:fixed;inset:0;z-index:390;display:flex;align-items:flex-end;justify-content:center;
        padding:14px;background:rgba(0,0,0,.86);backdrop-filter:blur(11px);
      }
      .cvFinishGuardV106Card{
        width:min(560px,100%);padding:18px;border:1px solid #303b43;border-radius:20px;
        background:linear-gradient(155deg,#0d1419,#070b0f);box-shadow:0 28px 90px rgba(0,0,0,.70);
      }
      .cvFinishGuardV106Ey{color:#ff8792;font-size:8px;font-weight:900;letter-spacing:.14em}
      .cvFinishGuardV106Card h2{margin:5px 0 7px;font-size:29px;line-height:1.02}
      .cvFinishGuardV106Sub{color:#aab5bb;font-size:11px;line-height:1.45}
      .cvFinishGuardV106Progress{
        margin-top:15px;padding:13px;border:1px solid #27343c;border-radius:14px;background:#060b0f;
      }
      .cvFinishGuardV106ProgressTop{display:flex;align-items:end;justify-content:space-between;gap:12px}
      .cvFinishGuardV106ProgressTop b{font:900 25px/1 'Barlow Condensed',Inter,sans-serif;color:#fff}
      .cvFinishGuardV106ProgressTop span{color:#8d9aa2;font-size:9px;font-weight:800}
      .cvFinishGuardV106Track{height:6px;margin-top:9px;overflow:hidden;border-radius:999px;background:#182128}
      .cvFinishGuardV106Fill{
        height:100%;width:0;border-radius:inherit;
        background:linear-gradient(90deg,#2ba8f3,#49c7d8,#5ee3a5);
        transition:width .2s ease;
      }
      .cvFinishGuardV106Warning{
        margin-top:11px;padding:10px 11px;border:1px solid rgba(255,104,120,.25);border-radius:11px;
        background:rgba(255,73,92,.055);color:#c8d0d4;font-size:10px;line-height:1.45;
      }
      .cvFinishGuardV106Actions{display:grid;grid-template-columns:1fr;gap:8px;margin-top:14px}
      .cvFinishGuardV106Actions button{min-height:48px;border-radius:12px;font-weight:900}
      #cvFinishGuardContinueV106{
        border:1px solid #34aeea;background:linear-gradient(180deg,#35b8f4,#149ddd);color:#fff;
      }
      #cvFinishGuardConfirmV106{
        border:1px solid #3b454b;background:#0a1014;color:#d4dde1;
      }
      @media(min-width:700px){
        .cvFinishGuardV106Backdrop{align-items:center}
        .cvFinishGuardV106Actions{grid-template-columns:1.25fr 1fr}
      }
    `;
    document.head.appendChild(style);
  }

  function state(){
    const rows=[...document.querySelectorAll('.cvSetRow')];
    const total=rows.length;
    const done=rows.filter(row=>row.classList.contains('done')).length;
    const pending=Math.max(0,total-done);
    const pct=total?Math.round(done/total*100):0;
    return {total,done,pending,pct};
  }

  function closeGuard(){
    const guard=document.getElementById('cvFinishGuardV106');
    guard?.remove();
    document.body.classList.remove('cvFinishGuardV106Open');
  }

  function returnToCurrent(){
    closeGuard();
    requestAnimationFrame(()=>{
      const current=document.querySelector('.cvV105ExerciseOpen,.cvExerciseCurrent');
      current?.scrollIntoView?.({behavior:'smooth',block:'center'});
      const input=current?.querySelector('.cvSetRow:not(.done) input[id^="cvw_"],.cvSetRow:not(.done) input[id^="cvr_"]');
      setTimeout(()=>input?.focus?.({preventScroll:true}),260);
    });
  }

  async function finishAnyway(){
    closeGuard();
    bypass=true;
    try{
      if(typeof window.finishWorkout==='function'){
        await window.finishWorkout();
      }
    }finally{
      setTimeout(()=>{bypass=false},0);
    }
  }

  function showGuard(progress){
    injectStyle();
    closeGuard();
    const backdrop=document.createElement('div');
    backdrop.id='cvFinishGuardV106';
    backdrop.className='cvFinishGuardV106Backdrop';
    backdrop.innerHTML=`
      <section class="cvFinishGuardV106Card" role="dialog" aria-modal="true" aria-labelledby="cvFinishGuardTitleV106">
        <div class="cvFinishGuardV106Ey">CIERRE DE SESIÓN</div>
        <h2 id="cvFinishGuardTitleV106">Aún quedan series pendientes</h2>
        <div class="cvFinishGuardV106Sub">Puedes seguir entrenando o cerrar la sesión de forma consciente.</div>
        <div class="cvFinishGuardV106Progress">
          <div class="cvFinishGuardV106ProgressTop">
            <b>${progress.done} / ${progress.total} SERIES</b>
            <span>${progress.pct}% completado</span>
          </div>
          <div class="cvFinishGuardV106Track" aria-hidden="true"><div class="cvFinishGuardV106Fill" style="width:${progress.pct}%"></div></div>
        </div>
        <div class="cvFinishGuardV106Warning">
          Quedan <b>${progress.pending} ${progress.pending===1?'serie pendiente':'series pendientes'}</b>.
          Si finalizas ahora, el cierre reflejará únicamente lo que alcanzaste a registrar.
        </div>
        <div class="cvFinishGuardV106Actions">
          <button id="cvFinishGuardContinueV106" type="button">SEGUIR ENTRENANDO</button>
          <button id="cvFinishGuardConfirmV106" type="button">FINALIZAR IGUAL</button>
        </div>
      </section>`;
    document.body.appendChild(backdrop);
    document.body.classList.add('cvFinishGuardV106Open');

    const keep=backdrop.querySelector('#cvFinishGuardContinueV106');
    const finish=backdrop.querySelector('#cvFinishGuardConfirmV106');
    keep.onclick=returnToCurrent;
    finish.onclick=finishAnyway;
    backdrop.addEventListener('click',event=>{if(event.target===backdrop)returnToCurrent()});
    requestAnimationFrame(()=>keep.focus());
  }

  function finishButton(target){
    const button=target?.closest?.('.workoutTop button');
    if(!button||!/FINALIZAR/i.test(button.textContent||''))return null;
    return button;
  }

  window.addEventListener('click',event=>{
    if(bypass)return;
    const button=finishButton(event.target);
    if(!button)return;
    if(!document.body.classList.contains('cvWorkoutActiveV40'))return;
    const progress=state();
    if(!progress.total||progress.done>=progress.total)return;
    event.preventDefault();
    event.stopPropagation();
    event.stopImmediatePropagation();
    showGuard(progress);
  },true);

  document.addEventListener('keydown',event=>{
    if(event.key==='Escape'&&document.getElementById('cvFinishGuardV106')){
      event.preventDefault();
      returnToCurrent();
    }
  });

  injectStyle();
  document.documentElement.setAttribute('data-cv-finish-guard','106');
  window.CVFinishGuardV106={
    version:VERSION,
    ready:true,
    marker:READY,
    progress:state,
    refresh:()=>state()
  };
  console.info(READY);
})();