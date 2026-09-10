from pathlib import Path

path=Path('client-portal/index.html')
text=path.read_text()

def once(old,new,label):
    global text
    count=text.count(old)
    if count!=1:
        raise SystemExit(f'{label}: expected 1 anchor, found {count}')
    text=text.replace(old,new,1)

style='''<style id="cv-rir-v1-css">
/* RIR real por serie: compacto, opcional y sin popup. */
body.cvFastWorkout .cvSetsHead,body.cvFastWorkout .cvSetRow{grid-template-columns:40px minmax(62px,1fr) 64px 58px 52px 43px!important;gap:4px!important}
body.cvFastWorkout .cvSetRow .cvRirInput{height:47px!important;font-size:18px!important;padding:0 3px!important}
body.cvFastWorkout .cvSetsHead span:nth-child(5){color:#ff7180!important}
@media(min-width:768px){body.cvFastWorkout .cvSetsHead,body.cvFastWorkout .cvSetRow{grid-template-columns:44px minmax(84px,1fr) 80px 70px 60px 48px!important;gap:6px!important}body.cvFastWorkout .cvSetRow .cvRirInput{height:50px!important;font-size:19px!important}}
@media(max-width:370px){body.cvFastWorkout .cvSetsHead,body.cvFastWorkout .cvSetRow{grid-template-columns:37px minmax(58px,1fr) 60px 54px 48px 40px!important;gap:3px!important}body.cvFastWorkout .cvSetRow .cvRirInput{font-size:17px!important}}
</style>'''
if 'id="cv-rir-v1-css"' not in text:
    once('</head>',style+'\n</head>','head style injection')

once(
"sets:Array.from({length:sets},(_,j)=>({set_log_id:null,set_number:j+1,suggested_weight_kg:null,suggested_reps:b[0],weight_kg:null,reps:null,completed:false,suggestion_source:'program_prescription'}))",
"sets:Array.from({length:sets},(_,j)=>({set_log_id:null,set_number:j+1,suggested_weight_kg:null,suggested_reps:b[0],weight_kg:null,reps:null,rir:null,completed:false,suggestion_source:'program_prescription'}))",
'demo/prestart set RIR'
)

once(
"const w=document.getElementById('cvw_'+i+'_'+j),r=document.getElementById('cvr_'+i+'_'+j);const wt=w&&w.value!==''?Number(w.value):null, rp=r&&r.value!==''?Number(r.value):null;if(wt!=null&&!Number.isFinite(wt))return null;if(rp!=null&&(!Number.isFinite(rp)||rp<0))return null;s.weight_kg=wt;s.reps=rp==null?null:Math.round(rp);return {ex,s,weight_kg:wt,reps:s.reps}",
"const w=document.getElementById('cvw_'+i+'_'+j),r=document.getElementById('cvr_'+i+'_'+j),ri=document.getElementById('cvri_'+i+'_'+j);const wt=w&&w.value!==''?Number(w.value):null, rp=r&&r.value!==''?Number(r.value):null, rir=ri&&ri.value!==''?Number(ri.value):null;if(wt!=null&&!Number.isFinite(wt))return null;if(rp!=null&&(!Number.isFinite(rp)||rp<0))return null;if(rir!=null&&(!Number.isFinite(rir)||rir<0||rir>10))return null;s.weight_kg=wt;s.reps=rp==null?null:Math.round(rp);s.rir=rir;return {ex,s,weight_kg:wt,reps:s.reps,rir}",
'cvSetFromInputs RIR'
)

once(
"update({weight_kg:p.weight_kg,reps:p.reps,source:'manual'})",
"update({weight_kg:p.weight_kg,reps:p.reps,rir:p.rir,source:'manual'})",
'draft save RIR'
)

once(
"update({weight_kg:p.weight_kg,reps:p.reps,completed:next,completed_at:next?new Date().toISOString():null,source:'manual'})",
"update({weight_kg:p.weight_kg,reps:p.reps,rir:p.rir,completed:next,completed_at:next?new Date().toISOString():null,source:'manual'})",
'legacy toggle RIR'
)

once(
"<span>SET</span><span>ANTERIOR</span><span>KG</span><span>REPS</span><span>✓</span>",
"<span>SET</span><span>ANTERIOR</span><span>KG</span><span>REPS</span><span>RIR</span><span>✓</span>",
'workout table RIR header'
)

