from pathlib import Path

ROOT = Path(__file__).resolve().parent
HTML = ROOT / "stable" / "index.html"

text = HTML.read_text(encoding="utf-8")

broken = "if(cards[2])cards[2].querySelector('.v').textContent=Number(state.value.total_xp||0).toLocaleString('es-CL')}}}\n  function decorateWorkout()"
fixed = "if(cards[2])cards[2].querySelector('.v').textContent=Number(state.value.total_xp||0).toLocaleString('es-CL')}}\n  function decorateWorkout()"

if broken in text:
    text = text.replace(broken, fixed, 1)
elif fixed not in text:
    raise SystemExit("V60 repair target not found")

HTML.write_text(text, encoding="utf-8")
print("CV_RANK_V60_SYNTAX_REPAIR_OK")
