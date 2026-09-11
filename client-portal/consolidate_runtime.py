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


# Phase 1: remove visual-only wrappers around render/start/toggle. The actual
# workout persistence remains owned by the canonical functional layer (v25).
# Visual synchronization is driven from DOM mutations instead, so visual code
# cannot silently overwrite or re-wrap the functional workout engine.

old_v23 = """  const baseRender=window.render;window.render=function(){const r=baseRender.apply(this,arguments);requestAnimationFrame(decorateCards);return r};
  requestAnimationFrame(decorateCards);
"""
new_v23 = """  let cvPremiumDecorQueued=false;
  function queuePremiumDecor(){if(cvPremiumDecorQueued)return;cvPremiumDecorQueued=true;requestAnimationFrame(()=>{cvPremiumDecorQueued=false;decorateCards()})}
  const cvPremiumDecorObserver=new MutationObserver(queuePremiumDecor);
  cvPremiumDecorObserver.observe(document.getElementById('content')||document.body,{childList:true,subtree:true});
  queuePremiumDecor();
"""
replace_once_or_keep(old_v23, new_v23, "v23 visual render wrapper removal")

old_v31 = """  const baseRender=window.render;window.render=function(){const r=baseRender.apply(this,arguments);requestAnimationFrame(enhance);return r};
  if(typeof window.cvToggleSet==='function'){const baseToggle=window.cvToggleSet;window.cvToggleSet=async function(){const r=await baseToggle.apply(this,arguments);requestAnimationFrame(enhance);return r}}
  if(typeof window.cvAddSet==='function'){const baseAdd=window.cvAddSet;window.cvAddSet=async function(){const r=await baseAdd.apply(this,arguments);requestAnimationFrame(enhance);return r}}
  if(typeof window.startWorkout==='function'){const baseStart=window.startWorkout;window.startWorkout=async function(){const r=await baseStart.apply(this,arguments);requestAnimationFrame(enhance);return r}}
  const observer=new MutationObserver(()=>{if(document.body.classList.contains('cvFastWorkout'))requestAnimationFrame(enhance)});observer.observe(document.getElementById('content')||document.body,{childList:true,subtree:true});
  requestAnimationFrame(enhance);
"""
new_v31 = """  let cvAthleteEnhanceQueued=false;
  function queueAthleteEnhance(){if(cvAthleteEnhanceQueued||!document.body.classList.contains('cvFastWorkout'))return;cvAthleteEnhanceQueued=true;requestAnimationFrame(()=>{cvAthleteEnhanceQueued=false;enhance()})}
  const observer=new MutationObserver(queueAthleteEnhance);observer.observe(document.getElementById('content')||document.body,{childList:true,subtree:true});
  requestAnimationFrame(enhance);
"""
replace_once_or_keep(old_v31, new_v31, "v31 visual workout wrappers removal")

old_v40 = """  const baseRender=window.render;
  if(typeof baseRender==='function')window.render=function(){const result=baseRender.apply(this,arguments);requestAnimationFrame(applyCompactV40);return result};
  if(typeof window.startWorkout==='function'){const baseStart=window.startWorkout;window.startWorkout=async function(){const result=await baseStart.apply(this,arguments);requestAnimationFrame(applyCompactV40);return result}}
  if(typeof window.cvToggleSet==='function'){const baseToggle=window.cvToggleSet;window.cvToggleSet=async function(){const result=await baseToggle.apply(this,arguments);requestAnimationFrame(applyCompactV40);return result}}
  document.addEventListener('focusin',event=>{
"""
new_v40 = """  let compactSyncQueuedV44=false;
  function queueCompactV44(){if(compactSyncQueuedV44)return;compactSyncQueuedV44=true;requestAnimationFrame(()=>{compactSyncQueuedV44=false;applyCompactV40()})}
  const compactObserverV44=new MutationObserver(queueCompactV44);
  compactObserverV44.observe(document.getElementById('content')||document.body,{childList:true,subtree:true,characterData:true});
  document.addEventListener('click',event=>{if(event.target.closest('.cvSetCheck,.cvAddSet'))setTimeout(queueCompactV44,0)},true);
  document.addEventListener('focusin',event=>{
"""
replace_once_or_keep(old_v40, new_v40, "v40 compact wrappers removal")

marker = "<!-- cv-runtime-consolidation-v44: visual wrappers removed; DOM observers own visual sync -->"
if marker not in text:
    if "</body>" not in text:
        raise SystemExit("runtime consolidation marker: </body> missing")
    text = text.replace("</body>", marker + "\n</body>", 1)

required = [
    "cvPremiumDecorObserver",
    "queueAthleteEnhance",
    "compactObserverV44",
    marker,
    "duration_seconds:performed",
    "cv-runtime-audit-v43",
]
for item in required:
    if item not in text:
        raise SystemExit(f"runtime consolidation required marker missing: {item}")

forbidden = [
    "const baseRender=window.render;window.render=function(){const r=baseRender.apply(this,arguments);requestAnimationFrame(decorateCards);return r};",
    "if(typeof window.cvToggleSet==='function'){const baseToggle=window.cvToggleSet;window.cvToggleSet=async function(){const r=await baseToggle.apply(this,arguments);requestAnimationFrame(enhance);return r}}",
    "if(typeof window.startWorkout==='function'){const baseStart=window.startWorkout;window.startWorkout=async function(){const result=await baseStart.apply(this,arguments);requestAnimationFrame(applyCompactV40);return result}}",
]
for item in forbidden:
    if item in text:
        raise SystemExit(f"runtime consolidation legacy wrapper remained: {item}")

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
    "v23 visual wrapper removed",
    "v31 workout visual wrappers removed",
    "v40 compact visual wrappers removed",
    "runtime consolidation v44",
]:
    if patch not in patches:
        patches.append(patch)
metadata["patches"] = patches
BUILD.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"sha256": sha, "bytes": metadata["bytes"], "patches": metadata["patches"][-4:]}, ensure_ascii=False))
