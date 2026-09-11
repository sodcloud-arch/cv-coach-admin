from pathlib import Path
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parent
HTML = ROOT / "stable" / "index.html"
BUILD = ROOT / "stable" / "build.json"

text = HTML.read_text(encoding="utf-8")
MARKER = "<!-- cv-client-runtime-v51: single render bus + shared verified set persistence -->"


def replace_exact(old: str, new: str, label: str, expected: int = 1) -> None:
    global text
    count = text.count(old)
    if count != expected:
        raise SystemExit(f"runtime v51 {label}: expected {expected}, got {count}")
    text = text.replace(old, new, expected)


NEW_PERSIST_AND_DRAFT = r'''  async function cvPersistSetLogV51(ex,s,body,missingMessage,confirmMessage){
    if(mode==='demo')return {id:s?.set_log_id||'demo'};
    if(!s)throw new Error(missingMessage||'set missing');
    if(!s.set_log_id){
      if(!ex?.session_exercise_id)throw new Error('session exercise missing');
      const lookup=await sb.from('set_logs').select('id').eq('session_exercise_id',ex.session_exercise_id).eq('set_number',s.set_number).maybeSingle();
      if(lookup.error)throw lookup.error;if(lookup.data?.id)s.set_log_id=lookup.data.id;
    }
    if(!s.set_log_id)throw new Error(missingMessage||'set log missing');
    const saved=await sb.from('set_logs').update(body).eq('id',s.set_log_id).select('id').maybeSingle();
    if(saved.error)throw saved.error;if(!saved.data?.id)throw new Error(confirmMessage||'set update was not confirmed');
    return saved.data
  }

  window.cvSaveDraftSet=async function(i,j){
    readDraft(i,j);if(!workout?.sessionId)return true;
    const key=String(workout.dayId||'none')+'|'+i+'|'+j,locks=window.cvDraftSaveLocksV50||(window.cvDraftSaveLocksV50=new Map()),prior=locks.get(key)||Promise.resolve();
    const task=prior.catch(()=>{}).then(async()=>{
      const row=(document.getElementById('cvw_'+i+'_'+j)||document.getElementById('cvr_'+i+'_'+j))?.closest('.cvSetRow');
      row?.classList.add('cvSaving');row?.classList.remove('cvSaved','cvSaveError');
      const p=cvSetFromInputs(i,j);if(!p){row?.classList.remove('cvSaving');row?.classList.add('cvSaveError');return false}
      if(mode==='demo'){row?.classList.remove('cvSaving');row?.classList.add('cvSaved');setTimeout(()=>row?.classList.remove('cvSaved'),700);return true}
      try{
        const body=p.unit==='seconds'?{weight_kg:null,reps:null,duration_seconds:p.duration_seconds,source:'manual'}:{weight_kg:p.weight_kg,reps:p.reps,duration_seconds:null,source:'manual'};
        await cvPersistSetLogV51(p.ex,p.s,body,'draft set log missing','draft update was not confirmed');
        row?.classList.remove('cvSaving');row?.classList.add('cvSaved');sfx('save');setTimeout(()=>row?.classList.remove('cvSaved'),700);return true
      }catch(e){
        row?.classList.remove('cvSaving');row?.classList.add('cvSaveError');toast?.('No pude confirmar el guardado del borrador. El valor queda visible para que puedas reintentarlo.');console.warn('CV draft persistence',e);return false
      }
    });
    locks.set(key,task);try{return await task}finally{if(locks.get(key)===task)locks.delete(key)}
  };'''

