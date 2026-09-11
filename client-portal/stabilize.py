from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "index.html"
OUT_DIR = ROOT / "stable"
OUT = OUT_DIR / "index.html"

text = SRC.read_text(encoding="utf-8")


def replace_once_or_keep(old: str, new: str, label: str) -> None:
    global text
    old_count = text.count(old)
    new_count = text.count(new)
    if old_count == 1:
        text = text.replace(old, new, 1)
        return
    if old_count == 0 and new_count >= 1:
        return
    raise SystemExit(f"{label}: unexpected source state old={old_count} new={new_count}")


replace_once_or_keep(
    "<title>CV Coach · Cliente Premium Preview</title>",
    "<title>CV Coach · Cliente</title>",
    "production title",
)

old_today = "const today=()=>new Date().toISOString().slice(0,10);"
new_today = """const dateInChile=()=>{const parts=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Santiago',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(new Date());const get=t=>parts.find(x=>x.type===t)?.value||'';return `${get('year')}-${get('month')}-${get('day')}`};\nconst today=()=>dateInChile();"""
replace_once_or_keep(old_today, new_today, "Chile local date")

old_habit = "window.logHabitInput=id=>{const el=document.getElementById('hv_'+id);const v=Number(el?.value);if(!Number.isFinite(v))return toast('Ingresa un valor.');logHabit(id,v,null)}"
new_habit = "window.logHabitInput=id=>{const el=document.getElementById('hv_'+id);const raw=el?.value?.trim()??'';if(raw==='')return toast('Ingresa un valor.');const v=Number(raw);if(!Number.isFinite(v))return toast('Ingresa un valor válido.');logHabit(id,v,null)}"
replace_once_or_keep(old_habit, new_habit, "empty numeric habit guard")

# V42 runtime hardening: historical audio helpers and rest observers from older
# workout layers are not needed by the current client timer. Production keeps
# normal UI confirmation/menu/save sounds, but automatic rest-related audio is
# removed. Haptics are preserved.
old_sfx = "function sfx(k){if(!soundEnabled)return;const c=audio();if(!c)return;if(k==='menu'){tone(c,620,.045,0,.018);tone(c,840,.05,.04,.014,'triangle')}else if(k==='confirm'){tone(c,523,.065,0,.027,'triangle');tone(c,659,.07,.045,.025,'triangle');tone(c,784,.10,.09,.022,'triangle')}else if(k==='rest'){tone(c,330,.06,0,.023,'square');tone(c,495,.065,.055,.021,'square')}else if(k==='ready'){tone(c,659,.075,0,.03,'triangle');tone(c,784,.08,.07,.03,'triangle');tone(c,988,.16,.14,.028,'triangle')}else if(k==='save'){tone(c,740,.035,0,.013,'triangle')}}"
new_sfx = "function sfx(k){if(!soundEnabled)return;const c=audio();if(!c)return;if(k==='menu'){tone(c,620,.045,0,.018);tone(c,840,.05,.04,.014,'triangle')}else if(k==='confirm'){tone(c,523,.065,0,.027,'triangle');tone(c,659,.07,.045,.025,'triangle');tone(c,784,.10,.09,.022,'triangle')}else if(k==='save'){tone(c,740,.035,0,.013,'triangle')}}"
replace_once_or_keep(old_sfx, new_sfx, "remove automatic rest audio categories")

replace_once_or_keep(
    "if(!was&&now){sfx('confirm');setTimeout(()=>sfx('rest'),120)}",
    "if(!was&&now){sfx('confirm')}",
    "remove automatic rest-start sound",
)

