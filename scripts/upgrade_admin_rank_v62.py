from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
HTML=ROOT/'index.html'
MARKER='<!-- cv-admin-rank-v62: ranking + seasons + challenges + rewards -->'
text=HTML.read_text(encoding='utf-8')
if MARKER not in text:
    if '</head>' not in text or '</body>' not in text:
        raise SystemExit('Admin V62 HTML anchors missing')
    text=text.replace('</head>','<link rel="stylesheet" href="/admin-assets/cv-rank-admin-v62.css"></head>',1)
    nav='<button data-v="alerts">⚠ Alertas</button>'
    if nav not in text: raise SystemExit('Admin V62 alerts nav anchor missing')
    text=text.replace(nav,nav+'<button data-v="ranking">🏆 Ranking CV</button>',1)
    title_anchor="alerts:'Alertas',plans:'Planes y suscripciones'"
    if title_anchor not in text: raise SystemExit('Admin V62 title map anchor missing')
    text=text.replace(title_anchor,"alerts:'Alertas',ranking:'Ranking y competencias',plans:'Planes y suscripciones'",1)
    render_anchor="if(view==='alerts')await alerts();if(view==='plans')"
    if render_anchor not in text: raise SystemExit('Admin V62 render anchor missing')
    text=text.replace(render_anchor,"if(view==='alerts')await alerts();if(view==='ranking')await rankCenter();if(view==='plans')",1)
    text=text.replace('</body>','<script src="/admin-assets/cv-rank-admin-v62.js"></script>'+MARKER+'</body>',1)
for item in [MARKER,'data-v="ranking"','Ranking y competencias',"view==='ranking'",'/admin-assets/cv-rank-admin-v62.js','/admin-assets/cv-rank-admin-v62.css']:
    if item not in text: raise SystemExit(f'Admin V62 contract missing: {item}')
HTML.write_text(text,encoding='utf-8')
print('CV_ADMIN_RANK_V62_PATCHED')
