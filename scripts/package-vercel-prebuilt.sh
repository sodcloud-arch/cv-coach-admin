#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STABLE="$ROOT/client-portal/stable"
OUT="$ROOT/client-portal/vercel-prebuilt"
STATIC="$OUT/.vercel/output/static"
CONFIG="$OUT/.vercel/output/config.json"

if [[ ! -f "$STABLE/index.html" || ! -f "$STABLE/build.json" ]]; then
  echo "::error::Canonical stable artifact is missing index.html or build.json"
  exit 1
fi

rm -rf "$OUT"
mkdir -p "$STATIC"
cp -a "$STABLE/." "$STATIC/"
rm -rf "$STATIC/.vercel"

grep -q 'CV_EXERCISE_SCREEN_V102_READY' "$STATIC/index.html"
grep -q 'CV_INLINE_SET_ENTRY_V104_READY' "$STATIC/index.html"
grep -q 'CV_GUIDED_SET_LOGGING_V105_READY' "$STATIC/index.html"
grep -q "revision:'105.5'" "$STATIC/index.html"
grep -q 'CV_FINISH_GUARD_V106_READY' "$STATIC/index.html"
grep -q 'FINALIZAR IGUAL' "$STATIC/index.html"
grep -q 'CV_SESSION_RECOVERY_V107_READY' "$STATIC/index.html"
grep -q 'REANUDAR SESIÓN' "$STATIC/index.html"

python3 - "$STATIC/build.json" <<'PY'
import json, sys
path=sys.argv[1]
data=json.load(open(path,encoding='utf-8'))
if data.get('version')!='107':
    raise SystemExit(f"Expected build.json version 107, got {data.get('version')!r}")
if not data.get('git_sha'):
    raise SystemExit('build.json is missing git_sha')
print('CV_PREBUILT_BUILD_META_OK',data['version'],data['git_sha'])
PY

cat > "$CONFIG" <<'JSON'
{
  "version": 3,
  "routes": [
    {
      "src": "/sw.js",
      "headers": {
        "Cache-Control": "no-cache, no-store, must-revalidate",
        "Service-Worker-Allowed": "/"
      },
      "continue": true
    },
    {
      "src": "/manifest.webmanifest",
      "headers": {
        "Content-Type": "application/manifest+json; charset=utf-8",
        "Cache-Control": "public, max-age=3600"
      },
      "continue": true
    },
    {
      "src": "/(.*)",
      "headers": {
        "X-Content-Type-Options": "nosniff",
        "X-Frame-Options": "DENY",
        "Referrer-Policy": "strict-origin-when-cross-origin",
        "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
        "X-Robots-Tag": "noindex, nofollow"
      },
      "continue": true
    },
    { "handle": "filesystem" },
    { "src": "/.*", "dest": "/index.html" }
  ]
}
JSON

python3 - "$CONFIG" <<'PY'
import json, sys
data=json.load(open(sys.argv[1],encoding='utf-8'))
assert data.get('version')==3
routes=data.get('routes') or []
assert any(route.get('handle')=='filesystem' for route in routes)
assert routes[-1].get('dest')=='/index.html'
print('CV_PREBUILT_CONFIG_OK',len(routes))
PY

echo "CV_VERCEL_PREBUILT_PACKAGE_OK"
