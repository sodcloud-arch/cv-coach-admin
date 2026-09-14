from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
HTML=ROOT/'index.html'
MARKER='<!-- cv-admin-progression-v83: adaptive progression center -->'
text=HTML.read_text(encoding='utf-8')
if MARKER not in text:
    if '</body>' not in text:
        raise SystemExit('Admin V83 body anchor missing')
    nav='<button data-v="programs">🏋️ Programación</button>'
    if nav not in text:
        raise SystemExit('Admin V83 programs nav anchor missing')
    text=text.replace(nav,nav+'<button data-v="progression">↗ Progresión</button>',1)
    title_anchor="programs:'Programación',alerts:'Alertas'"
    if title_anchor not in text:
        raise SystemExit('Admin V83 title map anchor missing')
    text=text.replace(title_anchor,"programs:'Programación',progression:'Centro de Progresión',alerts:'Alertas'",1)
    render_anchor="if(view==='programs')await programs();if(view==='alerts')"
    if render_anchor not in text:
        raise SystemExit('Admin V83 render anchor missing')
    text=text.replace(render_anchor,"if(view==='programs')await programs();if(view==='progression')await progressionCenter();if(view==='alerts')",1)
    text=text.replace('</body>','<script src="/admin-assets/cv-progression-admin-v83.js"></script>'+MARKER+'</body>',1)
for item in [MARKER,'data-v="progression"','Centro de Progresión',"view==='progression'",'/admin-assets/cv-progression-admin-v83.js']:
    if item not in text:
        raise SystemExit(f'Admin V83 contract missing: {item}')
HTML.write_text(text,encoding='utf-8')
print('CV_ADMIN_PROGRESSION_V83_PATCHED')
