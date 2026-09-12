from pathlib import Path
import re
import subprocess

ROOT=Path(__file__).resolve().parent
HTML=ROOT/'stable'/'index.html'
GUARD=ROOT/'assets'/'cv-workout-set-guard-v74.js'
MARKER='<!-- cv-workout-set-guard-v74: single-flight-set-toggle + hydration-guard -->'
START_STABILITY_MARKER='<!-- cv-workout-start-stability-v76: preserve-v40-cta-during-v31-enhance -->'
COMPACT_STABILITY_MARKER='<!-- cv-workout-compact-stability-v76: mutation-safe-v40-sync -->'
SCRIPT_ID='cv-workout-set-guard-v74-js'

for p in [HTML,GUARD]:
    if not p.exists() or p.stat().st_size<300:
        raise SystemExit(f'CV V74 source missing: {p}')
subprocess.run(['node','--check',str(GUARD)],check=True)
guard=GUARD.read_text(encoding='utf-8')
for token in ['CVWorkoutSetGuardV74',"version:VERSION",'pending.has(k)','MIN_LOCK_MS=420','__cvSetGuardV74']:
    if token not in guard:
        raise SystemExit(f'V74 set guard contract missing: {token}')

text=HTML.read_text(encoding='utf-8')
text=re.sub(r'<script id="cv-workout-set-guard-v74-js">.*?</script>','',text,flags=re.S)
text=text.replace(MARKER,'')
text=text.replace(START_STABILITY_MARKER,'')
text=text.replace(COMPACT_STABILITY_MARKER,'')

# Boot/hydration hardening: historical post-render helpers can run before demo/real data
# is available. Return an empty prestart exercise list until the portal is hydrated.
pattern=r"function cvPrestartExercises\(\)\{\s*const d=data\.days\.find\(x=>x\.id===workout\.dayId\);const raw=data\.exercises\[d\.id\]\|\|\[\];"
replacement="function cvPrestartExercises(){\n    if(!data||!workout?.dayId||!Array.isArray(data.days))return [];\n    const d=data.days.find(x=>x.id===workout.dayId);if(!d)return [];const raw=(data.exercises&&data.exercises[d.id])||[];"
if re.search(pattern,text):
    text=re.sub(pattern,replacement,text,count=1)
elif 'if(!data||!workout?.dayId||!Array.isArray(data.days))return [];' not in text:
    raise SystemExit('V74 hydration guard target missing')

# V76 production-canary finding: V31 owns the workout hero presentation while V40
# owns the visible pre-start CTA inserted inside that hero. The V31 MutationObserver
# can run again after V40 appends the button; its unconditional h.innerHTML rewrite
# then detaches the CTA while a physical touch is being acquired. Freeze only the
# pre-start hero presentation while that authoritative V40 CTA exists. Once the
# workout starts, render() replaces the view and normal hero updates resume.
old_hero_owner="""    let h=content.querySelector('.cvWorkoutHeroV31');if(!h){h=document.createElement('section');h.className='cvWorkoutHeroV31';stats.parentNode.insertBefore(h,stats)}
    const estimated=d?.estimated_minutes??null;
    h.innerHTML="""
new_hero_owner="""    let h=content.querySelector('.cvWorkoutHeroV31');if(!h){h=document.createElement('section');h.className='cvWorkoutHeroV31';stats.parentNode.insertBefore(h,stats)}
    const estimated=d?.estimated_minutes??null;
    if(h.querySelector('.cvWorkoutStartV40'))return;
    h.innerHTML="""
if old_hero_owner in text:
    text=text.replace(old_hero_owner,new_hero_owner,1)
elif "if(h.querySelector('.cvWorkoutStartV40'))return;" not in text:
    raise SystemExit('V76 pre-start hero ownership target missing')

# V76 production-canary finding: after runtime consolidation, V40 owns a child-list /
# character-data MutationObserver. Its own sync functions must therefore never write
# identical DOM content, otherwise each observer pass creates the mutation that wakes
# the next pass. Make both pre-start copy and active compact header differential.
old_live="const live=hero.querySelector('.cvWorkoutLivePill');if(live)live.textContent='LISTO PARA INICIAR';"
new_live="const live=hero.querySelector('.cvWorkoutLivePill');if(live&&live.textContent!=='LISTO PARA INICIAR')live.textContent='LISTO PARA INICIAR';"
if old_live in text:
    text=text.replace(old_live,new_live,1)
elif new_live not in text:
    raise SystemExit('V76 V40 pre-start differential target missing')

old_compact="""    copy.innerHTML='<strong>'+esc(name)+'</strong><span><b>'+s.doneSets+'/'+s.totalSets+'</b> series · '+Math.round(s.volume).toLocaleString('es-CL')+' kg·reps · <em id=\"cvCompactTimerV40\">'+elapsedV40()+'</em> · '+s.pct+'%</span><span class=\"cvWorkoutCompactProgressV40\"><i style=\"width:'+s.pct+'%\"></i></span>';"""
new_compact="""    const compactHtmlV76='<strong>'+esc(name)+'</strong><span><b>'+s.doneSets+'/'+s.totalSets+'</b> series · '+Math.round(s.volume).toLocaleString('es-CL')+' kg·reps · <em id=\"cvCompactTimerV40\">'+elapsedV40()+'</em> · '+s.pct+'%</span><span class=\"cvWorkoutCompactProgressV40\"><i style=\"width:'+s.pct+'%\"></i></span>';
    if(copy.innerHTML!==compactHtmlV76)copy.innerHTML=compactHtmlV76;"""
if old_compact in text:
    text=text.replace(old_compact,new_compact,1)
elif 'if(copy.innerHTML!==compactHtmlV76)copy.innerHTML=compactHtmlV76;' not in text:
    raise SystemExit('V76 V40 active differential target missing')

# Inject after every historical workout wrapper so V74 owns the final toggle contract.
payload=f'\n{START_STABILITY_MARKER}\n{COMPACT_STABILITY_MARKER}\n{MARKER}\n<script id="{SCRIPT_ID}">\n{guard}\n</script>\n'
if '</body>' not in text:
    raise SystemExit('V74 body injection target missing')
text=text.replace('</body>',payload+'</body>',1)

# Final ownership / safety checks.
if text.rfind('CVWorkoutSetGuardV74') <= text.rfind('window.cvToggleSet='):
    raise SystemExit('V74 is not the final set-toggle owner')
for token in [MARKER,START_STABILITY_MARKER,COMPACT_STABILITY_MARKER,SCRIPT_ID,'CVWorkoutSetGuardV74','cv-workout-numpad-v73: native-keyboard-retired + custom-editor + deterministic-save','if(!data||!workout?.dayId||!Array.isArray(data.days))return [];',"if(h.querySelector('.cvWorkoutStartV40'))return;","live&&live.textContent!=='LISTO PARA INICIAR'",'if(copy.innerHTML!==compactHtmlV76)copy.innerHTML=compactHtmlV76;']:
    if token not in text:
        raise SystemExit(f'V74 stable artifact missing: {token}')

HTML.write_text(text,encoding='utf-8')
print('{"patches":["single-flight set toggle v74","420ms double-tap suppression v74","pre-hydration exercise guard v74","stable pre-start CTA ownership v76","mutation-safe V40 compact sync v76"],"bytes":%d}'%len(text.encode('utf-8')))
