from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HTML = ROOT / "client-portal" / "stable" / "index.html"
ASSETS = ROOT / "client-portal" / "assets"

if not HTML.exists():
    raise SystemExit(f"built artifact missing: {HTML}")

html = HTML.read_text(encoding="utf-8")

SCRIPT_RE = re.compile(r"(?is)<script\b([^>]*)>(.*?)</script>")
SRC_RE = re.compile(r"\bsrc=[\"']([^\"']+)[\"']", re.I)

units: list[tuple[str, str]] = []
loaded_local: list[str] = []

for i, match in enumerate(SCRIPT_RE.finditer(html), start=1):
    attrs, body = match.group(1), match.group(2)
    src_match = SRC_RE.search(attrs)
    if src_match:
        src = src_match.group(1)
        if src.startswith("./assets/") or src.startswith("assets/"):
            rel = src.removeprefix("./")
            path = ROOT / "client-portal" / rel
            loaded_local.append(src)
            if path.exists() and path.suffix == ".js":
                units.append((f"external:{src}", path.read_text(encoding="utf-8")))
        continue
    if body.strip():
        units.append((f"inline:{i}", body))

# V74 and related runtimes are often inlined by the canonical build. Also inspect any
# JS asset explicitly referenced by the final HTML, but do not sweep unrelated assets.

def compact(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def contexts(code: str, pattern: str, radius: int = 900):
    rx = re.compile(pattern, re.I | re.S)
    for idx, m in enumerate(rx.finditer(code), start=1):
        lo = max(0, m.start() - radius)
        hi = min(len(code), m.end() + radius)
        yield idx, compact(code[lo:hi])


def flags(snippet: str) -> str:
    checks = {
        "cvFastWorkout": "cvFastWorkout" in snippet,
        "content": "getElementById('content')" in snippet or 'getElementById("content")' in snippet,
        "innerHTML": "innerHTML" in snippet,
        "textContent": "textContent" in snippet,
        "classList": "classList" in snippet,
        "insertHTML": "insertAdjacentHTML" in snippet,
        "render": "render" in snippet,
        "RAF": "requestAnimationFrame" in snippet,
    }
    return ",".join(k for k, v in checks.items() if v) or "none"

print("CV_V76_STATIC_BEGIN")
print(f"CV_V76_STATIC_ARTIFACT bytes={len(html.encode('utf-8'))} inline_or_loaded_js={len(units)}")
print("CV_V76_STATIC_LOCAL_SCRIPTS " + (" | ".join(loaded_local) if loaded_local else "none"))

aggregate = {
    "MutationObserver": 0,
    "requestAnimationFrame": 0,
    "setInterval": 0,
    "window.render": 0,
    "innerHTML": 0,
    "cvFastWorkout": 0,
    "startTimer": 0,
}

for name, code in units:
    counts = {
        "MutationObserver": len(re.findall(r"\bMutationObserver\b", code)),
        "requestAnimationFrame": len(re.findall(r"\brequestAnimationFrame\b", code)),
        "setInterval": len(re.findall(r"\bsetInterval\b", code)),
        "window.render": len(re.findall(r"window\.render", code)),
        "innerHTML": len(re.findall(r"\.innerHTML\b", code)),
        "cvFastWorkout": len(re.findall(r"cvFastWorkout", code)),
        "startTimer": len(re.findall(r"\bstartTimer\b", code)),
    }
    for k, v in counts.items():
        aggregate[k] += v
    if any(counts.values()):
        summary = " ".join(f"{k}={v}" for k, v in counts.items())
        print(f"CV_V76_UNIT {name} {summary}")

    for idx, snippet in contexts(code, r"new\s+MutationObserver\s*\(|\bMutationObserver\s*\(", 1250):
        print(f"CV_V76_OBSERVER unit={name} n={idx} flags={flags(snippet)} :: {snippet}")

    for idx, snippet in contexts(code, r"window\.render\s*=|const\s+baseRender\s*=\s*window\.render|let\s+baseRender\s*=\s*window\.render", 850):
        print(f"CV_V76_RENDER_WRAP unit={name} n={idx} flags={flags(snippet)} :: {snippet}")

    for idx, snippet in contexts(code, r"\bsetInterval\s*\(", 650):
        print(f"CV_V76_INTERVAL unit={name} n={idx} flags={flags(snippet)} :: {snippet}")

print("CV_V76_STATIC_TOTALS " + " ".join(f"{k}={v}" for k, v in aggregate.items()))

# High-signal final-artifact contracts. These are informational, not hypotheses.
for token in [
    "cv-workout-active-dom-stability-v76: mutation-safe-v31-enhance",
    "cv-workout-compact-stability-v76: mutation-safe-v40-sync",
    "cv-rank-home-stability-v76: mutation-safe-v61-home-decoration",
    "CVWorkoutControllerV71",
    "CVWorkoutNumpadV73",
    "CVWorkoutSetGuardV74",
    "historyDecorate",
    "executionButtons",
]:
    print(f"CV_V76_TOKEN {token}={int(token in html or any(token in code for _, code in units))}")

print("CV_V76_STATIC_OK")
