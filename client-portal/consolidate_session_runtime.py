from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parent
HTML = ROOT / "stable" / "index.html"
BUILD = ROOT / "stable" / "build.json"

text = HTML.read_text(encoding="utf-8")


def replace_once_or_keep(old: str, new: str, label: str) -> None:
    global text
    old_count = text.count(old)
    new_count = text.count(new)
    if old_count == 1:
        text = text.replace(old, new, 1)
        return
    if old_count == 0 and new_count >= 1:
        return
    raise SystemExit(f"{label}: unexpected state old={old_count} new={new_count}")


# V46 — session lifecycle consolidation.
# One coordinator owns: opening/resuming a day, starting a session, applying
# pre-start drafts and hydrating previous-session references. Async work is
# guarded by an epoch so a stale response can never overwrite another day.
replace_once_or_keep(
    "  const drafts={};\n  let restObserverHandle=null;\n  let restObservedEl=null;\n",
    "  const drafts={};\n  let restObserverHandle=null;\n  let restObservedEl=null;\n  let sessionEpoch=0,startPromise=null,historyPromise=null,resumePromise=null;\n",
    "session coordinator state",
)

replace_once_or_keep(
    "  function applyDraftsModel(){if(!workout?.liveExercises)return;for(const [k,d] of Object.entries(drafts)){const [i,j]=k.split('_').map(Number),ex=workout.liveExercises?.[i],s=ex?.sets?.[j];if(!s)continue;const unit=ex?.prescription_unit||'reps';if(unit==='reps'&&d.weight!==undefined&&d.weight!=='')s.weight_kg=Number(d.weight);if(d.reps!==undefined&&d.reps!==''){if(unit==='seconds'){s.duration_seconds=Math.round(Number(d.reps));s.reps=null;s.weight_kg=null}else{s.reps=Math.round(Number(d.reps));s.duration_seconds=null}}}}\n",
    "  function applyDraftsModel(target=workout){if(!target?.liveExercises)return;for(const [k,d] of Object.entries(drafts)){const [i,j]=k.split('_').map(Number),ex=target.liveExercises?.[i],s=ex?.sets?.[j];if(!s)continue;const unit=ex?.prescription_unit||'reps';if(unit==='reps'&&d.weight!==undefined&&d.weight!=='')s.weight_kg=Number(d.weight);if(d.reps!==undefined&&d.reps!==''){if(unit==='seconds'){s.duration_seconds=Math.round(Number(d.reps));s.reps=null;s.weight_kg=null}else{s.reps=Math.round(Number(d.reps));s.duration_seconds=null}}}}\n",
    "draft application target isolation",
)

old_history = """  async function hydrateHistory(){try{if(mode==='demo'||!workout?.liveExercises)return;const all=workout.liveExercises.flatMap(e=>Array.isArray(e.sets)?e.sets:[]),ids=[...new Set(all.map(s=>s.reference_set_log_id).filter(Boolean))];if(ids.length){const {data:rows,error}=await sb.from('set_logs').select('id,weight_kg,reps,duration_seconds,completed_at').in('id',ids);if(!error){const map=new Map((rows||[]).map(x=>[x.id,x]));for(const s of all){const ref=map.get(s.reference_set_log_id);if(ref){s.reference_weight_kg=ref.weight_kg;s.reference_reps=ref.reps;s.reference_duration_seconds=ref.duration_seconds;s.reference_completed_at=ref.completed_at}}}}workout.cvHistoryHydrated=true;render()}catch(e){console.warn('CV history',e)}}
"""
new_history = """  async function hydrateHistory(target=workout,epoch=sessionEpoch){
    try{
      if(!target)return false;
      if(mode==='demo'||!target.liveExercises){target.cvHistoryHydrated=true;return true}
      const sessionId=target.sessionId;if(!sessionId)return false;if(target.cvHistoryHydrated)return true;
      if(historyPromise?.sessionId===sessionId)return historyPromise.promise;
      const live=target.liveExercises,all=live.flatMap(e=>Array.isArray(e.sets)?e.sets:[]),ids=[...new Set(all.map(s=>s.reference_set_log_id).filter(Boolean))];
      const task=(async()=>{
        let rows=[];
        if(ids.length){const q=await sb.from('set_logs').select('id,weight_kg,reps,duration_seconds,completed_at').in('id',ids);if(q.error)throw q.error;rows=q.data||[]}
        if(epoch!==sessionEpoch||workout!==target||target.sessionId!==sessionId)return false;
        const map=new Map(rows.map(x=>[x.id,x]));for(const s of all){const ref=map.get(s.reference_set_log_id);if(ref){s.reference_weight_kg=ref.weight_kg;s.reference_reps=ref.reps;s.reference_duration_seconds=ref.duration_seconds;s.reference_completed_at=ref.completed_at}}
        target.cvHistoryHydrated=true;render();return true
      })();
      historyPromise={sessionId,promise:task};try{return await task}finally{if(historyPromise?.promise===task)historyPromise=null}
    }catch(e){console.warn('CV history',e);return false}
  }
"""
replace_once_or_keep(old_history, new_history, "race-safe history hydration")

