from pathlib import Path
import re
import subprocess
import tempfile

HTML = Path('client-portal/stable/index.html')
if not HTML.exists():
    raise SystemExit('stable client artifact missing; build before V57 module guard')
text = HTML.read_text(encoding='utf-8')

required = [
    'cv-client-modules-v57: audited habits missions progress notifications onboarding',
    'cv-client-modules-v57-css',
    'cv-client-modules-v57-js',
    "window.CVClientModulesV57={version:'v57'",
    "sb.from('habit_logs')",
    "sb.from('nutrition_daily_logs')",
    "sb.from('client_missions')",
    "sb.from('notifications')",
    "sb.from('progress_photos')",
    "window.logHabit=async function",
    "window.logNutrition=async function",
    'window.cvLogNutritionMealsV57',
    'window.cvTogglePhotoVisibilityV57',
    'Check-in semanal pendiente',
    'El progreso se actualiza automáticamente',
    "latest.status==='abandoned'",
    "active=sessions.find(s=>s.status==='in_progress'",
    'cvNotificationButton,#cvNotificationButton{display:grid!important',
    'DATOS PROTEGIDOS',
]
for fragment in required:
    if fragment not in text:
        raise SystemExit(f'V57 client module contract missing: {fragment}')

# V57 must be the final client module layer, after the verified workout runtime.
if text.find('cv-set-toggle-runtime-v56') > text.find('cv-client-modules-v57'):
    raise SystemExit('V57 is not layered after V56')

# Client code may only use the authenticated public client; never embed privileged keys.
v57_start = text.find('<script id="cv-client-modules-v57-js">')
v57_end = text.find('</script>', v57_start)
if v57_start < 0 or v57_end <= v57_start:
    raise SystemExit('V57 script block missing')
v57 = text[v57_start:v57_end]
for forbidden in ['service_role', 'SUPABASE_SERVICE_ROLE_KEY', '.delete().eq(\'client_id\'']:
    if forbidden in v57:
        raise SystemExit(f'V57 forbidden privileged/destructive client pattern: {forbidden}')

# Habits and nutrition must write through authenticated Edge Functions so CV12
# rewards/missions/achievements remain centralized in backend business logic.
for fragment in [
    "sb.functions.invoke('log-habit'",
    "sb.functions.invoke('log-nutrition-day'",
    'await Promise.all([loadDaily(true),syncCvState()])',
    'successFeedback()',
]:
    if fragment not in v57:
        raise SystemExit(f'V57 engagement write contract missing: {fragment}')

# Photos may change coach visibility only after an exact-row confirmation.
for fragment in [
    "update({visible_to_coach:!!next})",
    ".eq('id',id).eq('client_id',uid()).select('id,visible_to_coach').maybeSingle()",
    "if(q.error||!q.data?.id)",
]:
    if fragment not in v57:
        raise SystemExit(f'V57 photo visibility confirmation missing: {fragment}')

# Daily state must be date scoped; missions must include lifecycle states instead
# of filtering the page to active rows only.
if ".eq('log_date',logDay())" not in v57:
    raise SystemExit('V57 daily hydration is not date scoped')
mission_query = re.search(r"sb\.from\('client_missions'\).*?\.limit\(50\)", v57, flags=re.S)
if not mission_query:
    raise SystemExit('V57 mission lifecycle query missing')
if ".eq('status','active')" in mission_query.group(0):
    raise SystemExit('V57 mission page still filters out completed lifecycle states')

# Check inline syntax for the actual final V57 block in Node.
script_match = re.search(r'<script id="cv-client-modules-v57-js">(.*?)</script>', text, flags=re.S)
if not script_match:
    raise SystemExit('V57 executable script missing')
with tempfile.TemporaryDirectory() as tmp:
    js = Path(tmp) / 'v57.js'
    js.write_text(script_match.group(1), encoding='utf-8')
    checked = subprocess.run(['node', '--check', str(js)], text=True, capture_output=True)
    if checked.returncode != 0:
        raise SystemExit('V57 JavaScript syntax failed:\n' + checked.stdout + checked.stderr)

print('CV_CLIENT_MODULES_V57_OK')
