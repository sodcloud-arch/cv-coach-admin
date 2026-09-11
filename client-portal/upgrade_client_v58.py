from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parent
HTML = ROOT / "stable" / "index.html"
BUILD = ROOT / "stable" / "build.json"
MARKER = "<!-- cv-client-e2e-v58: executable module interactions + backend rollback contract -->"

text = HTML.read_text(encoding="utf-8")

prerequisites = [
    "cv-client-modules-v57",
    "cv-client-modules-v57-js",
    "window.logHabit=async function",
    "window.logNutrition=async function",
    "window.cvLogNutritionMealsV57",
    "window.cvTogglePhotoVisibilityV57",
    "function openWeeklyCheckin()",
    "async function saveWeeklyCheckin(event)",
    "sb.rpc('submit_weekly_checkin',payload)",
    "if(!saved?.id)throw new Error('El servidor no confirmó el check-in.')",
    "sb.from('notifications')",
    "sb.from('client_missions')",
    "sb.from('progress_photos')",
]
for prerequisite in prerequisites:
    if prerequisite not in text:
        raise SystemExit(f"client E2E v58 prerequisite missing: {prerequisite}")

if MARKER not in text:
    if "</body>" not in text:
        raise SystemExit("client E2E v58: </body> missing")
    text = text.replace("</body>", MARKER + "\n</body>", 1)

for item in [MARKER, "cv-client-modules-v57", "cv-set-toggle-runtime-v56"]:
    if item not in text:
        raise SystemExit(f"client E2E v58 contract missing: {item}")

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
patch = "client module executable E2E gate v58"
if patch not in patches:
    patches.append(patch)
metadata["patches"] = patches
BUILD.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"sha256": sha, "bytes": metadata["bytes"], "patch": patch}, ensure_ascii=False))
