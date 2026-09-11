from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
PORTAL=ROOT/'client-portal'
CSS=PORTAL/'assets'/'cv-rank-real-ui-v65.css'
JS=PORTAL/'assets'/'cv-rank-real-ui-v65.js'
UPGRADE=PORTAL/'upgrade_client_v61.py'
STABLE=PORTAL/'stable'/'index.html'

for path in [CSS,JS,UPGRADE]:
    assert path.exists() and path.stat().st_size>200, f'missing or empty: {path}'

css=CSS.read_text(encoding='utf-8')
js=JS.read_text(encoding='utf-8')
upgrade=UPGRADE.read_text(encoding='utf-8')

for token in [
    'grid-template-columns:repeat(7,minmax(0,1fr))!important',
    'height:72px!important',
    '.cv64CompactPath .cv64Step.next',
    '.cv64CompactPath .cv64Step:first-child img{opacity:0!important',
    "content:'ACTUAL'!important",
    '.cv65LeagueProgress',
    '.cv65CompactState'
]:
    assert token in css, f'V65 CSS contract missing: {token}'

# Current league must be the sole boxed focus. The next league remains visible but unboxed.
for token in [
    '.cv64CompactPath .cv64Step.next::after{content:none!important;display:none!important}',
    'border-color:transparent!important',
    'background:transparent!important',
    'box-shadow:none!important'
]:
    assert token in css, f'V65 next-rank focus contract missing: {token}'

# Tutorial stays a non-rank empty slot, but completed initiation must be unmistakable.
for token in [
    ".cv64CompactPath .cv64Step:first-child.reached:not(.current)::before{",
    "content:'✓'",
    'color:#45d79a',
    "content:'HECHO'!important;color:#45d79a!important"
]:
    assert token in css, f'V65 tutorial completion contract missing: {token}'

assert "content:'PRÓXIMO'!important" not in css, 'next league still receives competing PRÓXIMO badge treatment'

for token in [
    'CVRankRealUIV65',
    'cv65LeagueProgress',
    'PRÓXIMO RANGO ·',
    'ascenso${remaining===1',
    'cv65CompactState'
]:
    assert token in js, f'V65 JS contract missing: {token}'

for token in [
    'cv-rank-real-ui-v65.css',
    'cv-rank-real-ui-v65.js',
    'cv-rank-real-ui-v65: uniform-seven-slot-track + empty-tutorial + compact-rank-card',
    'cv65LeagueProgress'
]:
    assert token in upgrade, f'V65 build contract missing: {token}'

if STABLE.exists():
    html=STABLE.read_text(encoding='utf-8')
    for token in [
        'cv-rank-real-ui-v65-css',
        'cv-rank-real-ui-v65-js',
        'cv-rank-real-ui-v65: uniform-seven-slot-track + empty-tutorial + compact-rank-card',
        'grid-template-columns:repeat(7,minmax(0,1fr))!important',
        'cv65LeagueProgress',
        "content:'✓'"
    ]:
        assert token in html, f'stable V65 contract missing: {token}'
    assert 'cv-rank-real-ui-v63-js' not in html, 'V63 runtime still active in stable build'

print('CV_RANK_UI_V65_OK')
