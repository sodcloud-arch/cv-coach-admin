from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
HTML=ROOT/'index.html'
MARKER='<!-- cv-admin-adaptive-programming-v84 -->'
text=HTML.read_text(encoding='utf-8')
if MARKER not in text:
    if '</body>' not in text:
        raise SystemExit('Admin V84 body anchor missing')
    header='<div class="row"><button id="back" class="btn small">← Volver</button><button id="openClientReport" class="btn primary small">VER INFORME</button></div>'
    if header not in text:
        raise SystemExit('Admin V84 client header anchor missing')
    text=text.replace(header,'<div class="row"><button id="back" class="btn small">← Volver</button><button id="openClientReport" class="btn primary small">VER INFORME</button><button id="openTrainingTrendsV84" class="btn small">TENDENCIAS V84</button></div>',1)
    bind="$('#openClientReport').onclick=()=>{reportClientId=id;setView('reports')};"
    if bind not in text:
        raise SystemExit('Admin V84 report binding anchor missing')
    text=text.replace(bind,bind+"if($('#openTrainingTrendsV84'))$('#openTrainingTrendsV84').onclick=()=>openTrainingTrendsV84(id);",1)
    text=text.replace('</body>','<script src="/admin-assets/cv-adaptive-programming-admin-v84.js"></script>'+MARKER+'</body>',1)
for item in [MARKER,'id="openTrainingTrendsV84"','TENDENCIAS V84','openTrainingTrendsV84(id)','/admin-assets/cv-adaptive-programming-admin-v84.js']:
    if item not in text:
        raise SystemExit(f'Admin V84 contract missing: {item}')
HTML.write_text(text,encoding='utf-8')
print('CV_ADMIN_ADAPTIVE_PROGRAMMING_V84_PATCHED')
