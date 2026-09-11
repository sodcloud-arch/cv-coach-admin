from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PORTAL = ROOT / "client-portal/index.html"
CONTRACTS = ROOT / "scripts/validate-repo-contracts.py"

portal = PORTAL.read_text(encoding="utf-8")
contracts = CONTRACTS.read_text(encoding="utf-8")

STYLE_ID = "cv-client-workout-v32"
SCRIPT_ID = "cv-client-workout-v32-js"

if STYLE_ID in portal or SCRIPT_ID in portal:
    raise SystemExit("v32 already present")

style = r'''
<style id="cv-client-workout-v32">
/* CV Coach Client Workout v32
   Semantic palette: blue = active/time, green = completed/progress, red = destructive/error only. */
body.cvFastWorkout{
  --cvw-active:#43b8ff;
  --cvw-active-strong:#249fe8;
  --cvw-active-soft:rgba(67,184,255,.10);
  --cvw-active-line:rgba(67,184,255,.42);
  --cvw-ok:#5ee3a5;
  --cvw-ok-soft:rgba(94,227,165,.10);
}

/* Duration and active session indicators are informational, not warnings. */
body.cvFastWorkout .cvSessionStat.duration b{color:var(--cvw-active)!important;text-shadow:0 0 18px rgba(67,184,255,.18)!important}
body.cvFastWorkout .cvSessionStat.duration:after{background:var(--cvw-active)!important;box-shadow:0 0 10px rgba(67,184,255,.28)!important}
body.cvFastWorkout .cvWorkoutLivePill{border-color:rgba(94,227,165,.28)!important;background:rgba(94,227,165,.07)!important;color:#8af0be!important}
body.cvFastWorkout .cvWorkoutLivePill:before{background:var(--cvw-ok)!important;box-shadow:0 0 12px rgba(94,227,165,.55)!important}

/* Current exercise uses blue; completed uses green. */
body.cvFastWorkout .cvHevyExercise.cvExerciseCurrent{border-color:var(--cvw-active-line)!important;background:radial-gradient(circle at 100% 0,rgba(67,184,255,.09),transparent 30%),linear-gradient(150deg,#101920,#090f14 72%,#080c10)!important;box-shadow:0 19px 48px rgba(0,0,0,.34),0 0 34px rgba(67,184,255,.055)!important}
body.cvFastWorkout .cvHevyExercise.cvExerciseCurrent:before{background:linear-gradient(180deg,#65c8ff,#249fe8)!important;box-shadow:0 0 16px rgba(67,184,255,.25)!important}
body.cvFastWorkout .exerciseTop .num{background:linear-gradient(145deg,rgba(67,184,255,.16),rgba(24,88,128,.18))!important;border-color:rgba(67,184,255,.34)!important;color:#78d1ff!important}
body.cvFastWorkout .cvExerciseComplete .exerciseTop .num{background:rgba(94,227,165,.09)!important;border-color:rgba(94,227,165,.28)!important;color:#82efb8!important}
.cvExerciseStatusV31.current{border-color:rgba(67,184,255,.34)!important;background:rgba(67,184,255,.075)!important;color:#83d4ff!important}
.cvExerciseStatusV31.complete{border-color:rgba(94,227,165,.28)!important;background:rgba(94,227,165,.07)!important;color:#82efb8!important}

/* Prescription and rest are neutral/blue, never alert-red. */
body.cvFastWorkout .cvPrescriptionChip{border-color:#31414a!important;background:#091116!important;color:#bdc8ce!important}
body.cvFastWorkout .cvHevyExercise>.cvRestText{border-color:rgba(67,184,255,.22)!important;background:rgba(67,184,255,.055)!important;color:#74ccff!important;text-shadow:none!important}

/* Progress carries the positive semantic. */
body.cvFastWorkout .cvWorkoutProgressFill{background:linear-gradient(90deg,#2ba8f3 0%,#49c7d8 50%,#5ee3a5 100%)!important;box-shadow:0 0 18px rgba(72,198,216,.22)!important}

/* A completed set must be unmistakably green. */
body.cvFastWorkout .cvSetRow.done{background:linear-gradient(90deg,rgba(94,227,165,.085),transparent 82%)!important}
body.cvFastWorkout .cvSetCheck.done,
body.cvFastWorkout .cvSetCheck[aria-pressed="true"]{
  background:linear-gradient(145deg,#1a5335,#103a25)!important;
  border-color:#58bd86!important;
  color:#9af3c7!important;
  box-shadow:0 0 22px rgba(94,227,165,.18),inset 0 1px 0 rgba(255,255,255,.05)!important;
  opacity:1!important;
}
body.cvFastWorkout .cvSetCheck.done:after,
body.cvFastWorkout .cvSetCheck[aria-pressed="true"]:after{content:'✓';font-size:23px;font-weight:900;line-height:1}
body.cvFastWorkout .cvSetCheck.done{font-size:0!important}

/* Visual rest timer v32: reliable and clearly visible above app navigation. */
.cvRestVisualV32{
  position:fixed;z-index:320;left:50%;bottom:calc(82px + env(safe-area-inset-bottom));transform:translateX(-50%);
  width:min(500px,calc(100% - 20px));min-height:78px;padding:11px 12px 11px 15px;
  display:flex;align-items:center;gap:12px;border:1px solid rgba(67,184,255,.46);border-radius:17px;
  background:linear-gradient(145deg,rgba(8,18,25,.985),rgba(4,10,14,.99));
  box-shadow:0 22px 68px rgba(0,0,0,.68),0 0 30px rgba(67,184,255,.10);backdrop-filter:blur(20px);
}
.cvRestVisualV32.hidden{display:none!important}
.cvRestVisualV32.ready{border-color:rgba(94,227,165,.52);box-shadow:0 22px 68px rgba(0,0,0,.68),0 0 30px rgba(94,227,165,.11)}
.cvRestVisualCopy{min-width:0;flex:1}.cvRestVisualCopy small{display:block;color:#74ccff;font-size:8px;font-weight:900;letter-spacing:.15em;text-transform:uppercase}.cvRestVisualV32.ready .cvRestVisualCopy small{color:#7cebb3}
.cvRestVisualMain{display:flex;align-items:baseline;gap:9px;margin-top:2px}.cvRestVisualMain b{font:900 31px/1 Inter,system-ui,sans-serif;color:#eaf7ff;letter-spacing:-.04em}.cvRestVisualMain span{min-width:0;max-width:220px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;color:#93a5af;font-size:9px}
.cvRestVisualActions{display:flex;gap:6px}.cvRestVisualActions button{height:38px;border-radius:10px;border:1px solid #30434e;background:#0b151b;color:#c8d6dd;font-size:9px;font-weight:900;padding:0 10px}.cvRestVisualActions button:first-child{border-color:rgba(67,184,255,.25);color:#9bdcff}

@media(max-width:767px){
  .cvRestVisualV32{bottom:calc(78px + env(safe-area-inset-bottom));width:calc(100% - 18px);min-height:74px;padding:10px 10px 10px 13px}
  .cvRestVisualMain b{font-size:29px}.cvRestVisualMain span{max-width:132px}.cvRestVisualActions button{padding:0 8px}
}
@media(min-width:1024px){.cvRestVisualV32{left:calc(50% + 124px)}}
@media(min-width:1440px){.cvRestVisualV32{left:calc(50% + 134px)}}
</style>
'''