NEW_TOGGLE = r'''  /* active-session routing and resume are owned by the canonical session coordinator (v46). */
  window.cvToggleSet=async function(i,j){
    const locks=window.cvSetToggleLocksV48||(window.cvSetToggleLocksV48=new Set()),dayAtTap=workout?.dayId,lockKey=String(dayAtTap||'none')+'|'+i+'|'+j;
    if(locks.has(lockKey))return false;locks.add(lockKey);
    let preBtn=(document.getElementById('cvw_'+i+'_'+j)||document.getElementById('cvr_'+i+'_'+j))?.closest('.cvSetRow')?.querySelector('.cvSetCheck');
    const fail=message=>{preBtn?.classList.remove('cvSetCheckPendingV48');if(message)toast?.(message);return false};
    try{
      preBtn?.classList.add('cvSetCheckPendingV48');
      if(!workout?.sessionId){const started=await window.startWorkout();if(!started||!workout?.sessionId)return fail('No pude iniciar la rutina. Reintenta en unos segundos.')}
      if(!workout||workout.dayId!==dayAtTap)return fail('La rutina cambió mientras guardábamos la serie. Ábrela nuevamente.');
      const ex=typeof window.cvExercises==='function'?window.cvExercises()?.[i]:null,s=ex?.sets?.[j];if(!ex||!s)return fail('No pude recuperar esta serie. Vuelve a abrir el entrenamiento.');
      const old={w:s.weight_kg,r:s.reps,d:s.duration_seconds,c:s.completed},p=cvSetFromInputs(i,j);if(!p)return fail('Revisa los valores de la serie.');
      const unit=p.unit,w=p.weight_kg,performed=unit==='seconds'?p.duration_seconds:p.reps;
      if(performed==null||!Number.isFinite(performed)||performed<=0){s.weight_kg=old.w;s.reps=old.r;s.duration_seconds=old.d;return fail(unit==='seconds'?'Ingresa los segundos realizados.':'Ingresa las repeticiones realizadas.')}
      const next=!old.c;s.completed=next;
      const wi=document.getElementById('cvw_'+i+'_'+j),ri=document.getElementById('cvr_'+i+'_'+j),row=(wi||ri)?.closest('.cvSetRow'),btn=row?.querySelector('.cvSetCheck');preBtn=btn||preBtn;
      row?.classList.toggle('done',next);btn?.classList.toggle('done',next);btn?.classList.add('cvSetCheckPendingV48');btn?.setAttribute('aria-pressed',next?'true':'false');
      updateStats();const card=row?.closest('.cvHevyExercise'),all=ex.sets||[],done=all.filter(x=>x.completed).length;card?.classList.toggle('cvExerciseHasProgress',done>0);card?.classList.toggle('cvExerciseComplete',all.length>0&&done===all.length);
      const rollback=()=>{s.weight_kg=old.w;s.reps=old.r;s.duration_seconds=old.d;s.completed=old.c;row?.classList.toggle('done',old.c);btn?.classList.toggle('done',old.c);btn?.classList.remove('cvSetCheckPendingV48');btn?.setAttribute('aria-pressed',old.c?'true':'false');updateStats();return false};
      const commitSuccess=()=>{btn?.classList.remove('cvSetCheckPendingV48');if(next)startRest(ex.rest_seconds||90,ex.name);document.dispatchEvent(new CustomEvent('cv:set-state',{detail:{i,j,completed:next}}));return true};
      if(mode==='demo')return commitSuccess();
      const body=unit==='seconds'?{weight_kg:null,reps:null,duration_seconds:performed,completed:next,completed_at:next?new Date().toISOString():null,source:'manual'}:{weight_kg:w,reps:performed,duration_seconds:null,completed:next,completed_at:next?new Date().toISOString():null,source:'manual'};
      try{
        await cvPersistSetLogV51(ex,s,body,'set log missing','set update was not confirmed');
        return commitSuccess();
      }catch(e){rollback();toast?.('No pude confirmar el guardado de la serie. Se revirtió para proteger tus datos.');console.warn('CV set persistence',e);return false}
    }finally{locks.delete(lockKey)}
  };'''

RENDER_BUS = r'''<script id="cv-render-bus-v51-js">
(function(){
  const previous=window.render;if(typeof previous!=='function'||previous.__cvRenderBusV51)return;
  let queued=false;
  function queueRendered(){if(queued)return;queued=true;requestAnimationFrame(()=>{queued=false;document.dispatchEvent(new CustomEvent('cv:rendered'))})}
  function cvRenderV51(){const result=previous.apply(this,arguments);queueRendered();return result}
  cvRenderV51.__cvRenderBusV51=true;window.render=cvRenderV51;queueRendered();
})();
</script>'''


