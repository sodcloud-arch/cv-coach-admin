from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parent
HTML = ROOT / "stable" / "index.html"
BUILD = ROOT / "stable" / "build.json"

text = HTML.read_text(encoding="utf-8")
MARKER = "<!-- cv-workout-regression-guard-v52: executable persistence + lifecycle contracts -->"

required = [
    "cv-client-runtime-v51",
    "cvPersistSetLogV51",
    "cvDraftSaveLocksV50",
    "cvSetToggleLocksV48",
    "draft update was not confirmed",
    "set update was not confirmed",
    "sessionEpoch=0",
    "async function loadSession(",
    "historyPromise?.sessionId===sessionId",
    "new CustomEvent('cv:rendered')",
    "kg·reps",
]
for item in required:
    if item not in text:
        raise SystemExit(f"quality v52 prerequisite missing: {item}")

for forbidden in [
    "cvRirInput",
    "getElementById('cvri_'",
    "baseRender=window.render",
    "baseNav=window.nav",
]:
    if forbidden in text:
        raise SystemExit(f"quality v52 forbidden runtime marker remained: {forbidden}")

if MARKER not in text:
    if "</body>" not in text:
        raise SystemExit("quality v52: </body> missing")
    text = text.replace("</body>", MARKER + "\n</body>", 1)

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
patch = "workout runtime regression guard v52"
if patch not in patches:
    patches.append(patch)
metadata["patches"] = patches
BUILD.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"sha256": sha, "bytes": metadata["bytes"], "patch": patch}, ensure_ascii=False))