script = r'''
<script id="cv-client-workout-v32-js">
(function(){
  let visualRestEnd=0,visualRestTimer=null,visualRestName='',readyHideTimer=null;
  const exs=()=>{try{return typeof cvExercises==='function'?(cvExercises()||[]):[]}catch(_){return []}};
  const fmtRest=s=>{s=Math.max(0,Math.ceil(Number(s)||0));return String(Math.floor(s/60)).padStart(2,'0')+':'+String(s%60).padStart(2,'0')};

  function ensureVisualRest(){
    let el=document.getElementById('cvRestVisualV32');
    if(el)return el;
    el=document.createElement('div');el.id='cvRestVisualV32';el.className='cvRestVisualV32 hidden';
    el.setAttribute('role','status');el.setAttribute('aria-live','polite');
    el.innerHTML='<div class="cvRestVisualCopy"><small>DESCANSO ENTRE SERIES</small><div class="cvRestVisualMain"><b id="cvRestVisualTime">00:00</b><span id="cvRestVisualName"></span></div></div><div class="cvRestVisualActions"><button id="cvRestVisualPlus" type="button">+15 s</button><button id="cvRestVisualSkip" type="button">OMITIR</button></div>';
    document.body.appendChild(el);
    el.querySelector('#cvRestVisualPlus').onclick=()=>{visualRestEnd+=15000;syncVisualRest();try{document.querySelector('#cvRestDock .cvRestPlus')?.click()}catch(_){}};
    el.querySelector('#cvRestVisualSkip').onclick=()=>{hideVisualRest();try{document.querySelector('#cvRestDock .cvRestSkip')?.click()}catch(_){}};
    return el;
  }
  function hideVisualRest(){clearInterval(visualRestTimer);visualRestTimer=null;visualRestEnd=0;clearTimeout(readyHideTimer);const el=ensureVisualRest();el.classList.add('hidden');el.classList.remove('ready')}
  function syncVisualRest(){
    if(!visualRestEnd)return;
    const el=ensureVisualRest(),left=Math.max(0,Math.ceil((visualRestEnd-Date.now())/1000));
    const t=el.querySelector('#cvRestVisualTime'),n=el.querySelector('#cvRestVisualName');if(t)t.textContent=fmtRest(left);if(n)n.textContent=visualRestName;
    if(left<=0){clearInterval(visualRestTimer);visualRestTimer=null;visualRestEnd=0;el.classList.add('ready');if(t)t.textContent='LISTO';if(n)n.textContent='Continúa con la siguiente serie';clearTimeout(readyHideTimer);readyHideTimer=setTimeout(()=>el.classList.add('hidden'),1800)}
  }
  function showVisualRest(seconds,name){
    const sec=Math.max(1,Math.round(Number(seconds)||0));if(!sec)return;
    clearInterval(visualRestTimer);clearTimeout(readyHideTimer);visualRestEnd=Date.now()+sec*1000;visualRestName=String(name||'');
    const el=ensureVisualRest();el.classList.remove('hidden','ready');syncVisualRest();visualRestTimer=setInterval(syncVisualRest,250);
  }

  function workoutState(){
    const exercises=exs(),cards=[...document.querySelectorAll('.cvHevyExercise')];let currentFound=false,totalSets=0,doneSets=0,doneExercises=0;
    cards.forEach((card,i)=>{const e=exercises[i],sets=Array.isArray(e?.sets)?e.sets:[],rows=[...card.querySelectorAll('.cvSetRow')],total=sets.length||rows.length,done=sets.length?sets.filter(s=>s.completed).length:rows.filter(r=>r.classList.contains('done')).length,complete=total>0&&done===total,current=!complete&&!currentFound;if(current)currentFound=true;totalSets+=total;doneSets+=done;if(complete)doneExercises++;
      card.classList.toggle('cvExerciseCurrent',current);card.classList.toggle('cvExerciseComplete',complete);card.classList.toggle('cvExercisePending',!complete);
      let badge=card.querySelector('.cvExerciseStatusV31');if(!badge){badge=document.createElement('span');badge.className='cvExerciseStatusV31';card.querySelector('.exerciseTop .grow')?.appendChild(badge)}if(badge){badge.className='cvExerciseStatusV31 '+(complete?'complete':current?'current':'pending');badge.textContent=complete?'COMPLETADO':current?'AHORA':'PENDIENTE'}
      rows.forEach((row,j)=>{const checked=sets[j]?.completed??row.classList.contains('done'),btn=row.querySelector('.cvSetCheck');row.classList.toggle('done',!!checked);if(btn){btn.classList.toggle('done',!!checked);btn.setAttribute('aria-pressed',checked?'true':'false')}});
    });
    const totalExercises=cards.length,pct=totalSets?Math.round(doneSets/totalSets*100):0,fill=document.querySelector('.cvWorkoutProgressFill');if(fill)fill.style.width=pct+'%';
    const copy=document.querySelector('.cvWorkoutProgressCopy');if(copy)copy.innerHTML='<span><b>'+doneSets+' / '+totalSets+'</b> series completadas</span><span><b>'+doneExercises+' / '+totalExercises+'</b> ejercicios · '+pct+'%</span>';
  }

  /* v25 is the final functional toggle in the current portal. Wrap it here so visual feedback cannot be overwritten. */
  if(typeof window.cvToggleSet==='function'){
    const baseToggle=window.cvToggleSet;
    window.cvToggleSet=async function(i,j){
      const before=!!exs()?.[i]?.sets?.[j]?.completed;
      const result=await baseToggle.apply(this,arguments);
      const e=exs()?.[i],after=!!e?.sets?.[j]?.completed;
      requestAnimationFrame(workoutState);
      if(!before&&after)showVisualRest(e?.rest_seconds||90,e?.name||'');
      if(before&&!after){/* Unchecking a past set must not create a rest countdown. */}
      return result;
    };
  }

  const baseRender=window.render;window.render=function(){const r=baseRender.apply(this,arguments);requestAnimationFrame(workoutState);return r};
  document.addEventListener('visibilitychange',()=>{if(!document.hidden&&visualRestEnd)syncVisualRest()});
  window.addEventListener('pageshow',()=>{if(visualRestEnd)syncVisualRest()});
  requestAnimationFrame(workoutState);
})();
</script>
'''

portal = portal.replace("</body>", style + "\n" + script + "\n</body>", 1)

anchor = 'require(client, "cv-client-workout-v31", "client workout visual hierarchy")\n'
if anchor in contracts:
    contracts = contracts.replace(anchor, anchor + 'require(client, "cv-client-workout-v32", "client workout semantic colors")\nrequire(client, "cvRestVisualV32", "client visible rest timer")\n', 1)
else:
    # Keep the patch compatible if the validation script predates the v31 contract marker.
    tail = '\n# CV Coach client workout v32\nrequire(client, "cv-client-workout-v32", "client workout semantic colors")\nrequire(client, "cvRestVisualV32", "client visible rest timer")\n'
    contracts += tail

PORTAL.write_text(portal, encoding="utf-8")
CONTRACTS.write_text(contracts, encoding="utf-8")
print("CLIENT_WORKOUT_V32_PATCH_OK")
