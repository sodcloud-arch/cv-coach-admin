from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PORTAL = ROOT / 'client-portal/stable/index.html'
text = PORTAL.read_text(encoding='utf-8')

if 'cv-client-workout-v31' in text:
    raise SystemExit('cv-client-workout-v31 already present')

css = r'''<style id="cv-client-workout-v31">
/* CV Coach · Client Workout Visual V1
   Client-facing only: RIR stays in data/model but is intentionally hidden from the athlete. */
body.cvFastWorkout{--cvw-red:#ff3249;--cvw-red2:#e11d2e;--cvw-green:#59e4a5;--cvw-panel:#0a1015;--cvw-panel2:#101820;--cvw-line:#283640;--cvw-muted:#88969f}

/* Hide internal coach metric from client UI and keyboard flow. */
body.cvFastWorkout .cvRirInput,
body.cvFastWorkout .cvSetsHead span:nth-child(5){display:none!important}
body.cvFastWorkout .cvSetsHead,
body.cvFastWorkout .cvSetRow{grid-template-columns:44px minmax(110px,180px) 96px 96px 52px!important;justify-content:start!important;gap:8px!important}
body.cvFastWorkout .cvSetsHead,
body.cvFastWorkout .cvSetRows,
body.cvFastWorkout .cvAddSet{width:min(100%,640px)!important;margin-left:54px!important}
body.cvFastWorkout .cvSetsHead{padding-left:0!important;padding-right:0!important}
body.cvFastWorkout .cvSetRow{width:100%!important}
body.cvFastWorkout .cvAddSet{margin-top:10px!important}

/* Session hero: gives the workout a clear narrative and visible progress. */
.cvWorkoutHeroV31{position:relative;overflow:hidden;margin:0 0 14px;padding:22px 24px 20px;border:1px solid #303d46;border-radius:18px;background:
 radial-gradient(circle at 92% 18%,rgba(255,50,73,.18),transparent 31%),
 linear-gradient(135deg,#111920 0%,#090f14 58%,#070b0f 100%);box-shadow:0 22px 58px rgba(0,0,0,.34),inset 0 1px 0 rgba(255,255,255,.035)}
.cvWorkoutHeroV31:before{content:'';position:absolute;left:0;top:0;bottom:0;width:4px;background:linear-gradient(180deg,#ff5368,#d9142b);box-shadow:0 0 22px rgba(255,45,68,.45)}
.cvWorkoutHeroV31:after{content:'';position:absolute;right:-40px;top:-70px;width:260px;height:260px;border-radius:50%;border:1px solid rgba(255,255,255,.025);box-shadow:0 0 0 36px rgba(255,255,255,.012),0 0 0 78px rgba(255,255,255,.008);pointer-events:none}
.cvWorkoutHeroTop{display:flex;align-items:center;gap:10px;position:relative;z-index:2}
.cvWorkoutHeroEy{font-size:9px;font-weight:900;letter-spacing:.2em;color:#ff6679;text-transform:uppercase}
.cvWorkoutLivePill{display:inline-flex;align-items:center;gap:6px;margin-left:auto;padding:6px 9px;border:1px solid rgba(255,64,87,.30);border-radius:999px;background:rgba(255,32,55,.08);font-size:8px;font-weight:900;letter-spacing:.08em;color:#ff8b98}
.cvWorkoutLivePill:before{content:'';width:6px;height:6px;border-radius:50%;background:#ff3f56;box-shadow:0 0 12px rgba(255,63,86,.8)}
.cvWorkoutHeroV31 h1{position:relative;z-index:2;margin:8px 0 5px!important;font-size:clamp(31px,3.1vw,48px)!important;line-height:.96!important;color:#fff!important;letter-spacing:-.045em!important}
.cvWorkoutHeroFocus{position:relative;z-index:2;color:#9fabb2;font-size:12px;line-height:1.5}
.cvWorkoutHeroChips{position:relative;z-index:2;display:flex;flex-wrap:wrap;gap:7px;margin-top:15px}
.cvWorkoutHeroChip{display:inline-flex;align-items:center;min-height:28px;padding:0 10px;border:1px solid #314049;border-radius:999px;background:#090f13;color:#c5ced3;font-size:9px;font-weight:800}
.cvWorkoutHeroChip strong{color:#fff;margin-right:4px}
.cvWorkoutProgressTrack{position:relative;z-index:2;height:8px;margin-top:17px;border-radius:999px;background:#182129;overflow:hidden;border:1px solid rgba(255,255,255,.025)}
.cvWorkoutProgressFill{height:100%;width:0;border-radius:inherit;background:linear-gradient(90deg,#d91831,#ff5368);box-shadow:0 0 18px rgba(255,45,68,.28);transition:width .28s ease}
.cvWorkoutProgressCopy{position:relative;z-index:2;display:flex;justify-content:space-between;gap:12px;margin-top:7px;color:#77858d;font-size:9px;font-weight:700}
.cvWorkoutProgressCopy b{color:#dce3e7}

/* Session stats get depth and distinct semantic accents. */
body.cvFastWorkout .cvSessionStats{margin:0 0 15px!important;border:1px solid #28353e!important;border-radius:15px!important;overflow:hidden!important;background:#28353e!important;box-shadow:0 15px 38px rgba(0,0,0,.24)!important}
body.cvFastWorkout .cvSessionStat{position:relative;min-height:74px!important;padding:13px 16px!important;background:linear-gradient(180deg,#0d141a,#080d11)!important}
body.cvFastWorkout .cvSessionStat:after{content:'';position:absolute;left:16px;bottom:9px;width:30px;height:2px;border-radius:99px;background:#394852}
body.cvFastWorkout .cvSessionStat.duration:after{background:#ff4057;box-shadow:0 0 10px rgba(255,64,87,.3)}
body.cvFastWorkout .cvSessionStat.volume:after{background:#59e4a5;box-shadow:0 0 10px rgba(89,228,165,.22)}
body.cvFastWorkout .cvSessionStat small{color:#839099!important;font-size:9px!important;letter-spacing:.07em!important;text-transform:uppercase!important}
body.cvFastWorkout .cvSessionStat b{margin-top:4px!important;font-size:28px!important}

/* Exercise cards: pending, current and complete are visually distinct. */
body.cvFastWorkout .cvHevyExercise{position:relative!important;margin-bottom:12px!important;padding:18px 16px 16px!important;border:1px solid #26343d!important;border-radius:17px!important;background:linear-gradient(150deg,#0d151b,#080d11 72%,#070b0e)!important;box-shadow:0 15px 36px rgba(0,0,0,.26)!important;transition:border-color .2s ease,box-shadow .2s ease,transform .2s ease,opacity .2s ease!important}
body.cvFastWorkout .cvHevyExercise:before{content:''!important;position:absolute!important;left:0!important;top:16px!important;bottom:16px!important;width:3px!important;height:auto!important;background:#25323a!important;border-radius:0 4px 4px 0!important;box-shadow:none!important}
body.cvFastWorkout .cvHevyExercise.cvExerciseCurrent{border-color:rgba(255,64,87,.48)!important;background:radial-gradient(circle at 100% 0,rgba(255,50,73,.09),transparent 29%),linear-gradient(150deg,#111820,#090e13 72%,#080c10)!important;box-shadow:0 19px 48px rgba(0,0,0,.34),0 0 34px rgba(225,29,46,.055)!important;transform:translateY(-1px)}
body.cvFastWorkout .cvHevyExercise.cvExerciseCurrent:before{background:linear-gradient(180deg,#ff5065,#d91831)!important;box-shadow:0 0 16px rgba(255,55,78,.30)!important}
body.cvFastWorkout .cvHevyExercise.cvExerciseComplete{border-color:rgba(89,228,165,.30)!important;background:linear-gradient(150deg,#0c1714,#08110f 74%,#070c0b)!important;box-shadow:0 14px 36px rgba(0,0,0,.24),0 0 24px rgba(89,228,165,.035)!important}
body.cvFastWorkout .cvHevyExercise.cvExerciseComplete:before{background:#59e4a5!important;box-shadow:0 0 13px rgba(89,228,165,.25)!important}
body.cvFastWorkout .cvHevyExercise.cvExercisePending:not(.cvExerciseCurrent){opacity:.90}
body.cvFastWorkout .exerciseTop{align-items:flex-start!important;margin-bottom:3px!important}
body.cvFastWorkout .exerciseTop .num{width:46px!important;height:46px!important;min-width:46px!important;border-radius:13px!important;background:linear-gradient(145deg,rgba(255,43,65,.19),rgba(107,16,31,.22))!important;border-color:rgba(255,64,87,.36)!important;color:#ff6476!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.04)!important}
body.cvFastWorkout .cvExerciseComplete .exerciseTop .num{background:rgba(89,228,165,.09)!important;border-color:rgba(89,228,165,.28)!important;color:#75edb2!important}
body.cvFastWorkout .exerciseTop h3{font-size:28px!important;line-height:1.02!important;margin:1px 0 8px!important}
.cvExerciseStatusV31{display:inline-flex;align-items:center;min-height:23px;padding:0 8px;border:1px solid #35424b;border-radius:999px;background:#090e12;color:#89969e;font-size:7.5px;font-weight:900;letter-spacing:.09em;text-transform:uppercase;vertical-align:middle}
.cvExerciseStatusV31.current{border-color:rgba(255,64,87,.34);background:rgba(255,32,55,.08);color:#ff7484}
.cvExerciseStatusV31.complete{border-color:rgba(89,228,165,.28);background:rgba(89,228,165,.07);color:#74eeb1}
.cvPrescription{display:flex!important;flex-wrap:wrap!important;gap:6px!important;align-items:center!important;margin-top:0!important;color:inherit!important}
.cvPrescriptionChip{display:inline-flex;align-items:center;min-height:25px;padding:0 8px;border:1px solid #2d3b44;border-radius:999px;background:#080e12;color:#aeb9bf;font-size:8.5px;font-weight:800;white-space:nowrap}
body.cvFastWorkout .cvHevyExercise>.cvRestText{display:inline-flex!important;width:auto!important;margin:9px 0 12px 55px!important;padding:6px 9px!important;border:1px solid rgba(255,64,87,.20)!important;border-radius:999px!important;background:rgba(255,32,55,.055)!important;color:#ff697a!important;font-size:9px!important;letter-spacing:.02em!important}

/* Inputs: clearer hierarchy and stronger success feedback. */
body.cvFastWorkout .cvSetRows{gap:6px!important}
body.cvFastWorkout .cvSetRow{min-height:54px!important;padding:2px 0!important;border-radius:11px!important}
body.cvFastWorkout .cvSetRow.done{background:linear-gradient(90deg,rgba(89,228,165,.07),transparent 78%)!important}
body.cvFastWorkout .cvSetNo{width:44px!important;height:50px!important;background:#111a20!important;border-color:#2d3a43!important;color:#fff!important}
body.cvFastWorkout .cvSetRow input{height:50px!important;background:#050a0e!important;border-color:#313e47!important;font-size:21px!important;box-shadow:inset 0 1px 0 rgba(255,255,255,.02)!important}
body.cvFastWorkout .cvSetRow input:focus{border-color:#ff4d62!important;box-shadow:0 0 0 3px rgba(255,64,87,.09)!important}
body.cvFastWorkout .cvSetCheck{width:52px!important;height:50px!important;border-radius:11px!important;background:#11191f!important;border-color:#35434c!important;color:#65737c!important}
body.cvFastWorkout .cvSetCheck.done{background:linear-gradient(145deg,#174b30,#10331f)!important;border-color:#4aa071!important;color:#82f1b9!important;box-shadow:0 0 18px rgba(89,228,165,.12)!important}
body.cvFastWorkout .cvAddSet{height:45px!important;border-style:dashed!important;border-color:#35434c!important;background:rgba(15,23,29,.72)!important;color:#d9e0e4!important}

@media(max-width:767px){
 .cvWorkoutHeroV31{padding:18px 17px 16px;margin-bottom:10px;border-radius:16px}.cvWorkoutHeroV31 h1{font-size:32px!important}.cvWorkoutHeroFocus{font-size:11px}.cvWorkoutHeroChips{margin-top:12px;gap:5px}.cvWorkoutHeroChip{font-size:8px;padding:0 8px}
 body.cvFastWorkout .cvSetsHead,body.cvFastWorkout .cvSetRows,body.cvFastWorkout .cvAddSet{width:100%!important;margin-left:0!important}
 body.cvFastWorkout .cvSetsHead,body.cvFastWorkout .cvSetRow{grid-template-columns:38px minmax(66px,1fr) 68px 68px 44px!important;gap:4px!important}
 body.cvFastWorkout .cvSetNo{width:38px!important;height:47px!important;font-size:19px!important}body.cvFastWorkout .cvSetRow input{height:47px!important;font-size:19px!important}body.cvFastWorkout .cvSetCheck{width:44px!important;height:47px!important}
 body.cvFastWorkout .exerciseTop .num{width:41px!important;height:41px!important;min-width:41px!important}body.cvFastWorkout .exerciseTop h3{font-size:24px!important;margin-bottom:6px!important}
 body.cvFastWorkout .cvHevyExercise>.cvRestText{margin-left:50px!important}.cvPrescriptionChip{font-size:7.8px;min-height:23px}
 body.cvFastWorkout .cvSessionStat{min-height:65px!important;padding:10px!important}body.cvFastWorkout .cvSessionStat b{font-size:24px!important}.cvWorkoutProgressCopy{font-size:8px}
}
@media(max-width:380px){
 body.cvFastWorkout .cvSetsHead,body.cvFastWorkout .cvSetRow{grid-template-columns:35px minmax(57px,1fr) 62px 62px 41px!important;gap:3px!important}
 body.cvFastWorkout .cvSetsHead span{font-size:9px!important}.cvWorkoutHeroV31{padding-left:15px;padding-right:15px}
}
</style>'''

