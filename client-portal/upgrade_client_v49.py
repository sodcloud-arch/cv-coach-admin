from pathlib import Path
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parent
HTML = ROOT / "stable" / "index.html"
BUILD = ROOT / "stable" / "build.json"

text = HTML.read_text(encoding="utf-8")
MARKER = "<!-- cv-client-quality-v49: verified set persistence + coherent feedback history + timed records -->"

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
      const unit=ex.prescription_unit||'reps',wi=document.getElementById('cvw_'+i+'_'+j),ri=document.getElementById('cvr_'+i+'_'+j),riri=document.getElementById('cvri_'+i+'_'+j),w=unit==='reps'&&wi&&wi.value!==''?Number(wi.value):null,performed=ri&&ri.value!==''?Math.round(Number(ri.value)):null,rir=riri&&riri.value!==''?Number(riri.value):null;
      if(w!=null&&!Number.isFinite(w))return fail('Revisa el peso.');
      if(performed==null||!Number.isFinite(performed)||performed<=0)return fail(unit==='seconds'?'Ingresa los segundos realizados.':'Ingresa las repeticiones realizadas.');
      if(rir!=null&&(!Number.isFinite(rir)||rir<0||rir>10))return fail('RIR debe estar entre 0 y 10.');
      const next=!s.completed,old={w:s.weight_kg,r:s.reps,d:s.duration_seconds,rir:s.rir,c:s.completed};
      s.weight_kg=unit==='reps'?w:null;if(unit==='seconds'){s.duration_seconds=performed;s.reps=null}else{s.reps=performed;s.duration_seconds=null}s.rir=rir;s.completed=next;
      const row=(wi||ri)?.closest('.cvSetRow'),btn=row?.querySelector('.cvSetCheck');preBtn=btn||preBtn;
      row?.classList.toggle('done',next);btn?.classList.toggle('done',next);btn?.classList.add('cvSetCheckPendingV48');btn?.setAttribute('aria-pressed',next?'true':'false');
      updateStats();const card=row?.closest('.cvHevyExercise'),all=ex.sets||[],done=all.filter(x=>x.completed).length;card?.classList.toggle('cvExerciseHasProgress',done>0);card?.classList.toggle('cvExerciseComplete',all.length>0&&done===all.length);
      const rollback=()=>{s.weight_kg=old.w;s.reps=old.r;s.duration_seconds=old.d;s.rir=old.rir;s.completed=old.c;row?.classList.toggle('done',old.c);btn?.classList.toggle('done',old.c);btn?.classList.remove('cvSetCheckPendingV48');btn?.setAttribute('aria-pressed',old.c?'true':'false');updateStats();return false};
      const commitSuccess=()=>{btn?.classList.remove('cvSetCheckPendingV48');if(next)startRest(ex.rest_seconds||90,ex.name);document.dispatchEvent(new CustomEvent('cv:set-state',{detail:{i,j,completed:next}}));return true};
      if(mode==='demo')return commitSuccess();
      const body=unit==='seconds'?{weight_kg:null,reps:null,duration_seconds:performed,rir,completed:next,completed_at:next?new Date().toISOString():null,source:'manual'}:{weight_kg:w,reps:performed,duration_seconds:null,rir,completed:next,completed_at:next?new Date().toISOString():null,source:'manual'};
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

