from pathlib import Path
import re
import subprocess

ROOT=Path(__file__).resolve().parent
HTML=ROOT/'stable'/'index.html'
GUARD=ROOT/'assets'/'cv-workout-set-guard-v74.js'
MARKER='<!-- cv-workout-set-guard-v74: single-flight-set-toggle + hydration-guard -->'
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

# Boot/hydration hardening: historical post-render helpers can run before demo/real data
# is available. Return an empty prestart exercise list until the portal is hydrated.
pattern=r"function cvPrestartExercises\(\)\{\s*const d=data\.days\.find\(x=>x\.id===workout\.dayId\);const raw=data\.exercises\[d\.id\]\|\|\[\];"
replacement="function cvPrestartExercises(){\n    if(!data||!workout?.dayId||!Array.isArray(data.days))return [];\n    const d=data.days.find(x=>x.id===workout.dayId);if(!d)return [];const raw=(data.exercises&&data.exercises[d.id])||[];"
if re.search(pattern,text):
    text=re.sub(pattern,replacement,text,count=1)
elif 'if(!data||!workout?.dayId||!Array.isArray(data.days))return [];' not in text:
    raise SystemExit('V74 hydration guard target missing')

# Inject after every historical workout wrapper so V74 owns the final toggle contract.
payload=f'\n{MARKER}\n<script id="{SCRIPT_ID}">\n{guard}\n</script>\n'
if '</body>' not in text:
    raise SystemExit('V74 body injection target missing')
text=text.replace('</body>',payload+'</body>',1)

# Final ownership / safety checks.
if text.rfind('CVWorkoutSetGuardV74') <= text.rfind('window.cvToggleSet='):
    raise SystemExit('V74 is not the final set-toggle owner')
for token in [MARKER,SCRIPT_ID,'CVWorkoutSetGuardV74','cv-workout-numpad-v73: native-keyboard-retired + custom-editor + deterministic-save','if(!data||!workout?.dayId||!Array.isArray(data.days))return [];']:
    if token not in text:
        raise SystemExit(f'V74 stable artifact missing: {token}')

HTML.write_text(text,encoding='utf-8')
print('{"patches":["single-flight set toggle v74","420ms double-tap suppression v74","pre-hydration exercise guard v74"],"bytes":%d}'%len(text.encode('utf-8')))
