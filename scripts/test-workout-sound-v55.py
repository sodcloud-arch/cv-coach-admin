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
    "if(sec>=4)",
    "if(sec===3)",
    "if(sec===2)",
    "if(sec===1)",
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

# Set completion must keep the original CV ascending confirmation and V53's
# duplicate set MP3 manager must be disabled by V55.
for item in [
    "tone(c,523,.065,0,.027,'triangle')",
    "tone(c,659,.07,.045,.025,'triangle')",
    "tone(c,784,.10,.09,.022,'triangle')",
    "if(event.detail?.completed)sfx('confirm')",
]:
    if item not in text:
        raise SystemExit(f'V55 original set-confirm sound missing: {item}')

# Verify the semantic countdown split: 10..4 = original short tick, 3..1 =
# emphasized ticks, 0/LISTO = a distinct three-note ready chime.
block = re.search(r"function countdownTick\(sec\)\{(.*?)\n  \}\n  function ready\(\)\{(.*?)\n  \}", text, flags=re.S)
if not block:
    raise SystemExit('V55 countdown/ready functions missing')
countdown, ready = block.groups()
if countdown.count("tone(") < 7:
    raise SystemExit('V55 emphasized countdown tone hierarchy incomplete')
if ready.count("tone(") != 3:
    raise SystemExit('V55 ready chime must have exactly three notes')

# The public sound preference is the same one controlled by the header.
if 'cvSoundEnabledV53' in text and "window.CVSound?.setEnabled(false)" not in text:
    raise SystemExit('V55 failed to neutralize independent V53 sound preference')

print('CV_WORKOUT_SOUND_V55_OK')
