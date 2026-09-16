from pathlib import Path
import re
import sys

ROOT=Path(__file__).resolve().parents[1]
HTML=ROOT/'client-portal'/'stable'/'index.html'
ASSET=ROOT/'client-portal'/'assets'/'cv-push-v101.js'
SW=ROOT/'client-portal'/'sw.js'
MIG=ROOT/'supabase'/'migrations'/'20260916170259_push_notifications_os_v101.sql'
EDGE=ROOT/'supabase'/'functions'/'push-dispatch-v101'/'index.ts'

for p in [HTML,ASSET,SW,MIG,EDGE]:
    if not p.exists() or p.stat().st_size < 200:
        raise SystemExit(f'V101 contract file missing: {p}')

html=HTML.read_text(encoding='utf-8')
asset=ASSET.read_text(encoding='utf-8')
sw=SW.read_text(encoding='utf-8')
mig=MIG.read_text(encoding='utf-8')
edge=EDGE.read_text(encoding='utf-8')

required_html=['cv-client-push-v101: explicit-consent + web-push + preferences','./assets/cv-push-v101.js']
required_asset=[
    'CV_CLIENT_PUSH_V101_READY','Notification.requestPermission()','pushManager.subscribe',
    'userVisibleOnly:true','register_push_subscription_v101','disable_push_subscription_v101',
    'set_push_preferences_v101','enqueue_push_test_v101','push-dispatch-v101',
    "isIOS()&&!isStandalone()",'CV_PUSH_OPEN_V101','workout_reminder_time'
]
required_sw=["cv-coach-shell-v101",'CV_PUSH_SW_V101_READY',"addEventListener('push'","addEventListener('notificationclick'",'showNotification','CV_PUSH_OPEN_V101',"'/routine':'routine'"]
required_mig=[
    'push_preferences_v101','push_subscriptions_v101','push_dispatch_queue_v101','push_delivery_attempts_v101',
    'enqueue_notification_push_v101','get_push_center_v101','register_push_subscription_v101',
    'enqueue_push_test_v101','claim_push_dispatch_v101','finish_push_dispatch_v101',
    'enqueue_workout_reminders_v101','cv_push_dispatch_v101','cv_workout_reminders_v101',
    "workout_reminder_time is not null","metadata->>'push_disabled'"
]
required_edge=['PUSH_NOTIFICATIONS_OS_V101','web-push@3.6.7','get_push_dispatch_config_v101','dispatch_token','sendNotification','QUIET_HOURS_ACTIVE','claim_push_notification_v101']

for token in required_html:
    if token not in html: raise SystemExit(f'V101 HTML contract missing: {token}')
for token in required_asset:
    if token not in asset: raise SystemExit(f'V101 client asset contract missing: {token}')
for token in required_sw:
    if token not in sw: raise SystemExit(f'V101 service worker contract missing: {token}')
for token in required_mig:
    if token not in mig: raise SystemExit(f'V101 migration contract missing: {token}')
for token in required_edge:
    if token not in edge: raise SystemExit(f'V101 edge contract missing: {token}')

# Permission prompt must exist only inside the explicit enable click path.
permission_calls=[m.start() for m in re.finditer(r'Notification\.requestPermission\(\)',asset)]
if len(permission_calls)!=2:
    # One occurrence is the actual call and one is the explanatory guardrail comment.
    raise SystemExit(f'V101 expected guarded permission marker + call, found {len(permission_calls)}')
actual=asset.find("await Notification.requestPermission()")
enable_start=asset.find('async function enablePush()')
enable_end=asset.find('async function disablePush()')
if not (enable_start >= 0 and actual > enable_start and enable_end > actual):
    raise SystemExit('V101 permission request escaped explicit enablePush handler')

# Secrets must never ship to the browser or service worker.
for forbidden in ['cv_push_vapid_private_v101','cv_push_dispatch_token_v101','private_key']:
    if forbidden in asset or forbidden in sw:
        raise SystemExit(f'V101 browser bundle leaks server secret reference: {forbidden}')

# Push and WhatsApp remain independent products.
for forbidden in ['whatsapp_opt_in','Peach','peach']:
    if forbidden in mig or forbidden in asset:
        raise SystemExit(f'V101 push unexpectedly coupled to WhatsApp: {forbidden}')

# No automatic workout reminder time is allowed.
if re.search(r'workout_reminder_time\s+time[^\n]*default\s+',mig,re.I):
    raise SystemExit('V101 invented a default workout reminder time')

# Dispatcher must retain custom scheduled authentication despite verify_jwt=false deployment.
if "String(body.dispatch_token" not in edge or "DISPATCH_AUTH_FAILED" not in edge:
    raise SystemExit('V101 dispatcher custom authentication missing')
if "auth.getUser(token)" not in edge:
    raise SystemExit('V101 immediate test path does not authenticate the client')

# Arbitrary links are forbidden in the service worker click path.
if 'PUSH_ROUTE_TO_VIEW' not in sw or "url.origin!==self.location.origin" not in sw:
    raise SystemExit('V101 push click route allowlist missing')

print('CV_CLIENT_PUSH_V101_CONTRACT_OK')
