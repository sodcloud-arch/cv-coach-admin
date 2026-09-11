from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parent
HTML = ROOT / "stable" / "index.html"
BUILD = ROOT / "stable" / "build.json"
MARKER = "<!-- cv-mobile-workout-reliability-v54: bounded start + auth retry + confirmed progress sync -->"

text = HTML.read_text(encoding="utf-8")

HELPERS = r'''  function cvV54Timeout(ms,message){
    return new Promise((_,reject)=>setTimeout(()=>reject(new Error(message)),ms))
  }
  function cvV54Bounded(promise,ms,message){
    return Promise.race([Promise.resolve(promise),cvV54Timeout(ms,message)])
  }
  async function cvV54RefreshAuth(){
    const refreshed=await cvV54Bounded(sb.auth.refreshSession(),5000,'No pude renovar tu sesión. Revisa tu conexión.');
    if(refreshed?.error)throw refreshed.error;
    if(!refreshed?.data?.session?.access_token)throw new Error('Tu sesión de CV Coach expiró. Sal y vuelve a ingresar.');
    return true
  }
  async function cvV54EnsureAuth(){
    const current=await cvV54Bounded(sb.auth.getSession(),4000,'No pude validar tu sesión. Revisa tu conexión.');
    if(current?.error)throw current.error;
    if(current?.data?.session?.access_token)return true;
    return cvV54RefreshAuth()
  }
  function cvV54AuthLike(error){
    const message=String(error?.message||error||'');
    return /(401|unauthor|jwt|token|session|sesión|auth)/i.test(message)
  }
  async function cvInvokeStartWorkoutV54(dayId){
    await cvV54EnsureAuth();
    const invoke=()=>cvV54Bounded(
      sb.functions.invoke('start-workout',{body:{program_day_id:dayId}}),
      7000,
      'El inicio del entrenamiento tardó demasiado.'
    );
    let first=null;
    try{
      first=await invoke();
      const detail=String(first?.data?.detail||first?.data?.error||first?.error?.message||'');
      if(!first?.error&&!first?.data?.error)return first;
      if(!cvV54AuthLike(detail))return first
    }catch(error){
      first={error}
    }
    try{
      await cvV54RefreshAuth();
      return await cvV54Bounded(
        sb.functions.invoke('start-workout',{body:{program_day_id:dayId}}),
        9000,
        'El inicio del entrenamiento no respondió a tiempo.'
      )
    }catch(error){
      const message=cvV54AuthLike(error)
        ?'Tu sesión de CV Coach expiró. Sal y vuelve a ingresar.'
        :'No pude iniciar el entrenamiento. Revisa tu conexión e inténtalo otra vez.';
      const wrapped=new Error(message);wrapped.cause=error||first?.error;throw wrapped
    }
  }

'''

if MARKER not in text:
    for prerequisite in [
        "cv-session-runtime-v46",
        "cv-client-runtime-v51",
        "cv-workout-regression-guard-v52",
        "cv-client-sound-v53",
    ]:
        if prerequisite not in text:
            raise SystemExit(f"mobile workout v54 prerequisite missing: {prerequisite}")

    load_anchor = "  async function loadSession(target,dayId,epoch,{resuming=false,fallbackStarted=null}={}){"
    if text.count(load_anchor) != 1:
        raise SystemExit(f"mobile workout v54 loadSession anchor expected 1, got {text.count(load_anchor)}")
    text = text.replace(load_anchor, HELPERS + load_anchor, 1)

    direct_start = "    const {data:r,error}=await sb.functions.invoke('start-workout',{body:{program_day_id:dayId}});if(error||r?.error)throw new Error(r?.detail||r?.error||error.message);"
    robust_start = "    const {data:r,error}=await cvInvokeStartWorkoutV54(dayId);if(error||r?.error)throw new Error(r?.detail||r?.error||error.message);"
    if text.count(direct_start) != 1:
        raise SystemExit(f"mobile workout v54 direct start expected 1 canonical call, got {text.count(direct_start)}")
    text = text.replace(direct_start, robust_start, 1)

    compact_click = "  document.addEventListener('click',event=>{if(event.target.closest('.cvSetCheck,.cvAddSet'))setTimeout(queueCompactV44,0)},true);"
    compact_confirmed = compact_click + "\n  document.addEventListener('cv:set-state',()=>queueCompactV44());"
    if text.count(compact_click) != 1:
        raise SystemExit(f"mobile workout v54 compact click anchor expected 1, got {text.count(compact_click)}")
    text = text.replace(compact_click, compact_confirmed, 1)

    # V32 already owns row/check green-state synchronization. V54 asserts that
    # this confirmed-event path still exists so a successful persistence cannot
    # leave the visual row stale after later runtime consolidations.
    visual_contract = "requestAnimationFrame(workoutState);"
    if visual_contract not in text or "document.addEventListener('cv:set-state',event=>" not in text:
        raise SystemExit("mobile workout v54 confirmed visual state event contract missing")

    if "</body>" not in text:
        raise SystemExit("mobile workout v54: </body> missing")
    text = text.replace("</body>", MARKER + "\n</body>", 1)

required = [
    MARKER,
    "function cvV54Bounded",
    "Promise.race([Promise.resolve(promise),cvV54Timeout(ms,message)])",
    "sb.auth.getSession()",
    "sb.auth.refreshSession()",
    "cvInvokeStartWorkoutV54(dayId)",
    "El inicio del entrenamiento tardó demasiado.",
    "El inicio del entrenamiento no respondió a tiempo.",
    "document.addEventListener('cv:set-state',()=>queueCompactV44())",
    "requestAnimationFrame(workoutState);",
    "await cvPersistSetLogV51(ex,s,body,'set log missing','set update was not confirmed')",
]
for item in required:
    if item not in text:
        raise SystemExit(f"mobile workout v54 required contract missing: {item}")

# Only the V54 helper may invoke start-workout directly. loadSession must use
# the bounded/auth-aware helper so a mobile tap cannot remain pending forever.
start = text.find("  async function loadSession(")
end = text.find("\n  window.startWorkout=async function()", start)
if start < 0 or end <= start:
    raise SystemExit("mobile workout v54 could not isolate loadSession")
load_block = text[start:end]
if "sb.functions.invoke('start-workout'" in load_block:
    raise SystemExit("mobile workout v54 loadSession still invokes start-workout directly")
if "cvInvokeStartWorkoutV54(dayId)" not in load_block:
    raise SystemExit("mobile workout v54 loadSession is not using bounded start helper")

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
    "bounded mobile workout start v54",
    "auth refresh retry v54",
    "confirmed compact progress sync v54",
    "mobile workout reliability v54",
]:
    if patch not in patches:
        patches.append(patch)
metadata["patches"] = patches
BUILD.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"sha256": sha, "bytes": metadata["bytes"], "patches": metadata["patches"][-4:]}, ensure_ascii=False))
