from pathlib import Path
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parent
HTML = ROOT / "stable" / "index.html"
BUILD = ROOT / "stable" / "build.json"

text = HTML.read_text(encoding="utf-8")
MARKER = "<!-- cv-client-quality-v50: RIR-free athlete DOM + verified drafts + kg-reps units -->"

NEW_SET_PARSER = r'''  function cvSetFromInputs(i,j){
    const ex=cvExercises()[i],s=ex?.sets?.[j];if(!s)return null;
    const unit=ex.prescription_unit||'reps',w=document.getElementById('cvw_'+i+'_'+j),r=document.getElementById('cvr_'+i+'_'+j);
    const wt=unit==='reps'&&w&&w.value!==''?Number(w.value):null,target=r&&r.value!==''?Number(r.value):null;
    if(wt!=null&&!Number.isFinite(wt))return null;if(target!=null&&(!Number.isFinite(target)||target<0))return null;
    s.weight_kg=unit==='reps'?wt:null;if(unit==='seconds'){s.duration_seconds=target==null?null:Math.round(target);s.reps=null}else{s.reps=target==null?null:Math.round(target);s.duration_seconds=null}
    return {ex,s,unit,weight_kg:s.weight_kg,reps:s.reps,duration_seconds:s.duration_seconds,target}
  }'''

NEW_DRAFT_SAVE = r'''  window.cvSaveDraftSet=async function(i,j){
    readDraft(i,j);if(!workout?.sessionId)return true;
    const key=String(workout.dayId||'none')+'|'+i+'|'+j,locks=window.cvDraftSaveLocksV50||(window.cvDraftSaveLocksV50=new Map()),prior=locks.get(key)||Promise.resolve();
    const task=prior.catch(()=>{}).then(async()=>{
      const row=(document.getElementById('cvw_'+i+'_'+j)||document.getElementById('cvr_'+i+'_'+j))?.closest('.cvSetRow');
      row?.classList.add('cvSaving');row?.classList.remove('cvSaved','cvSaveError');
      const p=cvSetFromInputs(i,j);if(!p){row?.classList.remove('cvSaving');row?.classList.add('cvSaveError');return false}
      if(mode==='demo'){row?.classList.remove('cvSaving');row?.classList.add('cvSaved');setTimeout(()=>row?.classList.remove('cvSaved'),700);return true}
      try{
        if(!p.s.set_log_id){
          if(!p.ex?.session_exercise_id)throw new Error('session exercise missing');
          const lookup=await sb.from('set_logs').select('id').eq('session_exercise_id',p.ex.session_exercise_id).eq('set_number',p.s.set_number).maybeSingle();
          if(lookup.error)throw lookup.error;if(lookup.data?.id)p.s.set_log_id=lookup.data.id;
        }
        if(!p.s.set_log_id)throw new Error('draft set log missing');
        const body=p.unit==='seconds'?{weight_kg:null,reps:null,duration_seconds:p.duration_seconds,source:'manual'}:{weight_kg:p.weight_kg,reps:p.reps,duration_seconds:null,source:'manual'};
        const saved=await sb.from('set_logs').update(body).eq('id',p.s.set_log_id).select('id').maybeSingle();
        if(saved.error)throw saved.error;if(!saved.data?.id)throw new Error('draft update was not confirmed');
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
      const unit=ex.prescription_unit||'reps',wi=document.getElementById('cvw_'+i+'_'+j),ri=document.getElementById('cvr_'+i+'_'+j),w=unit==='reps'&&wi&&wi.value!==''?Number(wi.value):null,performed=ri&&ri.value!==''?Math.round(Number(ri.value)):null;
      if(w!=null&&!Number.isFinite(w))return fail('Revisa el peso.');
      if(performed==null||!Number.isFinite(performed)||performed<=0)return fail(unit==='seconds'?'Ingresa los segundos realizados.':'Ingresa las repeticiones realizadas.');
      const next=!s.completed,old={w:s.weight_kg,r:s.reps,d:s.duration_seconds,c:s.completed};
      s.weight_kg=unit==='reps'?w:null;if(unit==='seconds'){s.duration_seconds=performed;s.reps=null}else{s.reps=performed;s.duration_seconds=null}s.completed=next;
      const row=(wi||ri)?.closest('.cvSetRow'),btn=row?.querySelector('.cvSetCheck');preBtn=btn||preBtn;
      row?.classList.toggle('done',next);btn?.classList.toggle('done',next);btn?.classList.add('cvSetCheckPendingV48');btn?.setAttribute('aria-pressed',next?'true':'false');
      updateStats();const card=row?.closest('.cvHevyExercise'),all=ex.sets||[],done=all.filter(x=>x.completed).length;card?.classList.toggle('cvExerciseHasProgress',done>0);card?.classList.toggle('cvExerciseComplete',all.length>0&&done===all.length);
      const rollback=()=>{s.weight_kg=old.w;s.reps=old.r;s.duration_seconds=old.d;s.completed=old.c;row?.classList.toggle('done',old.c);btn?.classList.toggle('done',old.c);btn?.classList.remove('cvSetCheckPendingV48');btn?.setAttribute('aria-pressed',old.c?'true':'false');updateStats();return false};
      const commitSuccess=()=>{btn?.classList.remove('cvSetCheckPendingV48');if(next)startRest(ex.rest_seconds||90,ex.name);document.dispatchEvent(new CustomEvent('cv:set-state',{detail:{i,j,completed:next}}));return true};
      if(mode==='demo')return commitSuccess();
      const body=unit==='seconds'?{weight_kg:null,reps:null,duration_seconds:performed,completed:next,completed_at:next?new Date().toISOString():null,source:'manual'}:{weight_kg:w,reps:performed,duration_seconds:null,completed:next,completed_at:next?new Date().toISOString():null,source:'manual'};
      try{
        if(!s.set_log_id){
          if(!ex.session_exercise_id)throw new Error('session exercise missing');
          const lookup=await sb.from('set_logs').select('id').eq('session_exercise_id',ex.session_exercise_id).eq('set_number',s.set_number).maybeSingle();
          if(lookup.error)throw lookup.error;if(lookup.data?.id)s.set_log_id=lookup.data.id;
        }
        if(!s.set_log_id)throw new Error('set log missing');
        const saved=await sb.from('set_logs').update(body).eq('id',s.set_log_id).select('id').maybeSingle();
        if(saved.error)throw saved.error;if(!saved.data?.id)throw new Error('set update was not confirmed');
        return commitSuccess();
      }catch(e){rollback();toast?.('No pude confirmar el guardado de la serie. Se revirtió para proteger tus datos.');console.warn('CV set persistence',e);return false}
    }finally{locks.delete(lockKey)}
  };
  const baseRender=window.render;'''