old_wrappers = """  const baseRender=window.render;window.render=function(){const r=baseRender.apply(this,arguments);requestAnimationFrame(afterRender);return r};
  const baseStart=window.startWorkout;window.startWorkout=async function(){for(const inp of document.querySelectorAll('input[id^=\"cvw_\"],input[id^=\"cvr_\"]')){const m=inp.id.match(/^cv([wr])_(\\d+)_(\\d+)$/);if(m)readDraft(Number(m[2]),Number(m[3]))}await baseStart.apply(this,arguments);applyDraftsModel();if(mode!=='demo'&&workout?.sessionId&&!workout.cvHistoryHydrated)await hydrateHistory();else render();if(workout?.started&&typeof startTimer==='function')startTimer()};

  const baseSave=window.cvSaveDraftSet;window.cvSaveDraftSet=async function(i,j){readDraft(i,j);if(!workout?.sessionId)return true;const row=document.getElementById('cvw_'+i+'_'+j)?.closest('.cvSetRow');row?.classList.add('cvSaving');row?.classList.remove('cvSaved','cvSaveError');const ok=await baseSave.apply(this,arguments);row?.classList.remove('cvSaving');if(ok===false){row?.classList.add('cvSaveError');return false}row?.classList.add('cvSaved');sfx('save');setTimeout(()=>row?.classList.remove('cvSaved'),700);return true};

  const baseToggle=window.cvToggleSet;window.cvToggleSet=async function(i,j){readDraft(i,j);if(!workout?.sessionId){await window.startWorkout();applyDraftsModel();render();await new Promise(r=>requestAnimationFrame(()=>r()))}const ex=typeof window.cvExercises==='function'?window.cvExercises()?.[i]:null,s=ex?.sets?.[j],was=!!s?.completed;const result=await baseToggle.apply(this,arguments);const now=typeof window.cvExercises==='function'?!!window.cvExercises()?.[i]?.sets?.[j]?.completed:false;if(!was&&now){sfx('confirm')}return result};

  const baseOpen=window.openDay;window.openDay=function(id){Object.keys(drafts).forEach(k=>delete drafts[k]);const r=baseOpen.apply(this,arguments);if(mode!=='demo')setTimeout(()=>tryResume(id),70);return r};
  async function tryResume(dayId){try{if(!user?.id||!workout||workout.dayId!==dayId||workout.sessionId)return;const {data:open,error}=await sb.from('workout_sessions').select('id,started_at,status').eq('client_id',user.id).eq('program_day_id',dayId).eq('status','in_progress').order('started_at',{ascending:false}).limit(1).maybeSingle();if(error||!open||workout.sessionId)return;const {data:r,error:e}=await sb.functions.invoke('start-workout',{body:{program_day_id:dayId}});if(e||r?.error)return;workout.sessionId=r?.session_id||open.id;workout.liveExercises=Array.isArray(r?.exercises)?r.exercises:null;workout.started=r?.started_at?new Date(r.started_at).getTime():new Date(open.started_at).getTime();workout.cvResumed=true;workout.cvHistoryHydrated=false;await hydrateHistory();if(typeof startTimer==='function')startTimer();toast?.('Sesión recuperada · continuamos donde quedaste')}catch(e){console.warn('CV resume',e)}}
"""
new_wrappers = """  let nightSyncQueued=false;
  function queueNightSync(){if(nightSyncQueued)return;nightSyncQueued=true;requestAnimationFrame(()=>{nightSyncQueued=false;afterRender()})}
  const nightObserver=new MutationObserver(queueNightSync);nightObserver.observe(document.getElementById('content')||document.body,{childList:true});queueNightSync();

  async function loadSession(target,dayId,epoch,{resuming=false,fallbackStarted=null}={}){
    if(!target||epoch!==sessionEpoch||workout!==target||target.dayId!==dayId)return false;
    if(mode==='demo'){
      target.sessionId='demo';target.started=Date.now();target.liveExercises=cvPrestartExercises();target.liveExercises.forEach((e,ei)=>e.sets.forEach((s,si)=>s.set_log_id='demo_'+ei+'_'+si));target.cvHistoryHydrated=true;applyDraftsModel(target);render();if(typeof startTimer==='function')startTimer();return true
    }
    const {data:r,error}=await sb.functions.invoke('start-workout',{body:{program_day_id:dayId}});if(error||r?.error)throw new Error(r?.detail||r?.error||error.message);
    if(epoch!==sessionEpoch||workout!==target||target.dayId!==dayId)return false;
    target.sessionId=r?.session_id||target.sessionId||null;target.liveExercises=Array.isArray(r?.exercises)?r.exercises:null;target.started=r?.started_at?new Date(r.started_at).getTime():(fallbackStarted?new Date(fallbackStarted).getTime():Date.now());if(!target.sessionId)throw new Error('No se recibió la sesión de entrenamiento.');target.cvResumed=!!(resuming||r?.idempotent);target.cvHistoryHydrated=false;applyDraftsModel(target);await hydrateHistory(target,epoch);if(epoch!==sessionEpoch||workout!==target)return false;if(typeof startTimer==='function')startTimer();return true
  }

  window.startWorkout=async function(){
    const target=workout,dayId=target?.dayId,epoch=sessionEpoch;if(!target||!dayId)return false;if(target.sessionId)return true;if(startPromise?.target===target)return startPromise.promise;
    for(const inp of document.querySelectorAll('input[id^=\"cvw_\"],input[id^=\"cvr_\"]')){const m=inp.id.match(/^cv([wr])_(\\d+)_(\\d+)$/);if(m)readDraft(Number(m[2]),Number(m[3]))}
    const task=(async()=>{try{const ok=await loadSession(target,dayId,epoch);if(ok)toast?.(target.cvResumed?'Sesión reanudada':'Entrenamiento iniciado');return ok}catch(e){if(epoch===sessionEpoch&&workout===target)toast?.(e.message||String(e));return false}})();startPromise={target,promise:task};try{return await task}finally{if(startPromise?.promise===task)startPromise=null}
  };

  window.cvSaveDraftSet=async function(i,j){
    readDraft(i,j);if(!workout?.sessionId)return true;const row=(document.getElementById('cvw_'+i+'_'+j)||document.getElementById('cvr_'+i+'_'+j))?.closest('.cvSetRow');row?.classList.add('cvSaving');row?.classList.remove('cvSaved','cvSaveError');const p=cvSetFromInputs(i,j);if(!p){row?.classList.remove('cvSaving');row?.classList.add('cvSaveError');return false}
    if(mode==='demo'||!p.s.set_log_id){row?.classList.remove('cvSaving');row?.classList.add('cvSaved');setTimeout(()=>row?.classList.remove('cvSaved'),700);return true}
    const body=p.unit==='seconds'?{weight_kg:null,reps:null,duration_seconds:p.duration_seconds,rir:p.rir,source:'manual'}:{weight_kg:p.weight_kg,reps:p.reps,duration_seconds:null,rir:p.rir,source:'manual'};const {error}=await sb.from('set_logs').update(body).eq('id',p.s.set_log_id);row?.classList.remove('cvSaving');if(error){row?.classList.add('cvSaveError');toast?.('No pude guardar la serie: '+error.message);return false}row?.classList.add('cvSaved');sfx('save');setTimeout(()=>row?.classList.remove('cvSaved'),700);return true
  };

  const baseOpen=window.openDay;
  window.openDay=async function(id){
    const epoch=++sessionEpoch;historyPromise=null;startPromise=null;resumePromise=null;Object.keys(drafts).forEach(k=>delete drafts[k]);let effective=id,open=null;
    if(mode==='real'&&user?.id){try{const q=await sb.from('workout_sessions').select('id,program_day_id,started_at,status').eq('client_id',user.id).eq('status','in_progress').order('started_at',{ascending:false}).limit(1).maybeSingle();if(q.error)throw q.error;if(epoch!==sessionEpoch)return false;open=q.data||null;if(open?.program_day_id){effective=open.program_day_id;if(effective!==id)toast?.('Ya tenías una sesión activa · la recuperé')}}catch(e){console.warn('CV active session lookup',e)}}
    if(epoch!==sessionEpoch)return false;const result=baseOpen.call(this,effective);const target=workout;if(open?.program_day_id===effective&&target?.dayId===effective){const task=(async()=>{try{const ok=await loadSession(target,effective,epoch,{resuming:true,fallbackStarted:open.started_at});if(ok)toast?.('Sesión recuperada · continuamos donde quedaste');return ok}catch(e){console.warn('CV resume',e);return false}})();resumePromise=task;try{await task}finally{if(resumePromise===task)resumePromise=null}}return result
  };

  document.addEventListener('cv:set-state',event=>{if(event.detail?.completed)sfx('confirm')});
"""
replace_once_or_keep(old_wrappers, new_wrappers, "canonical session coordinator")

