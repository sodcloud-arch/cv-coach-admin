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

required = [
    "CV Coach",
    "sb.functions.invoke('start-workout'",
    "sb.functions.invoke('complete-workout'",
    "sb.functions.invoke('log-habit'",
    "sb.functions.invoke('log-nutrition-day'",
    "cvRestDock",
    "cvOpenTechnique",
    "client_cv_state",
]
for marker in required:
    if marker not in text:
        raise SystemExit(f"required marker missing: {marker}")

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
    ],
}
(OUT_DIR / "build.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps(metadata, ensure_ascii=False))
