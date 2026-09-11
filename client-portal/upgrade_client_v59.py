from pathlib import Path
import hashlib
import json
import runpy

ROOT = Path(__file__).resolve().parent
HTML = ROOT / "stable" / "index.html"
BUILD = ROOT / "stable" / "build.json"
MARKER = "<!-- cv-coach-client-loop-v59: routine notifications + reviewed-risk attention -->"

text = HTML.read_text(encoding="utf-8")

if MARKER not in text:
    prerequisites = [
        "cv-client-e2e-v58",
        "function safeNotificationView(url)",
        "const notificationTypes={",
        "'/progress/achievements':'achievements'",
    ]
    for prerequisite in prerequisites:
        if prerequisite not in text:
            raise SystemExit(f"coach-client loop v59 prerequisite missing: {prerequisite}")

    old_types = "const notificationTypes={onboarding_approved:'Onboarding aprobado',onboarding_changes_requested:'Cambios solicitados',adaptive_mission:'Misión adaptativa',mission_completed:'Misión completada',achievement_unlocked:'Logro desbloqueado',level_up:'Subida de nivel'};"
    new_types = "const notificationTypes={onboarding_approved:'Onboarding aprobado',onboarding_changes_requested:'Cambios solicitados',adaptive_mission:'Misión adaptativa',mission_completed:'Misión completada',achievement_unlocked:'Logro desbloqueado',level_up:'Subida de nivel',program_published:'Rutina actualizada'};"
    if old_types not in text:
        raise SystemExit("coach-client loop v59 notification type map not found")
    text = text.replace(old_types, new_types, 1)

    old_routes = "const routes={'/':'home','/progress':'progress','/progress/missions':'missions','/progress/achievements':'achievements'};"
    new_routes = "const routes={'/':'home','/routine':'routine','/progress':'progress','/progress/missions':'missions','/progress/achievements':'achievements'};"
    if old_routes not in text:
        raise SystemExit("coach-client loop v59 safe notification route map not found")
    text = text.replace(old_routes, new_routes, 1)

    if "</body>" not in text:
        raise SystemExit("coach-client loop v59: </body> missing")
    text = text.replace("</body>", MARKER + "\n</body>", 1)

required = [
    MARKER,
    "program_published:'Rutina actualizada'",
    "'/routine':'routine'",
]
for item in required:
    if item not in text:
        raise SystemExit(f"coach-client loop v59 required contract missing: {item}")

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
    "coach client feedback loop v59",
    "program published client notification route v59",
    "reviewed risk attention semantics v59",
]:
    if patch not in patches:
        patches.append(patch)
metadata["patches"] = patches
BUILD.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"sha256": sha, "bytes": metadata["bytes"], "patches": metadata["patches"][-3:]}, ensure_ascii=False))

# V60 is chained from the existing production build owner so the new rank
# experience cannot bypass any V52-V59 regression gates. The repair step is a
# narrow syntax hotfix kept explicit until it is folded into the generator.
runpy.run_path(str(ROOT / "upgrade_client_v60.py"), run_name="__main__")
runpy.run_path(str(ROOT / "repair_client_v60.py"), run_name="__main__")
runpy.run_path(str(ROOT.parent / "scripts" / "test-cv-rank-system-v60.py"), run_name="__main__")
