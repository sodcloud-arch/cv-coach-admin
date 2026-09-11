from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parent
HTML = ROOT / "stable" / "index.html"
BUILD = ROOT / "stable" / "build.json"
MARKER = "<!-- cv-set-toggle-runtime-v56: self-contained demo + real set completion -->"

text = HTML.read_text(encoding="utf-8")

SCRIPT = r'''<script id="cv-set-toggle-runtime-v56-js">
(function(){
  if(window.CVSetToggleRuntimeV56?.version==='v56')return;

  function rowFor(i,j){
    return (document.getElementById('cvw_'+i+'_'+j)||document.getElementById('cvr_'+i+'_'+j))?.closest('.cvSetRow')||null
  }
  function parseSet(i,j){
    const ex=typeof window.cvExercises==='function'?window.cvExercises()?.[i]:null,s=ex?.sets?.[j];
    if(!ex||!s)throw new Error('No pude recuperar esta serie. Vuelve a abrir el entrenamiento.');
    const unit=ex.prescription_unit||'reps',w=document.getElementById('cvw_'+i+'_'+j),r=document.getElementById('cvr_'+i+'_'+j);
    const weight=unit==='reps'&&w&&w.value!==''?Number(w.value):null,performed=r&&r.value!==''?Number(r.value):null;
    if(weight!=null&&(!Number.isFinite(weight)||weight<0))throw new Error('Revisa el peso de la serie.');
    if(performed==null||!Number.isFinite(performed)||performed<=0)throw new Error(unit==='seconds'?'Ingresa los segundos realizados.':'Ingresa las repeticiones realizadas.');
    return {ex,s,unit,weight_kg:unit==='reps'?weight:null,reps:unit==='reps'?Math.round(performed):null,duration_seconds:unit==='seconds'?Math.round(performed):null}
  }
  async function persistSet(ex,s,body){
    if(mode==='demo')return {id:s?.set_log_id||'demo'};
    if(!s)throw new Error('set missing');
    if(!s.set_log_id){
      if(!ex?.session_exercise_id)throw new Error('session exercise missing');
      const lookup=await sb.from('set_logs').select('id').eq('session_exercise_id',ex.session_exercise_id).eq('set_number',s.set_number).maybeSingle();
      if(lookup.error)throw lookup.error;if(lookup.data?.id)s.set_log_id=lookup.data.id;
    }
    if(!s.set_log_id)throw new Error('set log missing');
    const saved=await sb.from('set_logs').update(body).eq('id',s.set_log_id).select('id').maybeSingle();
    if(saved.error)throw saved.error;if(!saved.data?.id)throw new Error('set update was not confirmed');
    return saved.data
  }
  function primeDemoSession(){
    if(mode!=='demo'||!workout||workout.sessionId)return false;
    const seed=typeof window.cvExercises==='function'?(window.cvExercises()||[]):[];
    workout.liveExercises=seed;
    workout.sessionId='demo';
    workout.started=Date.now();
    seed.forEach((ex,ei)=>(ex.sets||[]).forEach((s,si)=>{if(!s.set_log_id)s.set_log_id='demo_'+ei+'_'+si}));
    return true
  }
  function refreshStats(){
    try{
      const exs=typeof window.cvExercises==='function'?(window.cvExercises()||[]):[],sets=exs.flatMap(e=>e.sets||[]),done=sets.filter(s=>s.completed);
      const volume=exs.reduce((total,e)=>total+((e.prescription_unit||'reps')==='reps'?(e.sets||[]).filter(s=>s.completed).reduce((sum,s)=>sum+(Number(s.weight_kg)||0)*(Number(s.reps)||0),0):0),0);
      const stats=document.querySelectorAll('.cvSessionStat');
      if(stats[1]?.querySelector('b'))stats[1].querySelector('b').textContent=Math.round(volume).toLocaleString('es-CL')+' kg·reps';
      if(stats[2]?.querySelector('b'))stats[2].querySelector('b').textContent=done.length+' / '+sets.length
    }catch(e){}
  }
  function rollbackVisual(row,button,completed){
    row?.classList.toggle('done',!!completed);button?.classList.toggle('done',!!completed);button?.classList.remove('cvSetCheckPendingV48');button?.setAttribute('aria-pressed',completed?'true':'false')
  }
  function stopVisibleRest(){
    const dock=document.getElementById('cvRestVisualV32');if(!dock||dock.classList.contains('hidden'))return;
    const skip=document.getElementById('cvRestVisualSkip');if(skip)skip.click();else dock.classList.add('hidden')
  }

  window.cvToggleSet=async function(i,j){
    const dayAtTap=workout?.dayId,locks=window.cvSetToggleLocksV56||(window.cvSetToggleLocksV56=new Set()),lockKey=String(dayAtTap||'none')+'|'+i+'|'+j;
    if(locks.has(lockKey))return false;locks.add(lockKey);
    let row=rowFor(i,j),button=row?.querySelector('.cvSetCheck'),snapshot=null,p=null,demoPrimed=false;
    try{
      button?.classList.add('cvSetCheckPendingV48');
      demoPrimed=primeDemoSession();
      if(!workout?.sessionId){
        const started=await window.startWorkout();
        if(!started||!workout?.sessionId)throw new Error('No pude iniciar la rutina. Reintenta en unos segundos.');
      }
      if(!workout||workout.dayId!==dayAtTap)throw new Error('La rutina cambió mientras guardábamos la serie. Ábrela nuevamente.');

      row=rowFor(i,j);button=row?.querySelector('.cvSetCheck');button?.classList.add('cvSetCheckPendingV48');
      p=parseSet(i,j);snapshot={w:p.s.weight_kg,r:p.s.reps,d:p.s.duration_seconds,c:!!p.s.completed};
      const next=!snapshot.c;
      p.s.weight_kg=p.weight_kg;p.s.reps=p.reps;p.s.duration_seconds=p.duration_seconds;p.s.completed=next;
      row?.classList.toggle('done',next);button?.classList.toggle('done',next);button?.setAttribute('aria-pressed',next?'true':'false');refreshStats();

      const body=p.unit==='seconds'
        ?{weight_kg:null,reps:null,duration_seconds:p.duration_seconds,completed:next,completed_at:next?new Date().toISOString():null,source:'manual'}
        :{weight_kg:p.weight_kg,reps:p.reps,duration_seconds:null,completed:next,completed_at:next?new Date().toISOString():null,source:'manual'};
      await persistSet(p.ex,p.s,body);

      button?.classList.remove('cvSetCheckPendingV48');
      if(!next)stopVisibleRest();
      document.dispatchEvent(new CustomEvent('cv:set-state',{detail:{i,j,completed:next}}));
      refreshStats();
      if(demoPrimed&&typeof window.render==='function')window.render();
      return true
    }catch(error){
      if(p?.s&&snapshot){p.s.weight_kg=snapshot.w;p.s.reps=snapshot.r;p.s.duration_seconds=snapshot.d;p.s.completed=snapshot.c;rollbackVisual(row,button,snapshot.c);refreshStats()}
      else button?.classList.remove('cvSetCheckPendingV48');
      const message=String(error?.message||error||'No pude guardar la serie.');
      toast?.(message.includes('confirm')||message.includes('set log')||message.includes('session exercise')?'No pude confirmar el guardado de la serie. Se revirtió para proteger tus datos.':message);
      console.warn('CV set toggle v56',error);return false
    }finally{locks.delete(lockKey)}
  };

  window.CVSetToggleRuntimeV56={version:'v56',parseSet,persistSet,primeDemoSession,refreshStats};
})();
</script>'''

