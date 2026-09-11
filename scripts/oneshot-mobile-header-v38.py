from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
PORTAL = ROOT / "client-portal/index.html"
text = PORTAL.read_text(encoding="utf-8")

pattern = re.compile(
    r'<style id="cv-client-header-option3-v37">.*?</style>\s*<script id="cv-client-header-option3-v37-js">.*?</script>',
    re.S,
)

replacement = r'''<style id="cv-client-header-v38">
/* CV Coach · Mobile Header V38
   One-row brand-first header. Replaces V37 instead of stacking another layer. */
@media(max-width:699px){
  .top{
    height:calc(76px + env(safe-area-inset-top))!important;
    min-height:calc(76px + env(safe-area-inset-top))!important;
    padding:env(safe-area-inset-top) 12px 0!important;
    display:grid!important;
    grid-template-columns:minmax(128px,45%) minmax(58px,1fr) max-content!important;
    column-gap:8px!important;
    align-items:center!important;
    background:rgba(3,7,9,.985)!important;
    border-bottom:1px solid rgba(67,184,255,.18)!important;
    box-shadow:0 7px 24px rgba(0,0,0,.24)!important;
    overflow:visible!important;
  }

  /* Brand is the dominant visual element. */
  .top .cvBrandOfficial{
    width:100%!important;
    min-width:0!important;
    height:76px!important;
    display:flex!important;
    align-items:center!important;
    justify-content:flex-start!important;
    overflow:visible!important;
    margin:0!important;
    padding:0!important;
  }
  .cvOfficialHeaderImg{
    display:block!important;
    width:144px!important;
    max-width:100%!important;
    height:auto!important;
    max-height:50px!important;
    object-fit:contain!important;
    object-position:left center!important;
    filter:drop-shadow(0 5px 12px rgba(0,0,0,.56)) drop-shadow(0 0 12px rgba(255,34,54,.13))!important;
  }
  .top .cvLogoMark,.top .brand{display:none!important}

  /* One-line context, never a second row. */
  .top .topTitle{
    min-width:0!important;
    width:100%!important;
    margin:0!important;
    padding:0!important;
    align-self:center!important;
    justify-self:center!important;
    text-align:center!important;
  }
  .cvHeaderIdentity{
    min-width:0!important;
    width:100%!important;
    display:flex!important;
    align-items:center!important;
    justify-content:center!important;
    text-align:center!important;
    line-height:1!important;
    margin:0!important;
  }
  .cvHeaderIdentity b{
    display:block!important;
    margin:0!important;
    font:900 19px/1 'Barlow Condensed',Inter,sans-serif!important;
    letter-spacing:.055em!important;
    text-transform:uppercase!important;
    color:#f7f9fa!important;
    white-space:nowrap!important;
  }
  .cvHeaderIdentity small{display:none!important}

  /* Utilities remain useful but secondary to brand/content. */
  .topRight{
    width:auto!important;
    min-width:0!important;
    margin:0!important;
    display:flex!important;
    align-items:center!important;
    justify-content:flex-end!important;
    gap:8px!important;
    white-space:nowrap!important;
  }
  .topRight .demoBadge,
  .topRight .cvNotificationButton,
  .topRight [data-cv-notifications],
  .topRight button[aria-label*="Notific" i]{display:none!important}
  .cvSoundToggle{
    width:40px!important;
    height:40px!important;
    min-width:40px!important;
    min-height:40px!important;
    padding:0!important;
    border-radius:11px!important;
    font-size:18px!important;
    background:#091116!important;
    border:1px solid #2b3c46!important;
  }
  .logout{
    min-width:0!important;
    height:40px!important;
    min-height:40px!important;
    padding:0 12px!important;
    border:1px solid #2b3b44!important;
    border-radius:11px!important;
    background:#091015!important;
    color:#eef3f5!important;
    font-size:14px!important;
    line-height:1!important;
    font-weight:800!important;
  }

  /* Sticky workout controls follow the real header height. */
  .workoutTop{top:calc(76px + env(safe-area-inset-top))!important}
}

@media(max-width:390px){
  .top{
    padding-left:10px!important;
    padding-right:10px!important;
    grid-template-columns:minmax(118px,44%) minmax(54px,1fr) max-content!important;
    column-gap:6px!important;
  }
  .cvOfficialHeaderImg{
    width:128px!important;
    max-width:100%!important;
    max-height:46px!important;
  }
  .cvHeaderIdentity b{font-size:18px!important;letter-spacing:.04em!important}
  .topRight{gap:6px!important}
  .cvSoundToggle{
    width:38px!important;
    height:38px!important;
    min-width:38px!important;
    min-height:38px!important;
    font-size:17px!important;
  }
  .logout{
    height:38px!important;
    min-height:38px!important;
    padding:0 9px!important;
    font-size:13px!important;
  }
}
</style>
<script id="cv-client-header-v38-js">
(function(){
  function enforceOneRowHeader(){
    const top=document.querySelector('.top');
    if(!top)return;

    top.querySelectorAll('.demoBadge,.cvNotificationButton,[data-cv-notifications]').forEach(el=>el.style.setProperty('display','none','important'));
    top.querySelectorAll('button[aria-label]').forEach(btn=>{
      if(/notific/i.test(btn.getAttribute('aria-label')||''))btn.style.setProperty('display','none','important');
    });

    const identity=top.querySelector('.cvHeaderIdentity');
    if(identity){
      let b=identity.querySelector('b');
      if(!b){b=document.createElement('b');identity.prepend(b)}
      b.textContent='RUTINA';
      identity.querySelectorAll('small').forEach(el=>el.remove());
    }

    const logo=top.querySelector('.cvOfficialHeaderImg');
    if(logo){
      logo.alt='Camilo Vásquez Fitness Coach';
      logo.setAttribute('aria-label','Camilo Vásquez Fitness Coach');
    }
  }

  const baseRender=window.render;
  if(typeof baseRender==='function'){
    window.render=function(){
      const out=baseRender.apply(this,arguments);
      requestAnimationFrame(enforceOneRowHeader);
      return out;
    };
  }

  const observer=new MutationObserver(()=>requestAnimationFrame(enforceOneRowHeader));
  observer.observe(document.documentElement,{subtree:true,childList:true});
  document.addEventListener('DOMContentLoaded',enforceOneRowHeader,{once:true});
  requestAnimationFrame(enforceOneRowHeader);
})();
</script>'''

updated, count = pattern.subn(replacement, text, count=1)
if count != 1:
    raise SystemExit(f"Expected exactly one V37 header block, found {count}")

required = [
    'id="cv-client-header-v38"',
    'id="cv-client-header-v38-js"',
    'width:144px!important',
    "b.textContent='RUTINA'",
    '.workoutTop{top:calc(76px + env(safe-area-inset-top))!important}',
]
for marker in required:
    if marker not in updated:
        raise SystemExit(f"Missing required marker: {marker}")

for forbidden in ['cv-client-header-option3-v37', 'cv-client-header-option3-v37-js']:
    if forbidden in updated:
        raise SystemExit(f"Legacy header block still present: {forbidden}")

PORTAL.write_text(updated, encoding="utf-8")
print("MOBILE_HEADER_V38_PATCH_OK")