def replace_exact(old: str, new: str, label: str, expected: int = 1) -> None:
    global text
    count = text.count(old)
    if count != expected:
        raise SystemExit(f"quality v50 {label}: expected {expected}, got {count}")
    text = text.replace(old, new, expected)


if MARKER not in text:
    # Remove the obsolete CSS-only RIR layer. The athlete DOM is rebuilt below
    # without the internal coach metric, so hiding it after render is no longer needed.
    text, rir_style_count = re.subn(r'\n?<style id="cv-rir-v1-css">.*?</style>', '', text, count=1, flags=re.S)
    if rir_style_count != 1:
        raise SystemExit(f"quality v50 RIR style removal expected 1 block, got {rir_style_count}")

    old_hide_css = """/* Hide internal coach metric from client UI and keyboard flow. */
body.cvFastWorkout .cvRirInput,
body.cvFastWorkout .cvSetsHead span:nth-child(5){display:none!important}
"""
    replace_exact(old_hide_css, "", "obsolete RIR hide CSS")

    # The canonical parser used by draft/final persistence no longer reads or writes RIR.
    parser_pattern = re.compile(r"  function cvSetFromInputs\(i,j\)\{.*?\n  window\.cvSaveDraftSet=async\(i,j\)=>", re.S)
    text, parser_count = parser_pattern.subn(NEW_SET_PARSER + "\n  window.cvSaveDraftSet=async(i,j)=>", text, count=1)
    if parser_count != 1:
        raise SystemExit(f"quality v50 set parser replacement expected 1 block, got {parser_count}")

    # Remove RIR from the generated athlete table and prescription before the DOM exists.
    replace_exact(
        ",rir=e.rir_target!=null?'RIR '+e.rir_target:''",
        "",
        "RIR prescription variable",
    )
    replace_exact(
        "[total+' series',target&&(unit==='seconds'?target+' s':target+' reps'),rir]",
        "[total+' series',target&&(unit==='seconds'?target+' s':target+' reps')]",
        "RIR prescription chip",
    )
    replace_exact("<span>RIR</span>", "", "RIR table heading")

    rir_input_start = '''<input id="cvri_'+i+'_'+j+'" class="cvRirInput"'''
    rir_input_end = ''' aria-label="RIR real serie '+(j+1)+' de '+esc(e.name)+'">'''
    start = text.find(rir_input_start)
    if start < 0:
        raise SystemExit("quality v50 RIR input start not found")
    end = text.find(rir_input_end, start)
    if end < 0:
        raise SystemExit("quality v50 RIR input end not found")
    text = text[:start] + text[end + len(rir_input_end):]

    # Remove the post-render RIR stripping helper; it is now redundant.
    rir_helper_pattern = re.compile(r"  function stripRirPrescription\(el\)\{.*?\n  \}\n  function hideRir\(\)\{.*?\n  \}\n", re.S)
    text, helper_count = rir_helper_pattern.subn("", text, count=1)
    if helper_count != 1:
        raise SystemExit(f"quality v50 RIR helper removal expected 1 block, got {helper_count}")
    replace_exact("  function enhance(){hideRir();hero();aria()}", "  function enhance(){hero();aria()}", "athlete enhancer cleanup")

    # Draft saves now use the same row lookup and server confirmation discipline as final ✓ saves.
    draft_pattern = re.compile(r"  window\.cvSaveDraftSet=async function\(i,j\)\{.*?\n  \};\n\n  const baseOpen=window\.openDay;", re.S)
    text, draft_count = draft_pattern.subn(NEW_DRAFT_SAVE + "\n\n  const baseOpen=window.openDay;", text, count=1)
    if draft_count != 1:
        raise SystemExit(f"quality v50 draft-save replacement expected 1 block, got {draft_count}")

    # Replace the V49 final toggle with the RIR-free verified version.
    toggle_pattern = re.compile(r"  /\* active-session routing and resume are owned by the canonical session coordinator \(v46\)\. \*/\n  window\.cvToggleSet=async function\(i,j\)\{.*?\n  \};\n  const baseRender=window\.render;", re.S)
    text, toggle_count = toggle_pattern.subn(NEW_TOGGLE, text, count=1)
    if toggle_count != 1:
        raise SystemExit(f"quality v50 set-toggle replacement expected 1 block, got {toggle_count}")

    # Volume is work volume (load × reps), not just kilograms.
    session_volume_old = "Math.round(volume).toLocaleString('es-CL')+' kg</b>"
    session_volume_count = text.count(session_volume_old)
    if session_volume_count < 1:
        raise SystemExit("quality v50 session volume label not found")
    text = text.replace(session_volume_old, "Math.round(volume).toLocaleString('es-CL')+' kg·reps</b>")

    update_volume_old = "Math.round(vol).toLocaleString('es-CL')+' kg'"
    if update_volume_old in text:
        text = text.replace(update_volume_old, "Math.round(vol).toLocaleString('es-CL')+' kg·reps'")

    compact_old = "+' kg · <em"
    compact_count = text.count(compact_old)
    if compact_count < 1:
        raise SystemExit("quality v50 compact volume labels not found")
    text = text.replace(compact_old, "+' kg·reps · <em")

    if "</body>" not in text:
        raise SystemExit("quality v50: </body> missing")
    text = text.replace("</body>", MARKER + "\n</body>", 1)

required = [
    MARKER,
    "cvDraftSaveLocksV50",
    "draft update was not confirmed",
    "set update was not confirmed",
    "kg·reps · <em",
    "Math.round(volume).toLocaleString('es-CL')+' kg·reps</b>",
    "function enhance(){hero();aria()}",
]
for item in required:
    if item not in text:
        raise SystemExit(f"quality v50 required marker missing: {item}")

for forbidden in [
    "cvRirInput",
    "getElementById('cvri_'",
    "<span>RIR</span>",
    "RIR real serie",
    "function hideRir()",
    "rir:p.rir",
]:
    if forbidden in text:
        raise SystemExit(f"quality v50 client-only RIR marker remained: {forbidden}")

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
    "RIR removed from athlete DOM v50",
    "verified serialized draft persistence v50",
    "kg-reps workout volume semantics v50",
    "obsolete RIR post-render layer removed v50",
]:
    if patch not in patches:
        patches.append(patch)
metadata["patches"] = patches
BUILD.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"sha256": sha, "bytes": metadata["bytes"], "patches": patches[-4:]}, ensure_ascii=False))