# v25 used to perform a second active-session lookup before delegating to the
# older openDay wrapper. The coordinator above already owns that lookup/resume.
old_v25_open = "  const oldOpen=window.openDay;window.openDay=async function(id){try{if(mode==='real'&&user?.id){const q=await sb.from('workout_sessions').select('program_day_id,started_at').eq('client_id',user.id).eq('status','in_progress').order('started_at',{ascending:false}).limit(1).maybeSingle();if(q.data?.program_day_id&&q.data.program_day_id!==id){id=q.data.program_day_id;toast?.('Ya tenías una sesión activa · la recuperé')}}}catch(e){console.warn('v25 active workout',e)}return oldOpen.call(this,id)};"
new_v25_open = "  /* active-session routing and resume are owned by the canonical session coordinator (v46). */"
replace_once_or_keep(old_v25_open, new_v25_open, "remove duplicate v25 active-session lookup")

marker = "<!-- cv-session-runtime-v46: canonical start/resume/drafts/history coordinator with stale-response guards -->"
if marker not in text:
    if "</body>" not in text:
        raise SystemExit("session runtime marker: </body> missing")
    text = text.replace("</body>", marker + "\n</body>", 1)

required = [
    "sessionEpoch=0",
    "async function loadSession(",
    "historyPromise?.sessionId===sessionId",
    "window.startWorkout=async function()",
    "window.cvSaveDraftSet=async function(i,j)",
    "active-session routing and resume are owned by the canonical session coordinator",
    "cv:set-state",
    marker,
]
for item in required:
    if item not in text:
        raise SystemExit(f"session runtime required marker missing: {item}")

forbidden = [
    "setTimeout(()=>tryResume(id),70)",
    "async function tryResume(dayId)",
    "const baseStart=window.startWorkout",
    "const baseSave=window.cvSaveDraftSet",
    "const baseToggle=window.cvToggleSet",
    "const oldOpen=window.openDay;window.openDay=async function(id){try{if(mode==='real'",
]
for item in forbidden:
    if item in text:
        raise SystemExit(f"session runtime duplicate/legacy owner remained: {item}")

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
    "canonical session lifecycle coordinator v46",
    "race-safe session/history hydration",
    "single active-session lookup on open day",
    "direct draft persistence owner",
]:
    if patch not in patches:
        patches.append(patch)
metadata["patches"] = patches
BUILD.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"sha256": sha, "bytes": metadata["bytes"], "patches": metadata["patches"][-4:]}, ensure_ascii=False))
