from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PORTAL = ROOT / 'client-portal/index.html'
html = PORTAL.read_text(encoding='utf-8')
marker = 'cv-client-header-option3-v37'
if marker in html:
    print('HEADER_OPTION3_V37_ALREADY_PRESENT')
    raise SystemExit(0)

payload = r'''
<style id="cv-client-header-option3-v37">
/* CV Coach · Mobile Header Option 3 V37
   Compact header: brand first, routine space preserved. */
@media(max-width:699px){
  .top{
    height:92px!important;
    min-height:92px!important;
    padding:calc(8px + env(safe-area-inset-top)) 14px 8px!important;
    display:grid!important;
    grid-template-columns:136px minmax(82px,1fr) 102px!important;
    gap:8px!important;
    align-items:center!important;
    background:rgba(3,7,9,.975)!important;
    border-bottom:1px solid rgba(67,184,255,.18)!important;
    box-shadow:0 8px 28px rgba(0,0,0,.26)!important;
  }
  .top .cvBrandOfficial{
    width:136px!important;
    min-width:136px!important;
    height:70px!important;
    display:flex!important;
    align-items:center!important;
    justify-content:flex-start!important;
    overflow:visible!important;
  }
  .cvOfficialHeaderImg{
    display:block!important;
    width:132px!important;
    max-width:132px!important;
    height:68px!important;
    object-fit:contain!important;
    object-position:left center!important;
    filter:drop-shadow(0 5px 12px rgba(0,0,0,.58)) drop-shadow(0 0 11px rgba(255,34,54,.14))!important;
  }
  .top .cvLogoMark,.top .brand{display:none!important}

  .top .topTitle{
    min-width:0!important;
    margin:0!important;
    align-self:center!important;
    justify-self:center!important;
    text-align:center!important;
  }
  .cvHeaderIdentity{
    min-width:0!important;
    display:flex!important;
    align-items:center!important;
    justify-content:center!important;
    text-align:center!important;
    line-height:1!important;
  }
  .cvHeaderIdentity b{
    display:block!important;
    font:900 20px/1 'Barlow Condensed',Inter,sans-serif!important;
    letter-spacing:.075em!important;
    text-transform:uppercase!important;
    color:#f7f9fa!important;
    white-space:nowrap!important;
    overflow:visible!important;
  }
  .cvHeaderIdentity small{display:none!important}

  .topRight{
    width:102px!important;
    min-width:102px!important;
    margin:0!important;
    display:flex!important;
    align-items:center!important;
    justify-content:flex-end!important;
    gap:6px!important;
  }
  .topRight .demoBadge,
  .topRight .cvNotificationButton,
  .topRight [data-cv-notifications],
  .topRight button[aria-label*="Notific" i]{display:none!important}
  .cvSoundToggle{
    width:44px!important;
    height:44px!important;
    min-width:44px!important;
    min-height:44px!important;
    padding:0!important;
    border-radius:12px!important;
    font-size:20px!important;
  }
  .logout{
    min-width:50px!important;
    min-height:44px!important;
    padding:0 8px!important;
    border:1px solid #33434c!important;
    border-radius:12px!important;
    background:#0a1115!important;
    color:#eef3f5!important;
    font-size:13px!important;
    font-weight:800!important;
  }

  /* Sticky workout elements must follow the compact 92px header. */
  .workoutTop{top:92px!important}
}

@media(max-width:390px){
  .top{
    grid-template-columns:122px minmax(66px,1fr) 96px!important;
    gap:5px!important;
    padding-left:10px!important;
    padding-right:10px!important;
  }
  .top .cvBrandOfficial{width:122px!important;min-width:122px!important}
  .cvOfficialHeaderImg{width:120px!important;max-width:120px!important;height:64px!important}
  .cvHeaderIdentity b{font-size:18px!important;letter-spacing:.055em!important}
  .topRight{width:96px!important;min-width:96px!important;gap:4px!important}
  .cvSoundToggle{width:42px!important;height:42px!important;min-width:42px!important;min-height:42px!important}
  .logout{min-width:48px!important;min-height:42px!important;padding:0 6px!important;font-size:12px!important}
}
</style>
<script id="cv-client-header-option3-v37-js">
(function(){
  function enforceCompactHeader(){
    const top=document.querySelector('.top');
    if(!top)return;
    top.querySelectorAll('.demoBadge,.cvNotificationButton,[data-cv-notifications]').forEach(el=>el.style.setProperty('display','none','important'));
    top.querySelectorAll('button[aria-label]').forEach(btn=>{if(/notific/i.test(btn.getAttribute('aria-label')||''))btn.style.setProperty('display','none','important')});
    let identity=top.querySelector('.cvHeaderIdentity');
    if(identity){
      let b=identity.querySelector('b');
      if(!b){b=document.createElement('b');identity.prepend(b)}
      b.textContent='RUTINA';
      identity.querySelectorAll('small').forEach(el=>el.remove());
    }
  }
  const baseRender=window.render;
  if(typeof baseRender==='function')window.render=function(){const out=baseRender.apply(this,arguments);requestAnimationFrame(enforceCompactHeader);return out};
  const observer=new MutationObserver(()=>requestAnimationFrame(enforceCompactHeader));
  observer.observe(document.documentElement,{subtree:true,childList:true});
  document.addEventListener('DOMContentLoaded',enforceCompactHeader,{once:true});
  requestAnimationFrame(enforceCompactHeader);
})();
</script>
'''

anchor='</body>'
if anchor not in html:
    raise SystemExit('Missing </body> anchor')
html=html.replace(anchor,payload+'\n'+anchor,1)
PORTAL.write_text(html,encoding='utf-8')
print('HEADER_OPTION3_V37_PATCH_OK')
