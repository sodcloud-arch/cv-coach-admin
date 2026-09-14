from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
HTML=ROOT/'index.html'
MARKER='<!-- cv-admin-coach-intelligence-v86 -->'
text=HTML.read_text(encoding='utf-8')
if MARKER not in text:
    v85='<script src="/admin-assets/cv-mesocycle-intelligence-admin-v85.js"></script><!-- cv-admin-mesocycle-intelligence-v85 -->'
    if v85 not in text:
        raise SystemExit('Admin V86 requires V85 asset anchor')
    nav='<button data-v="progression">↗ Progresión</button>'
    if nav not in text:
        raise SystemExit('Admin V86 progression nav anchor missing')
    text=text.replace(nav,nav+'<button data-v="intelligence">🧠 Inteligencia</button>',1)
    title="progression:'Centro de Progresión',alerts:'Alertas'"
    if title not in text:
        raise SystemExit('Admin V86 title map anchor missing')
    text=text.replace(title,"progression:'Centro de Progresión',intelligence:'Coach Intelligence V86',alerts:'Alertas'",1)
    render="if(view==='progression')await progressionCenter();if(view==='alerts')"
    if render not in text:
        raise SystemExit('Admin V86 render anchor missing')
    text=text.replace(render,"if(view==='progression')await progressionCenter();if(view==='intelligence')await coachIntelligenceV86();if(view==='alerts')",1)
    text=text.replace(v85,v85+'<script src="/admin-assets/cv-coach-intelligence-admin-v86.js"></script>'+MARKER,1)
for item in [MARKER,'data-v="intelligence"','Coach Intelligence V86',"view==='intelligence'",'/admin-assets/cv-coach-intelligence-admin-v86.js']:
    if item not in text:
        raise SystemExit(f'Admin V86 contract missing: {item}')
HTML.write_text(text,encoding='utf-8')
print('CV_ADMIN_COACH_INTELLIGENCE_V86_PATCHED')
