from pathlib import Path
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parent
HTML = ROOT / "stable" / "index.html"
BUILD = ROOT / "stable" / "build.json"

text = HTML.read_text(encoding="utf-8")
MARKER = "<!-- cv-feedback-simple-v48: 1-5 difficulty, conditional pain targeting, hardened set completion -->"
STYLE_ID = 'cv-feedback-simple-v48-css'

STYLE = r'''<style id="cv-feedback-simple-v48-css">
/* V48 · cierre de sesión simple y orientado a adherencia */
.cvFeedbackCardV48{width:min(560px,100%);max-height:92dvh;overflow:auto;border:1px solid #303a42;border-radius:20px;background:linear-gradient(155deg,#0d1319,#070b0f);box-shadow:0 28px 90px rgba(0,0,0,.65);padding:18px}
.cvFeedbackCardV48 h2{font-size:31px;margin:4px 0 6px}.cvFeedbackQuestionV48{margin-top:18px;color:#dfe6ea;font-size:13px;font-weight:850;line-height:1.35}.cvFeedbackHelpV48{margin-top:5px;color:#8998a1;font-size:10.5px;line-height:1.45}
.cvFeedbackScaleV48{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:7px;margin-top:10px}.cvFeedbackScaleV48 button,.cvFeedbackBinaryV48 button,.cvFeedbackTargetV48{border:1px solid #34434d;background:#081015;color:#b8c4ca;border-radius:12px;min-height:56px;padding:7px 5px;font-weight:800;cursor:pointer;touch-action:manipulation;transition:.16s ease}.cvFeedbackScaleV48 button b{display:block;color:#fff;font-size:20px;line-height:1}.cvFeedbackScaleV48 button span{display:block;margin-top:5px;font-size:8px;line-height:1.15}.cvFeedbackScaleV48 button.selected,.cvFeedbackBinaryV48 button.selected,.cvFeedbackTargetV48.selected{border-color:rgba(67,184,255,.68);background:rgba(67,184,255,.12);color:#a9e0ff;box-shadow:0 0 0 2px rgba(67,184,255,.07),0 0 18px rgba(67,184,255,.07)}
.cvFeedbackBinaryV48{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:10px}.cvFeedbackBinaryV48 button{min-height:48px;font-size:12px}.cvFeedbackPainV48{margin-top:14px;padding:13px;border:1px solid #293943;border-radius:14px;background:#070d11}.cvFeedbackPainV48.hidden{display:none!important}.cvFeedbackTargetsV48{display:flex;flex-wrap:wrap;gap:7px;margin-top:9px}.cvFeedbackTargetV48{min-height:38px;padding:0 11px;font-size:9.5px}.cvFeedbackTargetV48.general{border-style:dashed}.cvFeedbackTargetV48.selected{border-color:rgba(94,227,165,.55);background:rgba(94,227,165,.09);color:#9cf2c8;box-shadow:0 0 16px rgba(94,227,165,.06)}
.cvFeedbackCardV48 textarea{width:100%;min-height:88px;margin-top:8px;background:#05090d;border:1px solid #303942;color:#fff;border-radius:12px;padding:11px 12px;font:inherit;outline:none;resize:vertical}.cvFeedbackCardV48 textarea:focus{border-color:rgba(67,184,255,.78);box-shadow:0 0 0 3px rgba(67,184,255,.08)}.cvFeedbackCardV48 textarea::placeholder{color:#6f7c84}.cvFeedbackSafetyV48{margin-top:13px;padding:10px 12px;border:1px solid rgba(67,184,255,.16);border-radius:12px;background:rgba(67,184,255,.04);font-size:10px;line-height:1.45;color:#aab7be}.cvFeedbackActionsV48{display:grid;grid-template-columns:1fr;gap:8px;margin-top:14px}.cvFeedbackStatusV48{min-height:20px;margin-top:8px;font-size:11px;color:#aeb8be}.cvFeedbackStatusV48.error{color:#ff8d99}
body.cvFastWorkout .cvSetCheck.cvSetCheckPendingV48{box-shadow:0 0 0 2px rgba(67,184,255,.13),0 0 18px rgba(67,184,255,.10)!important}
@media(min-width:700px){.cvFeedbackBackdrop{align-items:center}.cvFeedbackActionsV48{grid-template-columns:1fr 1.25fr}}
@media(max-width:390px){.cvFeedbackCardV48{padding:16px}.cvFeedbackScaleV48{gap:5px}.cvFeedbackScaleV48 button{min-height:54px;padding:6px 3px}.cvFeedbackScaleV48 button span{font-size:7px}.cvFeedbackTargetV48{font-size:9px;padding:0 9px}}
</style>'''

