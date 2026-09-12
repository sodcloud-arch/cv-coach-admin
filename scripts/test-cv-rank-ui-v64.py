from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
PORTAL=ROOT/'client-portal'
CSS=PORTAL/'assets'/'cv-rank-real-ui-v64.css'
HOTFIX=PORTAL/'assets'/'cv-rank-real-ui-v64-hotfix.css'
JS=PORTAL/'assets'/'cv-rank-real-ui-v64.js'
UPGRADE=PORTAL/'upgrade_client_v61.py'
SW=PORTAL/'sw.js'
STABLE=PORTAL/'stable'/'index.html'

for path in [CSS,HOTFIX,JS,UPGRADE,SW]:
    assert path.exists() and path.stat().st_size>200, f'missing or empty: {path}'

css=CSS.read_text(encoding='utf-8')
hotfix=HOTFIX.read_text(encoding='utf-8')
js=JS.read_text(encoding='utf-8')
upgrade=UPGRADE.read_text(encoding='utf-8')
sw=SW.read_text(encoding='utf-8')

for token in ['.cv64WorkoutRankHud','.cv64Step.next','.cv64SessionEndLabel','background:transparent']:
    assert token in css, f'V64 CSS contract missing: {token}'
for token in ['.cv64CompactPath .cv64Step.next{','min-height:0!important','padding-right:1px!important','.cv64CompactPath .cv64Step.next:after','content:none!important']:
    assert token in hotfix, f'V64 iPhone hotfix contract missing: {token}'
for token in ['CVRankRealUIV64','?v=${VERSION}','cv64WorkoutRankHud','moveSessionStatsMobile','freshenRankImages']:
    assert token in js, f'V64 JS contract missing: {token}'
for token in ['cv-rank-real-ui-v64.css','cv-rank-real-ui-v64-hotfix.css','cv-rank-real-ui-v64.js','cv-rank-real-ui-v64: cache-fresh-transparent-badges','.cv64CompactPath .cv64Step.next:after']:
    assert token in upgrade, f'V64 build contract missing: {token}'
# V64 required a cache generation bump, but later releases are allowed to advance it.
cache_match=re.search(r"CACHE_NAME='cv-coach-shell-v(\d+)'",sw)
assert cache_match and int(cache_match.group(1))>=64, 'service-worker cache generation regressed below V64'
assert 'cv-rank-tutorial-v61.webp' in sw, 'tutorial rank asset missing from shell cache'

# The approved rank artwork must expose alpha so it can render without a rectangular background.
for key in ['tutorial','bronze','silver','gold','platinum','diamond','legend']:
    path=PORTAL/'assets'/'ranks'/f'cv-rank-{key}-v61.webp'
    assert path.exists() and path.stat().st_size>3000, f'rank asset invalid: {path}'
    blob=path.read_bytes()
    assert blob[:4]==b'RIFF' and blob[8:12]==b'WEBP', f'not WebP: {path}'
    has_alpha_chunk=b'ALPH' in blob
    vp8x_alpha=False
    if blob[12:16]==b'VP8X' and len(blob)>20:
        vp8x_alpha=bool(blob[20] & 0x10)
    assert has_alpha_chunk or vp8x_alpha, f'rank asset lacks alpha channel: {path}'

if STABLE.exists():
    html=STABLE.read_text(encoding='utf-8')
    for token in ['cv-rank-real-ui-v64-css','cv-rank-real-ui-v64-js','cv-rank-real-ui-v64: cache-fresh-transparent-badges','cv64WorkoutRankHud','.cv64CompactPath .cv64Step.next:after']:
        assert token in html, f'stable V64 contract missing: {token}'
    assert 'cv-rank-real-ui-v63-js' not in html, 'V63 runtime still active in stable build'

print('CV_RANK_UI_V64_OK')
