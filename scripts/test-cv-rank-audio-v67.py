from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
HTML=ROOT/'client-portal'/'stable'/'index.html'
AUDIO=ROOT/'client-portal'/'assets'/'sounds'/'cv-rank-up-v67.mp3'
JS=ROOT/'client-portal'/'assets'/'cv-rank-celebration-v66.js'
CSS=ROOT/'client-portal'/'assets'/'cv-rank-celebration-v67.css'

for p in [HTML,AUDIO,JS,CSS]:
    if not p.exists() or p.stat().st_size<100:
        raise SystemExit(f'V67 artifact missing: {p}')
if AUDIO.stat().st_size<12000:
    raise SystemExit('V67 rank-up audio unexpectedly small')
if AUDIO.read_bytes()[:3]!=b'ID3':
    raise SystemExit('V67 rank-up audio is not MP3/ID3')
html=HTML.read_text(encoding='utf-8')
js=JS.read_text(encoding='utf-8')
css=CSS.read_text(encoding='utf-8')
checks={
    'html marker':'cv-rank-audio-sync-v67',
    'audio path':'cv-rank-up-v67.mp3',
    'impact constant':'RANK_UP_IMPACT=3.36',
    'audio clock watcher':'player.currentTime)>=RANK_UP_IMPACT',
    'impact class':"classList.add('cv66Impact')",
}
for label,token in checks.items():
    if token not in html and token not in js:
        raise SystemExit(f'V67 {label} contract missing: {token}')
for token in ['cv67OldCharge','cv67OldBurst','cv67NewReveal','cv67ImpactFlash']:
    if token not in css or token not in html:
        raise SystemExit(f'V67 CSS sync contract missing: {token}')
print('CV_RANK_AUDIO_V67_OK')