NEW_FEEDBACK_JS = r'''function cvCloseWorkoutFeedback(){document.getElementById('cvWorkoutFeedbackBackdrop')?.remove()}
function cvFeedbackExerciseOptionsV48(){try{return (typeof window.cvExercises==='function'?(window.cvExercises()||[]):[]).map((e,i)=>({sessionExerciseId:e?.session_exercise_id||null,name:String(e?.name||('Ejercicio '+(i+1))),index:i})).filter(x=>x.sessionExerciseId)}catch(_){return []}}
function cvFeedbackSetErrorV48(status,message){if(!status)return;status.className='cvFeedbackStatusV48'+(message?' error':'');status.textContent=message||''}
async function cvCompleteWorkoutAfterFeedback(statusEl,button){
  try{
    button.disabled=true;cvFeedbackSetErrorV48(statusEl,'');statusEl.className='cvFeedbackStatusV48';statusEl.textContent='Guardando cierre de sesión…';
    const modal=document.getElementById('cvWorkoutFeedbackBackdrop');
    const difficulty=Number(modal?.dataset?.difficulty||0),painRaw=modal?.dataset?.hadPain,hadPain=painRaw==='1';
    if(!Number.isInteger(difficulty)||difficulty<1||difficulty>5)throw new Error('Marca qué tan difícil estuvo la rutina del 1 al 5.');
    if(painRaw!=='0'&&painRaw!=='1')throw new Error('Indica si sentiste alguna molestia o dolor.');
    const general=!!modal?.querySelector('.cvFeedbackTargetV48.general.selected');
    const exerciseIds=[...modal?.querySelectorAll('.cvFeedbackTargetV48.exercise.selected')||[]].map(x=>x.dataset.sessionExerciseId).filter(Boolean);
    const painDescription=(document.getElementById('cvFeedbackPainDescription')?.value||'').trim();
    const notes=(document.getElementById('cvFeedbackNotes')?.value||'').trim();
    if(hadPain&&!general&&!exerciseIds.length)throw new Error('Selecciona Rutina completa o al menos un ejercicio donde sentiste la molestia.');
    if(hadPain&&painDescription.length<3)throw new Error('Describe brevemente la molestia que sentiste.');
    if(painDescription.length>700)throw new Error('La descripción de la molestia supera el máximo permitido.');
    if(notes.length>1200)throw new Error('El comentario supera el máximo permitido.');
    const feedback=await sb.rpc('save_workout_feedback_v2',{
      p_session_id:workout.sessionId,
      p_difficulty_level:difficulty,
      p_had_pain:hadPain,
      p_pain_general:hadPain&&general,
      p_pain_session_exercise_ids:hadPain&&!general?exerciseIds:[],
      p_pain_description:hadPain?(painDescription||null):null,
      p_session_notes:notes||null
    });
    if(feedback.error)throw feedback.error;if(!feedback.data?.saved)throw new Error('El servidor no confirmó el cierre de sesión.');
    const {data:r,error}=await sb.functions.invoke('complete-workout',{body:{session_id:workout.sessionId}});if(error||r?.error)throw new Error(r?.detail||r?.error||error.message);
    clearInterval(timerHandle);cvCloseWorkoutFeedback();workout=null;await loadReal();view='home';render();cvShowWorkoutResult(r||{});
  }catch(e){cvFeedbackSetErrorV48(statusEl,e?.message||String(e));button.disabled=false}
}
function cvOpenWorkoutFeedback(){
  if(document.getElementById('cvWorkoutFeedbackBackdrop'))return;
  const exercises=cvFeedbackExerciseOptionsV48();
  const targets=exercises.map(x=>'<button type="button" class="cvFeedbackTargetV48 exercise" data-session-exercise-id="'+esc(x.sessionExerciseId)+'">'+esc(x.name)+'</button>').join('');
  const modal=document.createElement('div');modal.id='cvWorkoutFeedbackBackdrop';modal.className='cvFeedbackBackdrop';modal.dataset.difficulty='';modal.dataset.hadPain='';
  modal.innerHTML='<div class="cvFeedbackCardV48" role="dialog" aria-modal="true" aria-labelledby="cvFeedbackTitle"><div class="ey">CIERRE DE SESIÓN</div><h2 id="cvFeedbackTitle">¿Cómo estuvo la rutina?</h2><div class="sub">Dos respuestas rápidas y, solo si hubo molestia, un poco más de contexto.</div><div class="cvFeedbackQuestionV48">¿Qué tan difícil estuvo la rutina?</div><div class="cvFeedbackHelpV48">1 = muy fácil · 5 = muy difícil</div><div id="cvFeedbackDifficulty" class="cvFeedbackScaleV48"><button type="button" data-level="1"><b>1</b><span>MUY FÁCIL</span></button><button type="button" data-level="2"><b>2</b><span>FÁCIL</span></button><button type="button" data-level="3"><b>3</b><span>MODERADA</span></button><button type="button" data-level="4"><b>4</b><span>DIFÍCIL</span></button><button type="button" data-level="5"><b>5</b><span>MUY DIFÍCIL</span></button></div><div class="cvFeedbackQuestionV48">¿Sentiste alguna molestia o dolor durante la rutina?</div><div id="cvFeedbackPainChoice" class="cvFeedbackBinaryV48"><button type="button" data-pain="0">NO</button><button type="button" data-pain="1">SÍ</button></div><div id="cvFeedbackPainDetails" class="cvFeedbackPainV48 hidden"><div class="cvFeedbackQuestionV48" style="margin-top:0">¿Dónde apareció la molestia?</div><div class="cvFeedbackHelpV48">Puedes marcar uno o varios ejercicios, o elegir Rutina completa.</div><div id="cvFeedbackPainTargets" class="cvFeedbackTargetsV48"><button type="button" class="cvFeedbackTargetV48 general">RUTINA COMPLETA</button>'+targets+'</div><label for="cvFeedbackPainDescription">DESCRIBE LA MOLESTIA</label><textarea id="cvFeedbackPainDescription" maxlength="700" placeholder="Ej.: molestia en rodilla derecha al bajar, tensión lumbar, dolor en hombro…"></textarea></div><label for="cvFeedbackNotes">COMENTARIOS DE LA SESIÓN · OPCIONAL</label><textarea id="cvFeedbackNotes" maxlength="1200" placeholder="Ej.: dormí poco, me sentí fuerte, el ejercicio 2 se sintió muy bien…"></textarea><div class="cvFeedbackSafetyV48">Si reportas una molestia, CV Coach la dejará marcada para revisión antes de una progresión automática.</div><div class="cvFeedbackActionsV48"><button id="cvFeedbackCancel" class="btn" type="button">VOLVER AL ENTRENAMIENTO</button><button id="cvFeedbackFinish" class="btn primary" type="button">GUARDAR Y FINALIZAR</button></div><div id="cvFeedbackStatus" class="cvFeedbackStatusV48" role="status"></div></div>';
  document.body.appendChild(modal);
  modal.querySelectorAll('#cvFeedbackDifficulty button').forEach(b=>b.onclick=()=>{modal.dataset.difficulty=b.dataset.level||'';modal.querySelectorAll('#cvFeedbackDifficulty button').forEach(x=>x.classList.toggle('selected',x===b))});
  modal.querySelectorAll('#cvFeedbackPainChoice button').forEach(b=>b.onclick=()=>{const yes=b.dataset.pain==='1';modal.dataset.hadPain=yes?'1':'0';modal.querySelectorAll('#cvFeedbackPainChoice button').forEach(x=>x.classList.toggle('selected',x===b));document.getElementById('cvFeedbackPainDetails')?.classList.toggle('hidden',!yes);if(!yes){modal.querySelectorAll('.cvFeedbackTargetV48').forEach(x=>x.classList.remove('selected'));const d=document.getElementById('cvFeedbackPainDescription');if(d)d.value=''}});
  modal.querySelectorAll('.cvFeedbackTargetV48').forEach(b=>b.onclick=()=>{if(b.classList.contains('general')){const next=!b.classList.contains('selected');modal.querySelectorAll('.cvFeedbackTargetV48').forEach(x=>x.classList.remove('selected'));b.classList.toggle('selected',next)}else{modal.querySelector('.cvFeedbackTargetV48.general')?.classList.remove('selected');b.classList.toggle('selected')}});
  document.getElementById('cvFeedbackCancel').onclick=cvCloseWorkoutFeedback;
  document.getElementById('cvFeedbackFinish').onclick=()=>cvCompleteWorkoutAfterFeedback(document.getElementById('cvFeedbackStatus'),document.getElementById('cvFeedbackFinish'));
}
'''

