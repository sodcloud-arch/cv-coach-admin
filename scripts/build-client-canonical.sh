#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "CV_CANONICAL_BUILD_START"
rm -rf client-portal/stable

python client-portal/stabilize.py
python client-portal/consolidate_runtime.py
python client-portal/consolidate_session_runtime.py
python client-portal/workout_feedback.py
python client-portal/upgrade_feedback_v48.py
python client-portal/upgrade_client_v49.py
python client-portal/upgrade_client_v50.py
python client-portal/upgrade_client_v51.py
python client-portal/upgrade_client_v52.py
python client-portal/upgrade_client_v53.py
python client-portal/upgrade_client_v54.py
python client-portal/upgrade_client_v55.py
python client-portal/upgrade_client_v56.py
python client-portal/upgrade_client_v57.py
python client-portal/upgrade_client_v59.py
python client-portal/upgrade_client_v60.py
python client-portal/repair_client_v60.py
python client-portal/upgrade_client_v61.py
python client-portal/upgrade_client_v67.py
python client-portal/upgrade_client_v68.py
python client-portal/upgrade_client_v69.py
python client-portal/upgrade_client_v74.py
python client-portal/upgrade_client_v101.py
python client-portal/upgrade_client_v102.py
python client-portal/upgrade_client_v103.py
python client-portal/upgrade_client_v104.py
python client-portal/upgrade_client_v105.py

mkdir -p client-portal/stable/assets
cp -R client-portal/assets/. client-portal/stable/assets/
cp client-portal/vercel.json client-portal/stable/vercel.json

for file in manifest.webmanifest sw.js favicon.ico; do
  if [[ -f "client-portal/$file" ]]; then
    cp "client-portal/$file" "client-portal/stable/$file"
  fi
done

node --check client-portal/assets/cv-guided-set-logging-v105.js
grep -q 'CV_GUIDED_SET_LOGGING_V105_READY' client-portal/stable/index.html
grep -q 'CV_INLINE_SET_ENTRY_V104_READY' client-portal/stable/index.html
grep -q "revision:'105.4'" client-portal/stable/index.html
! grep -q 'CVWorkoutNumpadV73' client-portal/stable/index.html

python - <<'PY'
from pathlib import Path
import hashlib, json, os

root = Path("client-portal/stable")
html = root / "index.html"
payload = html.read_bytes()
meta = {
    "pipeline": "canonical-client",
    "version": "105.4",
    "git_sha": os.environ.get("GITHUB_SHA") or os.environ.get("CV_GIT_SHA") or "local",
    "index_sha256": hashlib.sha256(payload).hexdigest(),
    "index_bytes": len(payload),
}
(root / "build.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("CV_CANONICAL_BUILD_METADATA", json.dumps(meta, ensure_ascii=False))
PY

echo "CV_CANONICAL_BUILD_OK"
