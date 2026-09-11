from pathlib import Path
import subprocess
import tempfile

HTML = Path('client-portal/stable/index.html')
MIGRATION = Path('supabase/migrations/202609111520_coach_client_loop_v59.sql')
ADMIN = Path('index.html')

for path in (HTML, MIGRATION, ADMIN):
    if not path.exists():
        raise SystemExit(f'V59 required file missing: {path}')

html = HTML.read_text(encoding='utf-8')
sql = MIGRATION.read_text(encoding='utf-8')
admin = ADMIN.read_text(encoding='utf-8')

required_html = [
    'cv-coach-client-loop-v59: routine notifications + reviewed-risk attention',
    "program_published:'Rutina actualizada'",
    "'/routine':'routine'",
    'function safeNotificationView(url)',
]
for fragment in required_html:
    if fragment not in html:
        raise SystemExit(f'V59 client route contract missing: {fragment}')

required_sql = [
    'resolve_coach_alert_backend',
    'risk_level_preserved',
    'set requires_coach=false',
    'active_risk_alerts',
    'b.requires_coach or b.active_risk_alerts>0',
    'program_published',
    "'/routine'",
    'trg_notify_client_program_published_v59',
    'trg_audit_coach_alert_close_v59',
    'trg_reconcile_risk_attention_v59',
    "new.alert_type in ('training_risk','weekly_recovery')",
]
for fragment in required_sql:
    if fragment not in sql:
        raise SystemExit(f'V59 backend contract missing: {fragment}')

# Current Admin may still close alerts with a REST PATCH. The V59 database
# triggers are intentionally required so this legacy-compatible path cannot
# leave requires_coach stuck true.
if 'coach_alerts' not in admin or "status:'resolved'" not in admin:
    raise SystemExit('V59 could not verify the Admin alert-close surface')


def extract_braced_function(source: str, signature: str) -> str:
    start = source.find(signature)
    if start < 0:
        raise SystemExit(f'V59 function signature missing: {signature}')
    brace = source.find('{', start + len(signature))
    if brace < 0:
        raise SystemExit(f'V59 function body missing: {signature}')
    depth = 0
    quote = None
    escaped = False
    i = brace
    while i < len(source):
        ch = source[i]
        if quote is not None:
            if escaped:
                escaped = False
            elif ch == '\\':
                escaped = True
            elif ch == quote:
                quote = None
            i += 1
            continue
        if ch in ("'", '"', '`'):
            quote = ch
        elif ch == '{':
            depth += 1
        elif ch == '}':
            depth -= 1
            if depth == 0:
                return source[start:i + 1]
        i += 1
    raise SystemExit(f'V59 unterminated function body: {signature}')


# Execute the real client safeNotificationView function in Node. This verifies
# that program notifications route into the in-app Routine view while external
# and scheme-relative URLs remain rejected.
fn = extract_braced_function(html, 'function safeNotificationView(url)')
node = f"""
const assert=(v,m)=>{{if(!v)throw new Error(m)}};
const location={{origin:'https://client.test'}};
{fn}
assert(safeNotificationView('/routine')==='routine','routine notification did not route to Routine');
assert(safeNotificationView('/progress')==='progress','existing progress route regressed');
assert(safeNotificationView('//evil.test')===null,'scheme-relative external URL was accepted');
assert(safeNotificationView('https://evil.test/routine')===null,'external origin was accepted');
console.log('CV_COACH_CLIENT_ROUTE_RUNTIME_V59_OK');
"""
with tempfile.TemporaryDirectory() as tmp:
    js = Path(tmp) / 'v59-route.js'
    js.write_text(node, encoding='utf-8')
    check = subprocess.run(['node', '--check', str(js)], text=True, capture_output=True)
    if check.returncode != 0:
        raise SystemExit('V59 route syntax failed:\n' + check.stdout + check.stderr)
    run = subprocess.run(['node', str(js)], text=True, capture_output=True, timeout=15)
    if run.returncode != 0:
        raise SystemExit('V59 route runtime failed:\n' + run.stdout + run.stderr)
    if 'CV_COACH_CLIENT_ROUTE_RUNTIME_V59_OK' not in run.stdout:
        raise SystemExit('V59 route runtime success marker missing')

print('CV_COACH_CLIENT_LOOP_V59_OK')