old_premium_audio = """  let cvPremiumAC=null,lastSecond=null,lastFinished=false;
  function soundOn(){return localStorage.getItem('cv_sound_enabled')!=='0'}
  function ctx(){try{if(!cvPremiumAC){const C=window.AudioContext||window.webkitAudioContext;if(!C)return null;cvPremiumAC=new C()}if(cvPremiumAC.state==='suspended')cvPremiumAC.resume().catch(()=>{});return cvPremiumAC}catch(_){return null}}
  function tone(f,d,delay=0,vol=.018,type='triangle'){if(!soundOn())return;const c=ctx();if(!c)return;try{const o=c.createOscillator(),g=c.createGain(),t=c.currentTime+delay;o.type=type;o.frequency.setValueAtTime(f,t);g.gain.setValueAtTime(.0001,t);g.gain.exponentialRampToValueAtTime(vol,t+.006);g.gain.exponentialRampToValueAtTime(.0001,t+d);o.connect(g).connect(c.destination);o.start(t);o.stop(t+d+.02)}catch(_){}}
  function tick(){tone(780,.042,0,.012,'square')}
  function ready(){tone(660,.08,0,.025);tone(825,.09,.065,.024);tone(990,.15,.13,.022)}
"""
new_premium_audio = """  let lastSecond=null,lastFinished=false;
"""
replace_once_or_keep(old_premium_audio, new_premium_audio, "remove dead premium timer audio helpers")

old_premium_rest_watch = """  function restWatch(){const d=document.getElementById('cvRestDock'),t=document.getElementById('cvRestTime');if(!d||!t)return;const parts=(t.textContent||'').split(':').map(Number);if(parts.length!==2||parts.some(n=>!Number.isFinite(n)))return;const sec=parts[0]*60+parts[1],active=!d.classList.contains('hidden')&&!d.classList.contains('done');d.classList.toggle('cvLastTen',active&&sec>0&&sec<=10);if(active&&sec>0&&sec<=10&&sec!==lastSecond){lastSecond=sec;try{navigator.vibrate?.(18)}catch(_){}}if(active&&sec===0&&!lastFinished){lastFinished=true;try{navigator.vibrate?.([90,55,120])}catch(_){}}if(!active){lastSecond=null;lastFinished=false;d.classList.remove('cvLastTen')}}
  const baseRender=window.render;window.render=function(){const r=baseRender.apply(this,arguments);requestAnimationFrame(()=>{decorateCards();restWatch()});return r};
  setInterval(restWatch,250);
  requestAnimationFrame(decorateCards);
"""
new_premium_rest_watch = """  const baseRender=window.render;window.render=function(){const r=baseRender.apply(this,arguments);requestAnimationFrame(decorateCards);return r};
  requestAnimationFrame(decorateCards);
"""
replace_once_or_keep(old_premium_rest_watch, new_premium_rest_watch, "remove duplicate legacy rest observer")

