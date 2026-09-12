from pathlib import Path
import hashlib

ROOT=Path(__file__).resolve().parents[1]
HTML=ROOT/'client-portal'/'stable'/'index.html'
AUDIO=ROOT/'client-portal'/'assets'/'sounds'/'cv-rank-up-v67.mp3'
JS=ROOT/'client-portal'/'assets'/'cv-rank-celebration-v66.js'
CSS=ROOT/'client-portal'/'assets'/'cv-rank-celebration-v67.css'
EXPECTED='ea7bdb79a6230c0fa00c42d0e51bccd9c23fee61a9db94b6afcd8fdaaa92358f'

for p in [HTML,AUDIO,JS,CSS]:
    if not p.exists() or p.stat().st_size<100:
        raise SystemExit(f'V67 artifact missing: {p}')
raw=AUDIO.read_bytes()
if len(raw)<12000:
    raise SystemExit('V67 rank-up audio unexpectedly small')
if raw[:3]!=b'ID3':
    raise SystemExit('V67 rank-up audio is not MP3/ID3')
if hashlib.sha256(raw).hexdigest()!=EXPECTED:
    raise SystemExit('V67 rank-up audio hash mismatch')
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
