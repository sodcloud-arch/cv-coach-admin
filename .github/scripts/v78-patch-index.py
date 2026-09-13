from pathlib import Path

path = Path("index.html")
text = path.read_text(encoding="utf-8")
tag = '<script src="/admin-assets/v78-library.js"></script>'

if tag in text:
    raise SystemExit(0)
if "</body>" not in text:
    raise SystemExit("index.html has no closing body tag")

path.write_text(text.replace("</body>", tag + "</body>", 1), encoding="utf-8")
