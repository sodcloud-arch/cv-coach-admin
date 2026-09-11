from pathlib import Path

html = Path('client-portal/stable/index.html')
if not html.exists():
    raise SystemExit('stable client artifact missing; build before V54 guard')
text = html.read_text(encoding='utf-8')

required = [
    'cv-mobile-workout-reliability-v54',
    'function cvV54Timeout',
    'function cvV54Bounded',
    'Promise.race([Promise.resolve(promise),cvV54Timeout(ms,message)])',
    'sb.auth.getSession()',
    'sb.auth.refreshSession()',
    'async function cvInvokeStartWorkoutV54(dayId)',
    'await cvInvokeStartWorkoutV54(dayId)',
    'El inicio del entrenamiento tardó demasiado.',
    'El inicio del entrenamiento no respondió a tiempo.',
    "document.addEventListener('cv:set-state',()=>queueCompactV44())",
    'requestAnimationFrame(workoutState);',
    "await cvPersistSetLogV51(ex,s,body,'set log missing','set update was not confirmed')",
    "new CustomEvent('cv:set-state',{detail:{i,j,completed:next}})",
]
for item in required:
    if item not in text:
        raise SystemExit(f'V54 mobile workout contract missing: {item}')

# The canonical session loader must be bounded by the V54 helper rather than
# making an unbounded Edge Function call itself.
load_start = text.find('  async function loadSession(')
load_end = text.find('\n  window.startWorkout=async function()', load_start)
if load_start < 0 or load_end <= load_start:
    raise SystemExit('V54 could not isolate canonical loadSession')
load_block = text[load_start:load_end]
if "sb.functions.invoke('start-workout'" in load_block:
    raise SystemExit('V54 loadSession still has an unbounded direct start-workout invoke')
if 'cvInvokeStartWorkoutV54(dayId)' not in load_block:
    raise SystemExit('V54 loadSession does not use bounded start helper')

# Persistence still has to precede the domain event. This prevents green ✓,
# sound or progress from reporting success when Supabase did not confirm it.
toggle_anchor = 'window.cvToggleSet=async function(i,j)'
pos = text.rfind(toggle_anchor)
if pos < 0:
    raise SystemExit('V54 canonical set toggle missing')
tail = text[pos:]
persist = tail.find('await cvPersistSetLogV51')
success = tail.find('return commitSuccess()', persist)
commit_decl = tail.find('const commitSuccess=()=>')
event = tail.find("new CustomEvent('cv:set-state'", commit_decl)
if min(persist, success, commit_decl, event) < 0 or success < persist or event < commit_decl:
    raise SystemExit('V54 confirmed set persistence/event ordering broken')

# The compact top summary must re-read model state after the successful event;
# click-only synchronization is too early on mobile because persistence is async.
click_listener = "document.addEventListener('click',event=>{if(event.target.closest('.cvSetCheck,.cvAddSet'))setTimeout(queueCompactV44,0)},true);"
confirmed_listener = "document.addEventListener('cv:set-state',()=>queueCompactV44());"
if click_listener not in text or confirmed_listener not in text:
    raise SystemExit('V54 compact progress synchronization listeners missing')

print('CV_MOBILE_WORKOUT_V54_OK')