once(
"<input id=\"cvr_'+i+'_'+j+'\" inputmode=\"numeric\" type=\"number\" min=\"0\" step=\"1\" value=\"'+esc(cvInputValue(s.reps,s.suggested_reps))+'\" onchange=\"cvSaveDraftSet('+i+','+j+')\"><button class=\"cvSetCheck",
"<input id=\"cvr_'+i+'_'+j+'\" inputmode=\"numeric\" type=\"number\" min=\"0\" step=\"1\" value=\"'+esc(cvInputValue(s.reps,s.suggested_reps))+'\" onchange=\"cvSaveDraftSet('+i+','+j+')\"><input id=\"cvri_'+i+'_'+j+'\" class=\"cvRirInput\" inputmode=\"decimal\" type=\"number\" min=\"0\" max=\"10\" step=\"0.5\" placeholder=\"—\" value=\"'+esc(s.rir??'')+'\" onchange=\"cvSaveDraftSet('+i+','+j+')\" aria-label=\"RIR real serie '+(j+1)+' de '+esc(e.name)+'\"><button class=\"cvSetCheck",
'workout row RIR input'
)

once(
"const wi=document.getElementById('cvw_'+i+'_'+j),ri=document.getElementById('cvr_'+i+'_'+j),w=wi&&wi.value!==''?Number(wi.value):null,r=ri&&ri.value!==''?Math.round(Number(ri.value)):null;if(w!=null&&!Number.isFinite(w))return toast?.('Revisa el peso.');if(r==null||!Number.isFinite(r)||r<=0)return toast?.('Ingresa las repeticiones realizadas.');\n    const next=!s.completed,old={w:s.weight_kg,r:s.reps,c:s.completed};s.weight_kg=w;s.reps=r;s.completed=next;",
"const wi=document.getElementById('cvw_'+i+'_'+j),ri=document.getElementById('cvr_'+i+'_'+j),riri=document.getElementById('cvri_'+i+'_'+j),w=wi&&wi.value!==''?Number(wi.value):null,r=ri&&ri.value!==''?Math.round(Number(ri.value)):null,rir=riri&&riri.value!==''?Number(riri.value):null;if(w!=null&&!Number.isFinite(w))return toast?.('Revisa el peso.');if(r==null||!Number.isFinite(r)||r<=0)return toast?.('Ingresa las repeticiones realizadas.');if(rir!=null&&(!Number.isFinite(rir)||rir<0||rir>10))return toast?.('RIR debe estar entre 0 y 10.');\n    const next=!s.completed,old={w:s.weight_kg,r:s.reps,rir:s.rir,c:s.completed};s.weight_kg=w;s.reps=r;s.rir=rir;s.completed=next;",
'v25 toggle read RIR'
)

once(
"update({weight_kg:w,reps:r,completed:next,completed_at:next?new Date().toISOString():null,source:'manual'})",
"update({weight_kg:w,reps:r,rir,completed:next,completed_at:next?new Date().toISOString():null,source:'manual'})",
'v25 database toggle RIR'
)

once(
"s.weight_kg=old.w;s.reps=old.r;s.completed=old.c;",
"s.weight_kg=old.w;s.reps=old.r;s.rir=old.rir;s.completed=old.c;",
'v25 rollback RIR'
)

# Input draft preservation in cv-night: include RIR fields in delegated draft layer without changing its weight/reps object semantics.
once(
"document.addEventListener('input',e=>{const inp=e.target;if(!(inp instanceof HTMLInputElement))return;const m=inp.id.match(/^cv([wr])_(\\d+)_(\\d+)$/);if(m)readDraft(Number(m[2]),Number(m[3]))},true);",
"document.addEventListener('input',e=>{const inp=e.target;if(!(inp instanceof HTMLInputElement))return;const m=inp.id.match(/^cv([wr])_(\\d+)_(\\d+)$/);if(m)readDraft(Number(m[2]),Number(m[3]))},true);",
'draft listener presence'
)

required=[
'id="cv-rir-v1-css"','<span>RIR</span>','id="cvri_',"rir:p.rir","update({weight_kg:w,reps:r,rir,completed:next",
"RIR debe estar entre 0 y 10.","s.rir=rir","s.rir=old.rir"
]
missing=[x for x in required if x not in text]
if missing: raise SystemExit('Missing RIR markers: '+', '.join(missing))
if text.count('id="cvri_') != 1: raise SystemExit('Unexpected RIR input template count')
path.write_text(text)