# V43 audit: the v25 override became the final functional set logger. The old
# version treated timed prescriptions (for example, planchas) as repetitions.
# Make the final logger unit-aware so seconds are written to duration_seconds and
# never leak into reps/weight fields.
old_v25_toggle = """  window.cvToggleSet=async function(i,j){
    if(!workout?.sessionId){await window.startWorkout();if(!workout?.sessionId)return}
    const ex=typeof window.cvExercises==='function'?window.cvExercises()?.[i]:null,s=ex?.sets?.[j];if(!ex||!s)return;
    const wi=document.getElementById('cvw_'+i+'_'+j),ri=document.getElementById('cvr_'+i+'_'+j),riri=document.getElementById('cvri_'+i+'_'+j),w=wi&&wi.value!==''?Number(wi.value):null,r=ri&&ri.value!==''?Math.round(Number(ri.value)):null,rir=riri&&riri.value!==''?Number(riri.value):null;if(w!=null&&!Number.isFinite(w))return toast?.('Revisa el peso.');if(r==null||!Number.isFinite(r)||r<=0)return toast?.('Ingresa las repeticiones realizadas.');if(rir!=null&&(!Number.isFinite(rir)||rir<0||rir>10))return toast?.('RIR debe estar entre 0 y 10.');
    const next=!s.completed,old={w:s.weight_kg,r:s.reps,rir:s.rir,c:s.completed};s.weight_kg=w;s.reps=r;s.rir=rir;s.completed=next;
    const row=wi?.closest('.cvSetRow'),btn=row?.querySelector('.cvSetCheck');row?.classList.toggle('done',next);btn?.classList.toggle('done',next);updateStats();const card=row?.closest('.cvHevyExercise'),all=ex.sets||[],done=all.filter(x=>x.completed).length;card?.classList.toggle('cvExerciseHasProgress',done>0);card?.classList.toggle('cvExerciseComplete',all.length>0&&done===all.length);if(next)startRest(ex.rest_seconds||90,ex.name);
    if(mode==='demo'||!s.set_log_id)return;
    try{const {error}=await sb.from('set_logs').update({weight_kg:w,reps:r,rir,completed:next,completed_at:next?new Date().toISOString():null,source:'manual'}).eq('id',s.set_log_id);if(error)throw error}catch(e){s.weight_kg=old.w;s.reps=old.r;s.rir=old.rir;s.completed=old.c;row?.classList.toggle('done',old.c);btn?.classList.toggle('done',old.c);updateStats();if(next)stopRest();toast?.('No pude guardar la serie. Se revirtió para proteger tus datos.')}
  };
"""
new_v25_toggle = """  window.cvToggleSet=async function(i,j){
    if(!workout?.sessionId){await window.startWorkout();if(!workout?.sessionId)return}
    const ex=typeof window.cvExercises==='function'?window.cvExercises()?.[i]:null,s=ex?.sets?.[j];if(!ex||!s)return;
    const unit=ex.prescription_unit||'reps',wi=document.getElementById('cvw_'+i+'_'+j),ri=document.getElementById('cvr_'+i+'_'+j),riri=document.getElementById('cvri_'+i+'_'+j),w=unit==='reps'&&wi&&wi.value!==''?Number(wi.value):null,performed=ri&&ri.value!==''?Math.round(Number(ri.value)):null,rir=riri&&riri.value!==''?Number(riri.value):null;if(w!=null&&!Number.isFinite(w))return toast?.('Revisa el peso.');if(performed==null||!Number.isFinite(performed)||performed<=0)return toast?.(unit==='seconds'?'Ingresa los segundos realizados.':'Ingresa las repeticiones realizadas.');if(rir!=null&&(!Number.isFinite(rir)||rir<0||rir>10))return toast?.('RIR debe estar entre 0 y 10.');
    const next=!s.completed,old={w:s.weight_kg,r:s.reps,d:s.duration_seconds,rir:s.rir,c:s.completed};s.weight_kg=unit==='reps'?w:null;if(unit==='seconds'){s.duration_seconds=performed;s.reps=null}else{s.reps=performed;s.duration_seconds=null}s.rir=rir;s.completed=next;
    const row=(wi||ri)?.closest('.cvSetRow'),btn=row?.querySelector('.cvSetCheck');row?.classList.toggle('done',next);btn?.classList.toggle('done',next);updateStats();const card=row?.closest('.cvHevyExercise'),all=ex.sets||[],done=all.filter(x=>x.completed).length;card?.classList.toggle('cvExerciseHasProgress',done>0);card?.classList.toggle('cvExerciseComplete',all.length>0&&done===all.length);if(next)startRest(ex.rest_seconds||90,ex.name);
    if(mode==='demo'||!s.set_log_id)return;
    const body=unit==='seconds'?{weight_kg:null,reps:null,duration_seconds:performed,rir,completed:next,completed_at:next?new Date().toISOString():null,source:'manual'}:{weight_kg:w,reps:performed,duration_seconds:null,rir,completed:next,completed_at:next?new Date().toISOString():null,source:'manual'};
    try{const {error}=await sb.from('set_logs').update(body).eq('id',s.set_log_id);if(error)throw error}catch(e){s.weight_kg=old.w;s.reps=old.r;s.duration_seconds=old.d;s.rir=old.rir;s.completed=old.c;row?.classList.toggle('done',old.c);btn?.classList.toggle('done',old.c);updateStats();if(next)stopRest();toast?.('No pude guardar la serie. Se revirtió para proteger tus datos.')}
  };
"""
replace_once_or_keep(old_v25_toggle, new_v25_toggle, "unit-aware final set logger")