js = r'''<script id="cv-client-workout-v31-js">
(function(){
  function cleanDayName(name){return String(name||'Entrenamiento').replace(/^D[ií]a\s*\d+\s*[—–-]?\s*/i,'').trim()||'Entrenamiento'}
  function athleteExercises(){try{return typeof cvExercises==='function'?(cvExercises()||[]):[]}catch(_){return []}}
  function stripRirPrescription(el){
    if(!el)return;const raw=(el.textContent||'').split('·').map(x=>x.trim()).filter(Boolean).filter(x=>!/^RIR\b/i.test(x));
    el.replaceChildren(...raw.map(text=>{const s=document.createElement('span');s.className='cvPrescriptionChip';s.textContent=text;return s}));
  }
  function hideRir(){
    document.querySelectorAll('.cvRirInput').forEach(x=>{x.hidden=true;x.tabIndex=-1;x.setAttribute('aria-hidden','true')});
    document.querySelectorAll('.cvSetsHead').forEach(h=>{const x=h.children?.[4];if(x){x.hidden=true;x.setAttribute('aria-hidden','true')}});
    document.querySelectorAll('.cvPrescription').forEach(stripRirPrescription);
  }
  function exerciseState(){
    const cards=[...document.querySelectorAll('.cvHevyExercise')],exs=athleteExercises();let currentFound=false,doneExercises=0,totalSets=0,doneSets=0;
    cards.forEach((card,i)=>{
      const ex=exs[i],sets=Array.isArray(ex?.sets)?ex.sets:[],total=sets.length||card.querySelectorAll('.cvSetRow').length,done=sets.length?sets.filter(s=>s.completed).length:card.querySelectorAll('.cvSetCheck.done').length,complete=total>0&&done>=total;
      totalSets+=total;doneSets+=done;if(complete)doneExercises++;
      const current=!complete&&!currentFound;if(current)currentFound=true;
      card.classList.toggle('cvExerciseCurrent',current);card.classList.toggle('cvExerciseComplete',complete);card.classList.toggle('cvExercisePending',!complete);
      let badge=card.querySelector('.cvExerciseStatusV31');if(!badge){badge=document.createElement('span');badge.className='cvExerciseStatusV31';card.querySelector('.exerciseTop .grow')?.appendChild(badge)}
      if(badge){badge.className='cvExerciseStatusV31 '+(complete?'complete':current?'current':'pending');badge.textContent=complete?'COMPLETADO':current?'AHORA':'PENDIENTE'}
    });
    return {cards,exs,totalSets,doneSets,doneExercises,totalExercises:cards.length};
  }
  function hero(){
    if(!document.body.classList.contains('cvFastWorkout')||!window.workout?.dayId)return;
    const content=document.getElementById('content'),stats=content?.querySelector('.cvSessionStats');if(!content||!stats)return;
    const d=window.data?.days?.find(x=>x.id===window.workout.dayId),state=exerciseState(),pct=state.totalSets?Math.round(state.doneSets/state.totalSets*100):0;
    let h=content.querySelector('.cvWorkoutHeroV31');if(!h){h=document.createElement('section');h.className='cvWorkoutHeroV31';stats.parentNode.insertBefore(h,stats)}
    const estimated=d?.estimated_minutes??null;
    h.innerHTML='<div class="cvWorkoutHeroTop"><span class="cvWorkoutHeroEy">ENTRENAMIENTO DE HOY</span><span class="cvWorkoutLivePill">EN CURSO</span></div>'+ 
      '<h1>'+esc(cleanDayName(d?.name||'Entrenamiento'))+'</h1>'+ 
      '<div class="cvWorkoutHeroFocus">'+esc(d?.focus||'Sigue tu programación y registra cada serie.')+'</div>'+ 
      '<div class="cvWorkoutHeroChips"><span class="cvWorkoutHeroChip"><strong>'+state.totalExercises+'</strong> ejercicios</span><span class="cvWorkoutHeroChip"><strong>'+state.totalSets+'</strong> series</span>'+(estimated!=null?'<span class="cvWorkoutHeroChip"><strong>~'+esc(estimated)+'</strong> min</span>':'')+'</div>'+ 
      '<div class="cvWorkoutProgressTrack"><div class="cvWorkoutProgressFill" style="width:'+pct+'%"></div></div>'+ 
      '<div class="cvWorkoutProgressCopy"><span><b>'+state.doneSets+' / '+state.totalSets+'</b> series completadas</span><span><b>'+state.doneExercises+' / '+state.totalExercises+'</b> ejercicios · '+pct+'%</span></div>';
  }
  function aria(){
    document.querySelectorAll('.cvHevyExercise').forEach((card,i)=>{const name=card.getAttribute('data-tech-name')||('Ejercicio '+(i+1));const ex=athleteExercises()[i],unit=ex?.prescription_unit||'reps';card.querySelectorAll('.cvSetRow').forEach((row,j)=>{const w=row.querySelector('input[id^="cvw_"]'),r=row.querySelector('input[id^="cvr_"]');if(w)w.setAttribute('aria-label','Peso serie '+(j+1)+' de '+name);if(r)r.setAttribute('aria-label',(unit==='seconds'?'Segundos':'Repeticiones')+' serie '+(j+1)+' de '+name)})})
  }
  function enhance(){hideRir();hero();aria()}
  const baseRender=window.render;window.render=function(){const r=baseRender.apply(this,arguments);requestAnimationFrame(enhance);return r};
  if(typeof window.cvToggleSet==='function'){const baseToggle=window.cvToggleSet;window.cvToggleSet=async function(){const r=await baseToggle.apply(this,arguments);requestAnimationFrame(enhance);return r}}
  if(typeof window.cvAddSet==='function'){const baseAdd=window.cvAddSet;window.cvAddSet=async function(){const r=await baseAdd.apply(this,arguments);requestAnimationFrame(enhance);return r}}
  if(typeof window.startWorkout==='function'){const baseStart=window.startWorkout;window.startWorkout=async function(){const r=await baseStart.apply(this,arguments);requestAnimationFrame(enhance);return r}}
  const observer=new MutationObserver(()=>{if(document.body.classList.contains('cvFastWorkout'))requestAnimationFrame(enhance)});observer.observe(document.getElementById('content')||document.body,{childList:true,subtree:true});
  requestAnimationFrame(enhance);
})();
</script>'''

if '</head>' not in text or '</body>' not in text:
    raise SystemExit('portal anchors missing')
text = text.replace('</head>', css + '\n</head>', 1)
text = text.replace('</body>', js + '\n</body>', 1)
PORTAL.write_text(text, encoding='utf-8')
print('CLIENT_WORKOUT_VISUAL_V1_PATCH_OK')