NEW_HISTORY = r'''function cvTrainingHistory(){const h=data?.trainingHistory||{},reps=Array.isArray(h.records)?h.records:[],timed=Array.isArray(h.duration_records)?h.duration_records:[],records=[...reps,...timed].sort((a,b)=>new Date(b.last_performed_at||0)-new Date(a.last_performed_at||0));return {error:h.error||'',summary:h.summary||{},sessions:Array.isArray(h.sessions)?h.sessions:[],records,durationRecords:timed}}
function cvTrainingNum(value){const n=Number(value);return Number.isFinite(n)?n:null}
function cvTrainingDate(value){if(!value)return '—';const d=new Date(String(value));return Number.isNaN(d.getTime())?'—':d.toLocaleDateString('es-CL',{timeZone:'America/Santiago'})}
function cvTrainingStatus(value){const s=String(value||'');return s==='completed'?{label:'COMPLETADO',cls:'good'}:s==='partial'?{label:'PARCIAL',cls:'warn'}:s==='abandoned'?{label:'CERRADO',cls:'red'}:{label:s.toUpperCase()||'—',cls:''}}
function cvHistoryChip(label,value,kind=''){if(value==null||value==='')return '';const cls=['good','warn','red'].includes(kind)?kind:'';return '<span class="cvHistoryChip '+cls+'">'+esc(label)+': '+esc(value)+'</span>'}
function cvTrainingDuration(value){const sec=Math.max(0,Math.round(Number(value)||0));if(sec<60)return sec+' s';const h=Math.floor(sec/3600),m=Math.floor((sec%3600)/60),s=sec%60;if(h)return h+' h '+String(m).padStart(2,'0')+' min';return m+' min'+(s?' '+s+' s':'')}
function cvPainContextText(context){if(!context||typeof context!=='object')return '';if(context.general===true)return 'Rutina completa';const names=Array.isArray(context.exercises)?context.exercises.map(x=>String(x?.exercise_name||'').trim()).filter(Boolean):[];return names.join(', ')}
function cvTrainingSessionCard(s){const meta=cvTrainingStatus(s.status),completion=cvTrainingNum(s.completion_pct),volume=cvTrainingNum(s.total_volume),seconds=cvTrainingNum(s.duration_seconds),difficulty=cvTrainingNum(s.difficulty_level),legacyEffort=cvTrainingNum(s.client_effort),legacyFatigue=cvTrainingNum(s.fatigue_score),legacyPain=cvTrainingNum(s.pain_score),hasPain=typeof s.had_pain==='boolean'?s.had_pain:null,painWhere=hasPain===true?cvPainContextText(s.pain_context):'';let feedback='';if(difficulty!=null)feedback+=cvHistoryChip('Dificultad',difficulty+' / 5',difficulty>=5?'warn':'');else{if(legacyEffort!=null)feedback+=cvHistoryChip('Esfuerzo histórico',legacyEffort+' / 10',legacyEffort>=9?'warn':'');if(legacyFatigue!=null)feedback+=cvHistoryChip('Fatiga histórica',legacyFatigue+' / 10',legacyFatigue>=8?'warn':'')}if(hasPain!==null)feedback+=cvHistoryChip('Molestia',hasPain?'Sí':'No',hasPain?'warn':'good');else if(legacyPain!=null)feedback+=cvHistoryChip('Dolor histórico',legacyPain+' / 10',legacyPain>=7?'red':legacyPain>=4?'warn':legacyPain===0?'good':'');return '<article class="card cvHistorySession"><div class="row"><div class="grow"><b>'+esc(s.day_name||s.program_name||'Entrenamiento')+'</b><div class="meta">'+esc(cvTrainingDate(s.finished_at||s.started_at))+(s.day_number!=null?' · Día '+esc(s.day_number):'')+'</div></div><span class="cvHistoryChip '+meta.cls+'">'+esc(meta.label)+'</span></div><div class="cvHistoryFeedback"><span class="cvHistoryChip">Finalización: '+esc(completion==null?'—':completion.toFixed(completion%1?1:0)+'%')+'</span>'+(volume==null?'':'<span class="cvHistoryChip">Volumen: '+esc(Math.round(volume).toLocaleString('es-CL'))+' kg·reps</span>')+(seconds==null?'':'<span class="cvHistoryChip">Duración: '+esc(cvTrainingDuration(seconds))+'</span>')+feedback+'</div>'+(painWhere?'<div class="hint" style="margin-top:8px"><b>Molestia en:</b> '+esc(painWhere)+'</div>':'')+(s.pain_notes?'<div class="hint" style="margin-top:5px"><b>Descripción:</b> '+esc(s.pain_notes)+'</div>':'')+(s.session_notes?'<div class="hint" style="margin-top:5px"><b>Comentario:</b> '+esc(s.session_notes)+'</div>':'')+'</article>'}
function cvTrainingRecordCard(r){const unit=String(r.prescription_unit||'reps');if(unit==='seconds'){const best=cvTrainingNum(r.best_duration_seconds??r.max_duration_seconds),sets=Math.max(0,Number(r.completed_sets)||0);return '<article class="card cvRecordCard"><h3>'+esc(r.exercise_name||'Ejercicio')+'</h3><div class="meta hint">Última ejecución: '+esc(cvTrainingDate(r.last_performed_at))+'</div><div class="cvRecordValues"><div class="cvRecordValue"><small>Mejor duración</small><b>'+(best==null?'—':esc(cvTrainingDuration(best)))+'</b><div class="hint">'+(best==null?'Sin duración completada':esc(cvTrainingDate(r.best_duration_at)))+'</div></div><div class="cvRecordValue"><small>Series completadas</small><b>'+esc(sets)+'</b><div class="hint">Trabajo por tiempo</div></div></div></article>'}const weight=cvTrainingNum(r.best_weight_kg),bestReps=cvTrainingNum(r.reps_at_best_weight),maxReps=cvTrainingNum(r.max_reps);return '<article class="card cvRecordCard"><h3>'+esc(r.exercise_name||'Ejercicio')+'</h3><div class="meta hint">Última ejecución: '+esc(cvTrainingDate(r.last_performed_at))+'</div><div class="cvRecordValues"><div class="cvRecordValue"><small>Mejor carga real</small><b>'+(weight==null?'—':esc(weight.toLocaleString('es-CL',{maximumFractionDigits:2}))+' kg')+'</b><div class="hint">'+(weight==null?'Sin carga externa registrada':esc(bestReps??'—')+' reps · '+esc(cvTrainingDate(r.best_weight_at)))+'</div></div><div class="cvRecordValue"><small>Máximo de reps</small><b>'+(maxReps==null?'—':esc(maxReps))+'</b><div class="hint">Series completadas: '+esc(r.completed_sets??0)+'</div></div></div></article>'}'''

