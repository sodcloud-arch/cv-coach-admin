from pathlib import Path
import re

html = Path('client-portal/stable/index.html')
if not html.exists():
    raise SystemExit('stable client artifact missing; build before V55 sound guard')
text = html.read_text(encoding='utf-8')

required = [
    'cv-workout-sound-language-v55',
    'cv-workout-sound-v55-js',
    "window.CVSound?.setEnabled(false)",
    "localStorage.getItem('cv_sound_enabled')",
    "window.CVWorkoutSoundV55={version:'v55'",
    "tone(780,.042,0,.012,'square')",
    "tone(840,.075,0,.026,'square')",
    "tone(920,.085,0,.029,'square')",
    "tone(1040,.105,0,.033,'square')",
    "tone(660,.08,0,.025,'triangle')",
    "tone(825,.09,.065,.024,'triangle')",
    "tone(990,.15,.13,.022,'triangle')",
    "navigator.vibrate?.(sec<=3?[35,28,35]:18)",
    "navigator.vibrate?.([90,55,120])",
    "./assets/sounds/cv-workout-complete-v1.mp3",
]
for item in required:
    if item not in text:
        raise SystemExit(f'V55 workout sound contract missing: {item}')

for item in [
    "tone(c,523,.065,0,.027,'triangle')",
    "tone(c,659,.07,.045,.025,'triangle')",
    "tone(c,784,.10,.09,.022,'triangle')",
    "if(event.detail?.completed)sfx('confirm')",
]:
    if item not in text:
        raise SystemExit(f'V55 original set-confirm sound missing: {item}')

block = re.search(r"function countdownTick\(sec\)\{(.*?)\n  \}\n  function ready\(\)\{(.*?)\n  \}", text, flags=re.S)
if not block:
    raise SystemExit('V55 countdown/ready functions missing')
countdown, ready = block.groups()

# 10..4 share one short tick. 3, 2 and 1 each have exactly one stronger tone.
# No branch is allowed to schedule a second overlapping tone.
branches = {
    '3': re.search(r"if\(sec===3\)\{(.*?)\}", countdown, flags=re.S),
    '2': re.search(r"if\(sec===2\)\{(.*?)\}", countdown, flags=re.S),
    '1': re.search(r"if\(sec===1\)\{(.*?)\}", countdown, flags=re.S),
}
for sec, match in branches.items():
    if not match:
        raise SystemExit(f'V55 countdown branch {sec} missing')
    if match.group(1).count('tone(') != 1:
        raise SystemExit(f'V55 countdown branch {sec} must emit exactly one tone')
if ready.count('tone(') != 3:
    raise SystemExit('V55 ready chime must have exactly three sequential notes')

if 'cvSoundEnabledV53' in text and "window.CVSound?.setEnabled(false)" not in text:
    raise SystemExit('V55 failed to neutralize independent V53 sound preference')

print('CV_WORKOUT_SOUND_V55_OK')