old_compact_apply = """  function applyCompactV40(){
    const active=workoutActiveViewV40(),started=active&&workoutStartedV40();
    document.body.classList.toggle('cvWorkoutPrestartV40',active&&!started);
    document.body.classList.toggle('cvWorkoutActiveV40',started);
    if(!active){removeStartCtaV40();return}
    const hero=document.querySelector('.cvWorkoutHeroV31');
    if(started){removeStartCtaV40();renderCompactTopV40()}else ensureStartCtaV40(hero);
  }
"""
new_compact_apply = """  function applyCompactV40(){
    const active=workoutActiveViewV40(),started=active&&workoutStartedV40();
    document.body.classList.toggle('cvWorkoutPrestartV40',active&&!started);
    document.body.classList.toggle('cvWorkoutActiveV40',started);
    if(!active){
      document.body.classList.remove('cvFastWorkout','cvWorkoutPrestartV40','cvWorkoutActiveV40');
      document.getElementById('cvRestVisualV32')?.classList.add('hidden');
      document.getElementById('cvRestDock')?.classList.add('hidden');
      if(!workout?.sessionId){try{sessionStorage.removeItem('cv_v25_rest')}catch(_){}}
      removeStartCtaV40();return
    }
    document.body.classList.add('cvFastWorkout');
    const hero=document.querySelector('.cvWorkoutHeroV31');
    if(started){removeStartCtaV40();renderCompactTopV40()}else ensureStartCtaV40(hero);
  }
"""
replace_once_or_keep(old_compact_apply, new_compact_apply, "clear workout-only state outside workout view")

replace_once_or_keep(
    "<!-- cv-rest-audio-v41: automated rest countdown audio disabled; haptics preserved -->\n</body>",
    "<!-- cv-rest-audio-v41: automated rest countdown audio disabled; haptics preserved -->\n<!-- cv-runtime-audit-v42: legacy rest audio and duplicate observer removed in stabilized production -->\n<!-- cv-runtime-audit-v43: timed-set persistence and workout-state cleanup hardened -->\n</body>",
    "runtime audit markers",
)

required = [
    "CV Coach",
    "sb.functions.invoke('start-workout'",
    "sb.functions.invoke('complete-workout'",
    "sb.functions.invoke('log-habit'",
    "sb.functions.invoke('log-nutrition-day'",
    "cvRestDock",
    "cvRestVisualV32",
    "cvOpenTechnique",
    "client_cv_state",
    "cv-client-header-v39",
    "cv-client-workout-compact-v40",
    "body.cvFastWorkout .cvRestDock{display:none!important}",
    "duration_seconds:performed",
    "document.body.classList.remove('cvFastWorkout'",
    "cv-runtime-audit-v42",
    "cv-runtime-audit-v43",
]
for marker in required:
    if marker not in text:
        raise SystemExit(f"required marker missing: {marker}")

forbidden = [
    "function tick(){tone(",
    "function ready(){tone(",
    "sfx('rest')",
    "sfx('ready')",
    "setInterval(restWatch,250)",
    "s.weight_kg=w;s.reps=r;s.rir=rir;s.completed=next",
]
for marker in forbidden:
    if marker in text:
        raise SystemExit(f"forbidden legacy runtime marker remained: {marker}")

if "cv-coach-sodcloud-1237.vercel.app" in text:
    raise SystemExit("protected Vercel client domain must not be embedded in stable portal")

OUT_DIR.mkdir(parents=True, exist_ok=True)
OUT.write_text(text, encoding="utf-8")
sha = hashlib.sha256(text.encode("utf-8")).hexdigest()
metadata = {
    "source": "client-portal/index.html",
    "output": "client-portal/stable/index.html",
    "bytes": len(text.encode("utf-8")),
    "sha256": sha,
    "patches": [
        "production title",
        "America/Santiago local date",
        "empty numeric habit guard",
        "automatic rest audio categories removed",
        "automatic rest-start sound removed",
        "dead premium timer audio helpers removed",
        "duplicate legacy rest observer removed",
        "timed prescriptions persisted as duration_seconds",
        "workout-only body state cleared outside workout view",
        "runtime audit markers v42-v43",
    ],
}
(OUT_DIR / "build.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps(metadata, ensure_ascii=False))