if MARKER not in text:
    toggle_pattern = re.compile(r"  /\* active-session routing and resume are owned by the canonical session coordinator \(v46\)\. \*/\n  window\.cvToggleSet=async function\(i,j\)\{.*?\n  \};\n  const baseRender=window\.render;", re.S)
    text, toggle_count = toggle_pattern.subn(NEW_TOGGLE, text, count=1)
    if toggle_count != 1:
        raise SystemExit(f"quality v49 set-toggle replacement expected 1 block, got {toggle_count}")

    history_pattern = re.compile(r"function cvTrainingHistory\(\)\{.*?\}\nfunction cvTrainingNum\(value\)\{.*?\}\nfunction cvTrainingDate\(value\)\{.*?\}\nfunction cvTrainingStatus\(value\)\{.*?\}\nfunction cvHistoryChip\(label,value,kind=''\)\{.*?\}\nfunction cvTrainingSessionCard\(s\)\{.*?\}\nfunction cvTrainingRecordCard\(r\)\{.*?\}\n\nfunction cvChileLocalParts", re.S)
    text, history_count = history_pattern.subn(NEW_HISTORY + "\n\nfunction cvChileLocalParts", text, count=1)
    if history_count != 1:
        raise SystemExit(f"quality v49 history replacement expected 1 block, got {history_count}")

    old_label = 'Completion promedio'
    if old_label in text:
        text = text.replace(old_label, 'Finalización promedio', 1)

    old_volume = "'+esc(Math.round(volume).toLocaleString('es-CL'))+' kg</b></div><div class=\"cvResultMetric\"><small>XP obtenido</small>"
    new_volume = "'+esc(Math.round(volume).toLocaleString('es-CL'))+' kg·reps</b></div><div class=\"cvResultMetric\"><small>XP obtenido</small>"
    if old_volume in text:
        text = text.replace(old_volume, new_volume, 1)

    if "</body>" not in text:
        raise SystemExit("quality v49: </body> missing")
    text = text.replace("</body>", MARKER + "\n</body>", 1)

required = [
    MARKER,
    "set update was not confirmed",
    ".eq('session_exercise_id',ex.session_exercise_id).eq('set_number',s.set_number).maybeSingle()",
    "difficulty_level",
    "had_pain",
    "pain_context",
    "Finalización promedio",
    "duration_records",
    "Mejor duración",
    "kg·reps</b></div><div class=\"cvResultMetric\"><small>XP obtenido</small>",
]
for item in required:
    if item not in text:
        raise SystemExit(f"quality v49 required marker missing: {item}")

for forbidden in [
    "if(mode==='demo'||!s.set_log_id)return commitSuccess();",
    "cvHistoryChip('RPE',s.client_effort,'high')+cvHistoryChip('Fatiga',s.fatigue_score,'high')+cvHistoryChip('Dolor',s.pain_score,'pain')",
    'Completion promedio',
]:
    if forbidden in text:
        raise SystemExit(f"quality v49 legacy behavior remained: {forbidden}")

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
    "verified set persistence v49",
    "coherent simplified feedback history v49",
    "timed exercise records v49",
    "progress terminology cleanup v49",
]:
    if patch not in patches:
        patches.append(patch)
metadata["patches"] = patches
BUILD.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"sha256": sha, "bytes": metadata["bytes"], "patches": patches[-4:]}, ensure_ascii=False))