if MARKER not in text:
    for prerequisite in [
        "cv-client-runtime-v51",
        "cv-workout-regression-guard-v52",
        "cv-mobile-workout-reliability-v54",
        "cv-workout-sound-language-v55",
        "cvRestVisualV32",
        "window.cvToggleSet=async function(i,j)",
    ]:
        if prerequisite not in text:
            raise SystemExit(f"set toggle v56 prerequisite missing: {prerequisite}")
    if "</body>" not in text:
        raise SystemExit("set toggle v56: </body> missing")
    text = text.replace("</body>", SCRIPT + "\n" + MARKER + "\n</body>", 1)

required = [
    MARKER,
    'cv-set-toggle-runtime-v56-js',
    "window.cvToggleSet=async function(i,j)",
    "window.cvSetToggleLocksV56",
    "const started=await window.startWorkout()",
    "function parseSet(i,j)",
    "function persistSet(ex,s,body)",
    "function primeDemoSession()",
    "workout.liveExercises=seed",
    "if(demoPrimed&&typeof window.render==='function')window.render()",
    ".update(body).eq('id',s.set_log_id).select('id').maybeSingle()",
    "throw new Error('set update was not confirmed')",
    "document.dispatchEvent(new CustomEvent('cv:set-state'",
    "window.CVSetToggleRuntimeV56={version:'v56'",
]
for item in required:
    if item not in text:
        raise SystemExit(f"set toggle v56 required contract missing: {item}")

# The final v56 handler must be self-contained. The production bug fixed here
# came from calling helpers that lived inside a different IIFE and therefore
# were not visible from the final click handler in Safari/normal browsers.
start = text.rfind("  window.cvToggleSet=async function(i,j){")
end = text.find("\n\n  window.CVSetToggleRuntimeV56", start)
if start < 0 or end <= start:
    raise SystemExit("set toggle v56 could not isolate canonical handler")
handler = text[start:end]
for forbidden in ["cvSetFromInputs(", "cvPersistSetLogV51(", "startRest("]:
    if forbidden in handler:
        raise SystemExit(f"set toggle v56 final handler still depends on hidden helper: {forbidden}")

HTML.write_text(text, encoding="utf-8")
sha = hashlib.sha256(text.encode("utf-8")).hexdigest()
metadata = {}
if BUILD.exists():
    try:
        metadata = json.loads(BUILD.read_text(encoding="utf-8"))
    except Exception:
        metadata = {}
metadata["bytes"] = len(text.encode("utf-8"))
metadata["sha256"] = sha
patches = list(metadata.get("patches") or [])
for patch in [
    "self-contained set parser v56",
    "self-contained confirmed set persistence v56",
    "demo set completion repaired v56",
    "real client set completion repaired v56",
    "cross-IIFE runtime dependency removed v56",
    "atomic demo prestart promotion v56",
]:
    if patch not in patches:
        patches.append(patch)
metadata["patches"] = patches
BUILD.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"sha256": sha, "bytes": metadata["bytes"], "patches": metadata["patches"][-6:]}, ensure_ascii=False))
