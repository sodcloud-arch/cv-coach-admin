from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PORTAL = ROOT / "client-portal" / "index.html"
CONTRACTS = ROOT / "scripts" / "validate-repo-contracts.py"

html = PORTAL.read_text(encoding="utf-8")
contracts = CONTRACTS.read_text(encoding="utf-8")

if 'id="cv-client-workout-v35"' in html:
    raise SystemExit("v35 already present")

style = r'''
<style id="cv-client-workout-v35">
/* CV Coach Client Workout V35
   Rest countdown = high-attention red. Technique CTA = explicit informational blue. */
body.cvFastWorkout .cvRestVisualV32{
  min-height:92px!important;
  padding:13px 14px 13px 18px!important;
  border:1px solid rgba(255,59,79,.70)!important;
  background:
    radial-gradient(circle at 8% 50%,rgba(255,49,72,.16),transparent 34%),
    linear-gradient(145deg,rgba(20,9,13,.992),rgba(8,7,10,.995))!important;
  box-shadow:0 24px 72px rgba(0,0,0,.72),0 0 38px rgba(255,45,68,.16)!important;
}
body.cvFastWorkout .cvRestVisualV32:before{
  content:'';position:absolute;left:0;top:13px;bottom:13px;width:4px;border-radius:0 5px 5px 0;
  background:linear-gradient(180deg,#ff6b7b,#e11d2e);box-shadow:0 0 18px rgba(255,45,68,.44)
}
body.cvFastWorkout .cvRestVisualCopy small{
  color:#ff7180!important;font-size:9px!important;letter-spacing:.16em!important
}
body.cvFastWorkout .cvRestVisualMain{gap:12px!important;margin-top:4px!important}
body.cvFastWorkout .cvRestVisualMain b{
  color:#ff4b61!important;font-size:46px!important;line-height:.92!important;letter-spacing:-.055em!important;
  text-shadow:0 0 22px rgba(255,59,79,.24)
}
body.cvFastWorkout .cvRestVisualMain span{color:#b9c2c7!important;font-size:10px!important;max-width:240px!important}
body.cvFastWorkout .cvRestVisualActions button{
  height:42px!important;border-color:#3b3035!important;background:#120d10!important;color:#d8dfe2!important
}
body.cvFastWorkout .cvRestVisualActions button:first-child{border-color:rgba(255,59,79,.35)!important;color:#ff98a4!important}
body.cvFastWorkout .cvRestVisualV32.ready{
  border-color:rgba(94,227,165,.58)!important;
  background:linear-gradient(145deg,rgba(9,25,18,.992),rgba(6,12,9,.995))!important;
  box-shadow:0 24px 72px rgba(0,0,0,.72),0 0 34px rgba(94,227,165,.12)!important
}
body.cvFastWorkout .cvRestVisualV32.ready:before{background:linear-gradient(180deg,#83f2ba,#43bd7d);box-shadow:0 0 18px rgba(94,227,165,.30)}
body.cvFastWorkout .cvRestVisualV32.ready .cvRestVisualCopy small,
body.cvFastWorkout .cvRestVisualV32.ready .cvRestVisualMain b{color:#7af0b5!important;text-shadow:none!important}

/* Explicit technique/execution affordance beside exercise title. */
.cvExerciseTitleRowV35{display:flex;align-items:center;gap:9px;flex-wrap:wrap;min-width:0;margin:0 0 5px}
body.cvFastWorkout .cvExerciseTitleRowV35 h3{margin:0!important;min-width:0;max-width:100%}
body.cvFastWorkout .cvExerciseTitleRowV35 h3:after{display:none!important}
.cvExecutionBtnV35{
  flex:0 0 auto;min-height:31px;padding:0 10px;border:1px solid rgba(67,184,255,.34);border-radius:9px;
  background:rgba(67,184,255,.075);color:#83d4ff;font-size:8px;font-weight:900;letter-spacing:.07em;
  text-transform:uppercase;cursor:pointer;display:inline-flex;align-items:center;gap:6px;touch-action:manipulation;
  transition:background .16s ease,border-color .16s ease,transform .16s ease
}
.cvExecutionBtnV35:before{content:'▶';font-size:9px;line-height:1}
.cvExecutionBtnV35:active{transform:scale(.97);background:rgba(67,184,255,.13)}
.cvExecutionBtnV35:focus-visible{outline:2px solid #43b8ff;outline-offset:2px}
@media(hover:hover){.cvExecutionBtnV35:hover{background:rgba(67,184,255,.13);border-color:rgba(67,184,255,.58)}}

@media(max-width:767px){
  body.cvFastWorkout .cvRestVisualV32{min-height:94px!important;padding:13px 11px 13px 16px!important}
  body.cvFastWorkout .cvRestVisualMain b{font-size:43px!important}
  body.cvFastWorkout .cvRestVisualMain span{max-width:112px!important;font-size:8.5px!important}
  body.cvFastWorkout .cvRestVisualActions{gap:4px!important}
  body.cvFastWorkout .cvRestVisualActions button{height:39px!important;padding:0 7px!important;font-size:8px!important}
  .cvExerciseTitleRowV35{gap:7px;margin-bottom:5px}
  .cvExecutionBtnV35{min-height:30px;padding:0 9px;font-size:7.5px}
}
@media(max-width:390px){
  body.cvFastWorkout .cvRestVisualMain b{font-size:40px!important}
  .cvExerciseTitleRowV35{align-items:flex-start}
  .cvExecutionBtnV35{width:auto}
}
</style>
'''