NEW_TOGGLE = r'''  /* active-session routing and resume are owned by the canonical session coordinator (v46). */
  window.cvToggleSet=async function(i,j){
    const locks=window.cvSetToggleLocksV48||(window.cvSetToggleLocksV48=new Set()),dayAtTap=workout?.dayId,lockKey=String(dayAtTap||'none')+'|'+i+'|'+j;
    if(locks.has(lockKey))return false;locks.add(lockKey);
    try{
      let preBtn=(document.getElementById('cvw_'+i+'_'+j)||document.getElementById('cvr_'+i+'_'+j))?.closest('.cvSetRow')?.querySelector('.cvSetCheck');preBtn?.classList.add('cvSetCheckPendingV48');
      if(!workout?.sessionId){const started=await window.startWorkout();if(!started||!workout?.sessionId){preBtn?.classList.remove('cvSetCheckPendingV48');toast?.('No pude iniciar la rutina. Reintenta en unos segundos.');return false}}
      if(!workout||workout.dayId!==dayAtTap)return false;
      const ex=typeof window.cvExercises==='function'?window.cvExercises()?.[i]:null,s=ex?.sets?.[j];if(!ex||!s)return false;
      const unit=ex.prescription_unit||'reps',wi=document.getElementById('cvw_'+i+'_'+j),ri=document.getElementById('cvr_'+i+'_'+j),riri=document.getElementById('cvri_'+i+'_'+j),w=unit==='reps'&&wi&&wi.value!==''?Number(wi.value):null,performed=ri&&ri.value!==''?Math.round(Number(ri.value)):null,rir=riri&&riri.value!==''?Number(riri.value):null;
      if(w!=null&&!Number.isFinite(w))return toast?.('Revisa el peso.');if(performed==null||!Number.isFinite(performed)||performed<=0)return toast?.(unit==='seconds'?'Ingresa los segundos realizados.':'Ingresa las repeticiones realizadas.');if(rir!=null&&(!Number.isFinite(rir)||rir<0||rir>10))return toast?.('RIR debe estar entre 0 y 10.');
      const next=!s.completed,old={w:s.weight_kg,r:s.reps,d:s.duration_seconds,rir:s.rir,c:s.completed};s.weight_kg=unit==='reps'?w:null;if(unit==='seconds'){s.duration_seconds=performed;s.reps=null}else{s.reps=performed;s.duration_seconds=null}s.rir=rir;s.completed=next;
      const row=(wi||ri)?.closest('.cvSetRow'),btn=row?.querySelector('.cvSetCheck');row?.classList.toggle('done',next);btn?.classList.toggle('done',next);btn?.classList.add('cvSetCheckPendingV48');btn?.setAttribute('aria-pressed',next?'true':'false');updateStats();const card=row?.closest('.cvHevyExercise'),all=ex.sets||[],done=all.filter(x=>x.completed).length;card?.classList.toggle('cvExerciseHasProgress',done>0);card?.classList.toggle('cvExerciseComplete',all.length>0&&done===all.length);
      const commitSuccess=()=>{btn?.classList.remove('cvSetCheckPendingV48');if(next)startRest(ex.rest_seconds||90,ex.name);document.dispatchEvent(new CustomEvent('cv:set-state',{detail:{i,j,completed:next}}));return true};
      if(mode==='demo'||!s.set_log_id)return commitSuccess();
      const body=unit==='seconds'?{weight_kg:null,reps:null,duration_seconds:performed,rir,completed:next,completed_at:next?new Date().toISOString():null,source:'manual'}:{weight_kg:w,reps:performed,duration_seconds:null,rir,completed:next,completed_at:next?new Date().toISOString():null,source:'manual'};
      try{const {error}=await sb.from('set_logs').update(body).eq('id',s.set_log_id);if(error)throw error;return commitSuccess()}catch(e){s.weight_kg=old.w;s.reps=old.r;s.duration_seconds=old.d;s.rir=old.rir;s.completed=old.c;row?.classList.toggle('done',old.c);btn?.classList.toggle('done',old.c);btn?.classList.remove('cvSetCheckPendingV48');btn?.setAttribute('aria-pressed',old.c?'true':'false');updateStats();toast?.('No pude guardar la serie. Se revirtió para proteger tus datos.');return false}
    }finally{locks.delete(lockKey)}
  };
  const baseRender=window.render;'''

