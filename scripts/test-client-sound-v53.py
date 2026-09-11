from pathlib import Path
import base64
import re

html = Path('client-portal/stable/index.html')
if not html.exists():
    raise SystemExit('stable client artifact missing; build before V53 sound guard')
text = html.read_text(encoding='utf-8')

required = [
    'cv-client-sound-v53',
    'cv-sound-manager-v53-js',
    "window.CVSound={version:'v53'",
    "document.addEventListener('cv:set-state'",
    "event.detail?.completed===true",
    "play('set_confirmed')",
    "play('workout_complete')",
    "String(result?.status||'').toLowerCase()==='completed'",
    "localStorage.getItem('cvSoundEnabledV53')",
    "localStorage.setItem('cvSoundEnabledV53'",
    "URL.createObjectURL(new Blob([bytes],{type:'audio/mpeg'}))",
    "document.addEventListener('pointerdown'",
]
for item in required:
    if item not in text:
        raise SystemExit(f'V53 sound contract missing: {item}')

if 'data:audio' in text:
    raise SystemExit('V53 sound must not use data: audio under current CSP')

m = re.search(r"const volumes=\{set_confirmed:([0-9.]+),workout_complete:([0-9.]+)\}", text)
if not m:
    raise SystemExit('V53 sound volume contract missing')
set_volume, workout_volume = map(float, m.groups())
if not (0 < set_volume <= 0.35):
    raise SystemExit(f'V53 set sound volume unsafe: {set_volume}')
if not (set_volume < workout_volume <= 0.55):
    raise SystemExit(f'V53 workout sound hierarchy unsafe: {workout_volume}')

encoded = dict(re.findall(r"(set_confirmed|workout_complete):'([A-Za-z0-9+/=]+)'", text))
if set(encoded) != {'set_confirmed', 'workout_complete'}:
    raise SystemExit('V53 embedded sound payloads missing')
for name, payload in encoded.items():
    raw = base64.b64decode(payload, validate=True)
    if len(raw) < 1000 or not raw.startswith(b'ID3'):
        raise SystemExit(f'V53 {name} is not a valid embedded MP3 payload')

# Real-mode set sound is downstream of V51 confirmed persistence: V51 emits
# cv:set-state only through commitSuccess(), and the confirmed update precedes
# return commitSuccess().
toggle_anchor = 'window.cvToggleSet=async function(i,j)'
pos = text.rfind(toggle_anchor)
if pos < 0:
    raise SystemExit('V53 canonical toggle missing')
tail = text[pos:]
persist = tail.find('await cvPersistSetLogV51')
success = tail.find('return commitSuccess()', persist)
event = tail.find("new CustomEvent('cv:set-state'", 0, persist)
if persist < 0 or success < persist:
    raise SystemExit('V53 set confirmation ordering broken')
if event < 0:
    # Event lives inside commitSuccess, which appears before persistence by
    # declaration but executes only after the verified call returns.
    commit_decl = tail.find('const commitSuccess=()=>')
    event = tail.find("new CustomEvent('cv:set-state'", commit_decl)
    if commit_decl < 0 or event < commit_decl:
        raise SystemExit('V53 set-state success event missing')

print('CV_CLIENT_SOUND_V53_OK')