script = r'''
<script id="cv-client-workout-v35-js">
(function(){
  function executionButtons(){
    if(!document.body.classList.contains('cvFastWorkout'))return;
    document.querySelectorAll('.cvHevyExercise').forEach((card,i)=>{
      const grow=card.querySelector('.exerciseTop .grow'),title=grow?.querySelector('h3');
      if(!grow||!title)return;
      let row=grow.querySelector(':scope > .cvExerciseTitleRowV35');
      if(!row){
        row=document.createElement('div');row.className='cvExerciseTitleRowV35';
        grow.insertBefore(row,title);row.appendChild(title);
      }
      let button=row.querySelector('.cvExecutionBtnV35');
      if(!button){
        button=document.createElement('button');button.type='button';button.className='cvExecutionBtnV35';button.textContent='VER EJECUCIÓN';
        button.setAttribute('aria-label','Ver ejecución de '+(card.getAttribute('data-tech-name')||title.textContent||('ejercicio '+(i+1))));
        button.addEventListener('click',event=>{event.preventDefault();event.stopPropagation();if(typeof window.cvOpenTechnique==='function')window.cvOpenTechnique(i)});
        row.appendChild(button);
      }
      title.setAttribute('title','Ver ejecución');
    });
  }
  const baseRender=window.render;
  window.render=function(){const result=baseRender.apply(this,arguments);requestAnimationFrame(executionButtons);return result};
  const observer=new MutationObserver(()=>{if(document.body.classList.contains('cvFastWorkout'))requestAnimationFrame(executionButtons)});
  observer.observe(document.getElementById('content')||document.body,{childList:true,subtree:true});
  requestAnimationFrame(executionButtons);
})();
</script>
'''

marker = "\n</body></html>"
if html.count(marker) != 1:
    raise SystemExit(f"expected one body marker, found {html.count(marker)}")
html = html.replace(marker, "\n" + style + "\n" + script + marker, 1)

# Add lightweight regression markers to repository contracts.
anchor = 'require(client_portal, "cv-client-semantic-v34", "client semantic palette cleanup")\n'
if anchor in contracts:
    contracts = contracts.replace(anchor, anchor +
        'require(client_portal, "cv-client-workout-v35", "large red rest countdown and execution CTA styles")\n'
        'require(client_portal, "cvExecutionBtnV35", "explicit client exercise execution button")\n'
        'require(client_portal, "VER EJECUCIÓN", "client execution CTA copy")\n', 1)
else:
    # Contracts evolve; append checks next to other client portal checks without making the patch brittle.
    needle = 'print("Repository contracts OK")'
    if needle not in contracts:
        raise SystemExit("contracts success anchor not found")
    contracts = contracts.replace(needle,
        'require(client_portal, "cv-client-workout-v35", "large red rest countdown and execution CTA styles")\n'
        'require(client_portal, "cvExecutionBtnV35", "explicit client exercise execution button")\n'
        'require(client_portal, "VER EJECUCIÓN", "client execution CTA copy")\n\n' + needle, 1)

PORTAL.write_text(html, encoding="utf-8")
CONTRACTS.write_text(contracts, encoding="utf-8")
print("CLIENT_REST_EXECUTION_V35_PATCH_OK")
