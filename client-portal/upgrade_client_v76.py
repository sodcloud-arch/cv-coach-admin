from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parent
HTML = ROOT / "stable" / "index.html"
BUILD = ROOT / "stable" / "build.json"
MARKER = "<!-- cv-workout-v76-idempotent-dom: mutation-observer-safe -->"

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


# V31 watches #content childList mutations. These visual helpers must therefore
# be idempotent: a second pass with identical state cannot mutate child nodes.
old_rir = """    el.replaceChildren(...raw.map(text=>{const s=document.createElement('span');s.className='cvPrescriptionChip';s.textContent=text;return s}));
"""
new_rir = """    const cvRirSignatureV76=raw.join('\\u001f');
    if(el.dataset.cvRirSignatureV76===cvRirSignatureV76)return;
    el.dataset.cvRirSignatureV76=cvRirSignatureV76;
    el.replaceChildren(...raw.map(text=>{const s=document.createElement('span');s.className='cvPrescriptionChip';s.textContent=text;return s}));
"""
replace_once_or_keep(old_rir, new_rir, "v31 RIR prescription idempotence")

old_badge = """      if(badge){badge.className='cvExerciseStatusV31 '+(complete?'complete':current?'current':'pending');badge.textContent=complete?'COMPLETADO':current?'AHORA':'PENDIENTE'}
"""
new_badge = """      if(badge){badge.className='cvExerciseStatusV31 '+(complete?'complete':current?'current':'pending');const cvBadgeTextV76=complete?'COMPLETADO':current?'AHORA':'PENDIENTE';if(badge.textContent!==cvBadgeTextV76)badge.textContent=cvBadgeTextV76}
"""
replace_once_or_keep(old_badge, new_badge, "v31 exercise badge idempotence")

if "cvHeroSignatureV76" not in text:
    hero_pattern = re.compile(
        r"(    const estimated=d\?\.estimated_minutes\?\?null;\n)"
        r"    h\.innerHTML=(.+?);\n"
        r"  \}\n  function aria\(\)",
        re.S,
    )
    match = hero_pattern.search(text)
    if not match:
        raise SystemExit("v31 hero idempotence: canonical hero block not found")
    markup_expr = match.group(2)
    replacement = (
        match.group(1)
        + "    const cvHeroSignatureV76=JSON.stringify([workout?.dayId||'',d?.name||'',d?.focus||'',estimated,state.totalExercises,state.totalSets,state.doneSets,state.doneExercises,pct]);\n"
        + "    if(h.dataset.cvHeroSignatureV76!==cvHeroSignatureV76){\n"
        + "      h.dataset.cvHeroSignatureV76=cvHeroSignatureV76;\n"
        + "      h.innerHTML="
        + markup_expr
        + ";\n"
        + "    }\n"
        + "  }\n  function aria()"
    )
    text = text[: match.start()] + replacement + text[match.end() :]
else:
    if text.count("cvHeroSignatureV76") < 2:
        raise SystemExit("v31 hero idempotence: partial V76 state")

if MARKER not in text:
    if "</body>" not in text:
        raise SystemExit("V76 marker: </body> missing")
    text = text.replace("</body>", MARKER + "\n</body>", 1)

required = [
    "cvRirSignatureV76",
    "cvBadgeTextV76",
    "cvHeroSignatureV76",
    "if(h.dataset.cvHeroSignatureV76!==cvHeroSignatureV76)",
    MARKER,
]
for item in required:
    if item not in text:
        raise SystemExit(f"V76 idempotence marker missing: {item}")

forbidden = [
    "if(badge){badge.className='cvExerciseStatusV31 '+(complete?'complete':current?'current':'pending');badge.textContent=complete?'COMPLETADO':current?'AHORA':'PENDIENTE'}",
    "    el.replaceChildren(...raw.map(text=>{const s=document.createElement('span');s.className='cvPrescriptionChip';s.textContent=text;return s}));\n  }\n  function hideRir()",
]
for item in forbidden:
    if item in text:
        raise SystemExit(f"V76 legacy self-mutation remained: {item[:72]}")

HTML.write_text(text, encoding="utf-8")

metadata = {}
if BUILD.exists():
    try:
        metadata = json.loads(BUILD.read_text(encoding="utf-8"))
    except Exception:
        metadata = {}
patches = list(metadata.get("patches") or [])
patch = "v76 workout V31 DOM mutations made idempotent"
if patch not in patches:
    patches.append(patch)
metadata["patches"] = patches
metadata["bytes"] = len(text.encode("utf-8"))
BUILD.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

print(json.dumps({"marker": MARKER, "bytes": metadata["bytes"], "patch": patch}, ensure_ascii=False))
