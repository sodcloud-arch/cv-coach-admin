from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
PORTAL = ROOT / 'client-portal' / 'index.html'
CONTRACTS = ROOT / 'scripts' / 'validate-repo-contracts.py'

html = PORTAL.read_text(encoding='utf-8')
contracts = CONTRACTS.read_text(encoding='utf-8')


def once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected 1 anchor, found {count}')
    return text.replace(old, new, 1)

# Root cause fix: expose the canonical exercise accessor to all later classic-script layers.
html = once(
    html,
    "  function cvExercises(){return workout?.liveExercises||cvPrestartExercises()}\n",
    "  function cvExercises(){return workout?.liveExercises||cvPrestartExercises()}\n  window.cvExercises=cvExercises;\n",
    'expose canonical exercise accessor',
)

# Later historical layers execute in separate IIFEs. Point every downstream lookup to the
# explicitly exported accessor instead of relying on private-scope identifier resolution.
marker = '<script id="cv-night-v12-js">'
pos = html.find(marker)
if pos < 0:
    raise SystemExit('downstream script marker not found')
head, tail = html[:pos], html[pos:]
tail = re.sub(r'(?<![\w.])cvExercises\(', 'window.cvExercises(', tail)
tail = tail.replace('typeof cvExercises', 'typeof window.cvExercises')
# Top-level let bindings are global lexical bindings, not window properties.
tail = tail.replace('window.workout', 'workout').replace('window.data', 'data')
html = head + tail

# Semantic color sweep for client-facing information. Red remains for errors/danger/destructive actions.
semantic_css = r'''
<style id="cv-client-semantic-v33">
/* CV Coach Client Semantic V33
   Blue = information/active/time, green = success/progress, red = error/danger/destructive only. */
:root{--cv-info:#43b8ff;--cv-info-2:#249fe8;--cv-info-soft:rgba(67,184,255,.10);--cv-positive:#5ee3a5}

/* Informational text and active navigation. */
.ey{color:var(--cv-info)!important}
.hero h1 b{color:var(--cv-info)!important}
.nav button.active .ico{color:var(--cv-info)!important;filter:drop-shadow(0 0 9px rgba(67,184,255,.28))!important}
.nav button.active:after{background:linear-gradient(90deg,var(--cv-info-2),#69cbff)!important;box-shadow:0 0 12px rgba(67,184,255,.28)!important}
.cvDesktopSide .cvSideNav button.active{background:linear-gradient(90deg,rgba(67,184,255,.17),rgba(67,184,255,.045))!important;border-color:rgba(67,184,255,.20)!important;box-shadow:inset 3px 0 0 var(--cv-info),0 0 18px rgba(67,184,255,.04)!important}
.day .num,.workoutExercise .num{background:linear-gradient(145deg,rgba(67,184,255,.16),rgba(24,88,128,.18))!important;border-color:rgba(67,184,255,.34)!important;color:#78d1ff!important}
body.cvFastWorkout .exerciseTop h3:after{color:var(--cv-info)!important}

/* Technique modal is instructional, not an alert. */
.cvTechniqueTitle,.cvTechBlock h4,.cvTempoHumanTitle{color:#70cdff!important}
.cvTempoStep .n{background:rgba(67,184,255,.09)!important;border-color:rgba(67,184,255,.26)!important;color:#79d1ff!important}
.cvTempoSingle .ico{border-color:rgba(67,184,255,.24)!important;background:rgba(67,184,255,.07)!important;color:#8bd8ff!important}
.cvPrevMeta.coach{color:#72cfff!important}

/* Positive progress uses green/blue, never warning red. */
.progress i,.onboardingProgress i{background:linear-gradient(90deg,#2caaf2,#4ec7d5 52%,var(--cv-positive))!important;box-shadow:0 0 14px rgba(67,184,255,.20)!important}
.stat:after{background:var(--cv-info)!important;box-shadow:0 0 12px rgba(67,184,255,.24)!important}
.cvWorkoutProgressFill{background:linear-gradient(90deg,#2caaf2,#4ec7d5 52%,var(--cv-positive))!important}

/* Selection/focus is informational. */
.onboardingChoice.selected{border-color:var(--cv-info)!important;background:rgba(67,184,255,.10)!important;box-shadow:0 0 0 2px rgba(67,184,255,.08)!important}
.onboardingChoice:focus-visible,.cvNotificationButton:focus-visible{outline-color:var(--cv-info)!important}
.input:focus,input:focus,.cvSetRow input:focus,.cvFeedbackCard select:focus,.cvFeedbackCard textarea:focus,.cvWeeklyModal select:focus,.cvWeeklyModal textarea:focus,.cvWeeklyModal input:focus{border-color:rgba(67,184,255,.78)!important;box-shadow:0 0 0 3px rgba(67,184,255,.08)!important}

/* Notifications are informational; errors keep their existing red classes. */
.cvNotificationBadge{background:var(--cv-info-2)!important}
.cvNotificationItem.unread{border-left-color:var(--cv-info)!important;background:linear-gradient(145deg,rgba(67,184,255,.08),#0b1115)!important}
.cvNotificationItem.unread .cvNotificationType{border-color:rgba(67,184,255,.38)!important;color:#86d8ff!important}

/* Ordinary primary actions are blue. Destructive/finalize actions remain red below. */
.btn.primary{background:linear-gradient(180deg,#39b6fb,#168fd6)!important;border-color:#55c3ff!important;box-shadow:0 10px 28px rgba(36,159,232,.20)!important}
button[onclick="finishWorkout()"],#cvFeedbackFinish{background:linear-gradient(180deg,#f1283c,#d91831)!important;border-color:#f13b4d!important;box-shadow:0 10px 28px rgba(225,29,46,.22)!important}

/* Weekly recovery card is neutral/informational until a real warning is produced. */
.cvWeeklyCard{border-color:rgba(67,184,255,.26)!important;background:radial-gradient(circle at 100% 0,rgba(67,184,255,.07),transparent 36%),linear-gradient(155deg,#0e151b,#080d11)!important}
</style>
'''

insert_anchor = '\n</body></html>'
if 'cv-client-semantic-v33' not in html:
    if insert_anchor not in html:
        raise SystemExit('closing body anchor not found')
    html = html.replace(insert_anchor, '\n' + semantic_css + insert_anchor, 1)

# Regression contracts for the exact root cause.
contract_marker = 'require(client, "cvRestVisualV32", "client visible rest timer")\n'
if contract_marker not in contracts:
    raise SystemExit('v32 contract anchor missing')
if 'client workout canonical exercise accessor' not in contracts:
    contracts = contracts.replace(
        contract_marker,
        contract_marker
        + 'require(client, "window.cvExercises=cvExercises", "client workout canonical exercise accessor")\n'
        + 'require(client, "cv-client-semantic-v33", "client semantic palette v33")\n',
        1,
    )

# No broken global-object lookups may survive in the final v31/v32 client layers.
if 'window.workout?.dayId' in html or 'window.data?.days' in html:
    raise SystemExit('broken window lookup remains')
if html.count('window.cvExercises=cvExercises') != 1:
    raise SystemExit('canonical exercise accessor was not exported exactly once')
if 'cv-client-workout-v32-js' not in html or 'cvRestVisualV32' not in html:
    raise SystemExit('v32 feedback layer missing')

PORTAL.write_text(html, encoding='utf-8')
CONTRACTS.write_text(contracts, encoding='utf-8')
print('CLIENT_WORKOUT_V33_PATCH_OK')