if MARKER not in text:
    feedback_pattern = re.compile(r"function cvFeedbackOptions\(min,max,kind\)\{.*?\nwindow\.finishWorkout=async\(\)=>", re.S)
    text, feedback_count = feedback_pattern.subn(NEW_FEEDBACK_JS + "\nwindow.finishWorkout=async()=>", text, count=1)
    if feedback_count != 1:
        raise SystemExit(f"feedback v48 replacement expected 1 block, got {feedback_count}")

    toggle_pattern = re.compile(r"  /\* active-session routing and resume are owned by the canonical session coordinator \(v46\)\. \*/\n  window\.cvToggleSet=async function\(i,j\)\{.*?\n  \};\n  const baseRender=window\.render;", re.S)
    text, toggle_count = toggle_pattern.subn(NEW_TOGGLE, text, count=1)
    if toggle_count != 1:
        raise SystemExit(f"set toggle v48 replacement expected 1 block, got {toggle_count}")

    if STYLE_ID not in text:
        if "</head>" not in text:
            raise SystemExit("feedback v48: </head> missing")
        text = text.replace("</head>", STYLE + "\n</head>", 1)
    if "</body>" not in text:
        raise SystemExit("feedback v48: </body> missing")
    text = text.replace("</body>", MARKER + "\n</body>", 1)

required = [
    MARKER,
    STYLE_ID,
    "save_workout_feedback_v2",
    "¿Qué tan difícil estuvo la rutina?",
    "cvFeedbackPainTargets",
    "cvSetToggleLocksV48",
    "aria-pressed",
    "cvSetCheckPendingV48",
]
for item in required:
    if item not in text:
        raise SystemExit(f"feedback v48 required marker missing: {item}")

forbidden = [
    "RPE GLOBAL</label><select id=\"cvFeedbackEffort\"",
    "FATIGA</label><select id=\"cvFeedbackFatigue\"",
    "save_workout_feedback',{p_session_id:workout.sessionId",
]
for item in forbidden:
    if item in text:
        raise SystemExit(f"feedback v48 legacy UI remained: {item}")

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
for patch in ["simple workout feedback v48", "hardened canonical set toggle v48"]:
    if patch not in patches:
        patches.append(patch)
metadata["patches"] = patches
BUILD.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"sha256": sha, "bytes": metadata["bytes"], "patches": patches[-2:]}, ensure_ascii=False))
