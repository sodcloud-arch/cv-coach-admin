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


# Set completion feedback must be driven by the canonical domain event so the
# visible row/check state cannot drift from the persisted workout model.
old_v21_listener = """  document.addEventListener('cv:set-state',event=>{
    const detail=event.detail||{};if(!detail.completed)return;
    try{navigator.vibrate?.(35)}catch(_){}
    requestAnimationFrame(()=>{const row=document.getElementById('cvw_'+detail.i+'_'+detail.j)?.closest('.cvSetRow');if(row){row.classList.add('cvJustCompleted');setTimeout(()=>row.classList.remove('cvJustCompleted'),380)}})
  });
"""
new_v21_listener = """  document.addEventListener('cv:set-state',event=>{
    const detail=event.detail||{},completed=!!detail.completed;
    requestAnimationFrame(()=>{
      const input=document.getElementById('cvw_'+detail.i+'_'+detail.j)||document.getElementById('cvr_'+detail.i+'_'+detail.j),row=input?.closest('.cvSetRow'),btn=row?.querySelector('.cvSetCheck');
      row?.classList.toggle('done',completed);btn?.classList.toggle('done',completed);btn?.setAttribute('aria-pressed',completed?'true':'false');
      if(completed&&row){try{navigator.vibrate?.(35)}catch(_){}row.classList.add('cvJustCompleted');setTimeout(()=>row.classList.remove('cvJustCompleted'),380)}
    })
  });
"""
replace_once_or_keep(old_v21_listener, new_v21_listener, "canonical visible set-state sync")

# The compact summary was previously queued on the click itself. When a click
# auto-starts the session the network/persistence path can finish after that
# queue has already run. Refresh again from the canonical set-state event.
old_v40_hook = """  document.addEventListener('click',event=>{if(event.target.closest('.cvSetCheck,.cvAddSet'))setTimeout(queueCompactV44,0)},true);
  document.addEventListener('focusin',event=>{
"""
new_v40_hook = """  document.addEventListener('click',event=>{if(event.target.closest('.cvSetCheck,.cvAddSet'))setTimeout(queueCompactV44,0)},true);
  document.addEventListener('cv:set-state',()=>{queueCompactV44();requestAnimationFrame(()=>{if(document.body.classList.contains('cvWorkoutActiveV40'))renderCompactTopV40()})});
  document.addEventListener('cv:set-added',queueCompactV44);
  document.addEventListener('focusin',event=>{
"""
replace_once_or_keep(old_v40_hook, new_v40_hook, "compact summary domain-event refresh")

STYLE = """<style id="cv-workout-readability-v47">
/* CV Coach · exercise-name readability + semantic completion feedback */
body.cvFastWorkout .exerciseTop h3{
  font-family:Inter,system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif!important;
  font-size:clamp(19px,5.2vw,23px)!important;
  font-weight:800!important;
  line-height:1.12!important;
  letter-spacing:-.035em!important;
  color:#f8fbff!important;
  text-shadow:0 1px 0 rgba(0,0,0,.32)!important;
  overflow-wrap:anywhere;
}
body.cvFastWorkout .exerciseTop h3:after{
  content:"";
  display:block;
  width:30px;
  height:2px;
  margin-top:6px;
  border-radius:99px;
  background:linear-gradient(90deg,#43c8ff,rgba(67,200,255,.12));
  box-shadow:0 0 12px rgba(67,200,255,.16);
  opacity:.68;
}
body.cvFastWorkout .cvExerciseCurrent .exerciseTop h3:after{opacity:1;width:38px}
body.cvFastWorkout .cvExerciseComplete .exerciseTop h3:after{background:linear-gradient(90deg,#5ee3a5,rgba(94,227,165,.10));box-shadow:0 0 12px rgba(94,227,165,.13)}
body.cvFastWorkout .cvSetCheck.done,
body.cvFastWorkout .cvSetCheck[aria-pressed="true"]{
  background:linear-gradient(145deg,#1b5838,#103a25)!important;
  border-color:#64cf94!important;
  color:#b3f8d5!important;
  box-shadow:0 0 24px rgba(94,227,165,.22),inset 0 1px 0 rgba(255,255,255,.06)!important;
}
body.cvFastWorkout .cvSetRow.done{background:linear-gradient(90deg,rgba(94,227,165,.10),transparent 82%)!important}
@media(max-width:390px){body.cvFastWorkout .exerciseTop h3{font-size:20px!important;line-height:1.14!important}}
</style>"""
if 'id="cv-workout-readability-v47"' not in text:
    if "</head>" not in text:
        raise SystemExit("workout readability style: </head> missing")
    text = text.replace("</head>", STYLE + "\n</head>", 1)

marker = "<!-- cv-workout-feedback-v47: canonical check/progress sync + Inter exercise titles with cyan accent -->"
if marker not in text:
    if "</body>" not in text:
        raise SystemExit("workout feedback marker: </body> missing")
    text = text.replace("</body>", marker + "\n</body>", 1)

required = [
    "btn?.setAttribute('aria-pressed',completed?'true':'false')",
    "document.addEventListener('cv:set-state',()=>{queueCompactV44()",
    'id="cv-workout-readability-v47"',
    "font-family:Inter,system-ui",
    marker,
    "cv-session-runtime-v46",
]
for item in required:
    if item not in text:
        raise SystemExit(f"workout feedback required marker missing: {item}")

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
    "canonical visible set-state sync",
    "compact workout progress refresh on set-state",
    "Inter exercise-title readability with cyan accent",
    "workout feedback v47",
]:
    if patch not in patches:
        patches.append(patch)
metadata["patches"] = patches
BUILD.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"sha256": sha, "bytes": metadata["bytes"], "patches": metadata["patches"][-4:]}, ensure_ascii=False))