if MARKER not in text:
    # One shared, verified persistence primitive is used by both draft saves and
    # final set toggles. This removes duplicate set-log lookup/update logic while
    # preserving locks, rollback and explicit server confirmation.
    draft_pattern = re.compile(r"  window\.cvSaveDraftSet=async function\(i,j\)\{.*?\n  \};\n\n  const baseOpen=window\.openDay;", re.S)
    text, draft_count = draft_pattern.subn(NEW_PERSIST_AND_DRAFT + "\n\n  const baseOpen=window.openDay;", text, count=1)
    if draft_count != 1:
        raise SystemExit(f"runtime v51 draft consolidation: expected 1, got {draft_count}")

    toggle_pattern = re.compile(r"  /\* active-session routing and resume are owned by the canonical session coordinator \(v46\)\. \*/\n  window\.cvToggleSet=async function\(i,j\)\{.*?\n  \};\n  const baseRender=window\.render;", re.S)
    text, toggle_count = toggle_pattern.subn(NEW_TOGGLE + "\n  const baseRender=window.render;", text, count=1)
    if toggle_count != 1:
        raise SystemExit(f"runtime v51 toggle consolidation: expected 1, got {toggle_count}")

    # Convert the remaining historical render wrappers to subscribers. V44/V46
    # already removed the workout wrappers they own; V51 finishes the active
    # chain so render has exactly one dispatcher instead of nested wrappers.
    replace_exact(
        "  const baseRender=window.render;window.render=function(){const r=baseRender.apply(this,arguments);requestAnimationFrame(tidyResume);return r};",
        "  document.addEventListener('cv:rendered',()=>requestAnimationFrame(tidyResume));",
        "resume post-render wrapper",
    )
    replace_exact(
        "  const baseRender=window.render;window.render=function(){const r=baseRender.apply(this,arguments);requestAnimationFrame(labels);return r};",
        "  document.addEventListener('cv:rendered',()=>requestAnimationFrame(labels));",
        "labels post-render wrapper",
    )
    replace_exact(
        " const baseRender=window.render;window.render=function(){const r=baseRender.apply(this,arguments);requestAnimationFrame(sync);return r};\n const baseNav=window.nav;window.nav=function(){const r=baseNav.apply(this,arguments);requestAnimationFrame(sync);return r};",
        " document.addEventListener('cv:rendered',()=>requestAnimationFrame(sync));",
        "navigation post-render wrappers",
    )
    replace_exact(
        "  const baseRender=window.render;window.render=function(){const r=baseRender.apply(this,arguments);requestAnimationFrame(()=>{setNav();fixHeader();decorateHistory();ensureDock()});return r};",
        "  document.addEventListener('cv:rendered',()=>requestAnimationFrame(()=>{setNav();fixHeader();decorateHistory();ensureDock()}));",
        "responsive QA post-render wrapper",
    )

    notification_old = "  const baseRender=window.render;window.render=function(){const result=baseRender.apply(this,arguments);if(view==='notifications'){const c=document.getElementById('content');if(c){c.innerHTML=notificationShell();document.getElementById('cvMarkAll').onclick=markAllNotifications;renderNotificationList()}}else if(view==='home'&&mode==='real'){refreshNotifications()}return result};"
    notification_new = "  function cvNotificationsAfterRenderV51(){if(view==='notifications'){const c=document.getElementById('content');if(c){c.innerHTML=notificationShell();document.getElementById('cvMarkAll').onclick=markAllNotifications;renderNotificationList()}}else if(view==='home'&&mode==='real'){refreshNotifications()}}\n  document.addEventListener('cv:rendered',cvNotificationsAfterRenderV51);"
    replace_exact(notification_old, notification_new, "notifications post-render wrapper")

    replace_exact(
        "  const baseRender=window.render;window.render=function(){const r=baseRender.apply(this,arguments);requestAnimationFrame(workoutState);return r};",
        "  document.addEventListener('cv:rendered',()=>requestAnimationFrame(workoutState));",
        "workout-state post-render wrapper",
    )
    replace_exact(
        "  const baseRender=window.render;\n  window.render=function(){const result=baseRender.apply(this,arguments);requestAnimationFrame(executionButtons);return result};",
        "  document.addEventListener('cv:rendered',()=>requestAnimationFrame(executionButtons));",
        "execution-buttons post-render wrapper",
    )
    replace_exact(
        "  const baseRender=window.render;window.render=function(){const r=baseRender.apply(this,arguments);requestAnimationFrame(mobileA11y);return r};",
        "  document.addEventListener('cv:rendered',()=>requestAnimationFrame(mobileA11y));",
        "mobile accessibility post-render wrapper",
    )
    replace_exact(
        "    const baseRender=window.render;\n    if(typeof baseRender==='function')window.render=function(){const result=baseRender.apply(this,arguments);requestAnimationFrame(applyHeaderV39);return result};",
        "    document.addEventListener('cv:rendered',()=>requestAnimationFrame(applyHeaderV39));",
        "header post-render wrapper",
    )

    # Install the single dispatcher after all subscribers have registered.
    if "</body>" not in text:
        raise SystemExit("runtime v51: </body> missing")
    text = text.replace("</body>", RENDER_BUS + "\n" + MARKER + "\n</body>", 1)

required = [
    MARKER,
    "cvPersistSetLogV51",
    "cvRenderV51.__cvRenderBusV51=true",
    "new CustomEvent('cv:rendered')",
    "document.addEventListener('cv:rendered',cvNotificationsAfterRenderV51)",
    "draft update was not confirmed",
    "set update was not confirmed",
    "cvDraftSaveLocksV50",
    "cvSetToggleLocksV48",
    "cv-client-quality-v50",
]
for item in required:
    if item not in text:
        raise SystemExit(f"runtime v51 required marker missing: {item}")

# V51's central contract: the canonical dispatcher is a named function
# assignment, so anonymous historical render wrappers must be fully gone.
render_assignments = len(re.findall(r"window\.render\s*=\s*function", text))
if render_assignments != 0:
    raise SystemExit(f"runtime v51 anonymous render wrappers remained: {render_assignments}")
if "baseRender=window.render" in text or "baseRender = window.render" in text:
    raise SystemExit("runtime v51 historical baseRender wrapper remained")
if "baseNav=window.nav" in text:
    raise SystemExit("runtime v51 historical baseNav wrapper remained")

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
    "shared verified set persistence v51",
    "single render event bus v51",
    "historical render wrappers removed v51",
    "runtime consolidation v51",
]:
    if patch not in patches:
        patches.append(patch)
metadata["patches"] = patches
BUILD.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"sha256": sha, "bytes": metadata["bytes"], "patches": metadata["patches"][-4:]}, ensure_ascii=False))
