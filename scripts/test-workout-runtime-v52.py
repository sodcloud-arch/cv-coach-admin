from pathlib import Path
import subprocess
import tempfile

HTML = Path('client-portal/stable/index.html')
if not HTML.exists():
    raise SystemExit('stable client artifact missing; build it before V52 regression guard')
text = HTML.read_text(encoding='utf-8')


def need(fragment, label):
    if fragment not in text:
        raise SystemExit(f'V52 missing {label}: {fragment}')


def forbid(fragment, label):
    if fragment in text:
        raise SystemExit(f'V52 forbidden {label}: {fragment}')


def extract_braced(source, anchor):
    start = source.find(anchor)
    if start < 0:
        raise SystemExit(f'V52 anchor missing: {anchor}')
    paren = source.find('(', start)
    if paren < 0:
        raise SystemExit(f'V52 parameter list missing: {anchor}')
    depth = 0; quote = None; escaped = False; close = -1
    for i in range(paren, len(source)):
        ch = source[i]
        if quote:
            if escaped: escaped = False
            elif ch == '\\': escaped = True
            elif ch == quote: quote = None
        else:
            if ch in ('\'', '"', '`'): quote = ch
            elif ch == '(': depth += 1
            elif ch == ')':
                depth -= 1
                if depth == 0:
                    close = i; break
    if close < 0:
        raise SystemExit(f'V52 unbalanced parameter list: {anchor}')
    brace = source.find('{', close + 1)
    if brace < 0:
        raise SystemExit(f'V52 opening body brace missing: {anchor}')
    depth = 0; quote = None; escaped = False
    for i in range(brace, len(source)):
        ch = source[i]
        if quote:
            if escaped: escaped = False
            elif ch == '\\': escaped = True
            elif ch == quote: quote = None
        else:
            if ch in ('\'', '"', '`'): quote = ch
            elif ch == '{': depth += 1
            elif ch == '}':
                depth -= 1
                if depth == 0:
                    return source[start:i + 1]
    raise SystemExit(f'V52 unbalanced braces: {anchor}')


for frag, label in [
    ('cv-workout-regression-guard-v52', 'V52 marker'),
    ('cv-client-runtime-v51', 'V51 runtime'),
    ('cvPersistSetLogV51', 'V51 persistence helper'),
    ('cvDraftSaveLocksV50', 'draft serialization lock'),
    ('kg·reps', 'volume unit'),
]:
    need(frag, label)
for frag, label in [
    ('cvRirInput', 'athlete RIR input'),
    ("getElementById('cvri_'", 'athlete RIR lookup'),
    ('baseRender=window.render', 'historical render wrapper'),
    ('baseNav=window.nav', 'historical navigation wrapper'),
]:
    forbid(frag, label)

persist = extract_braced(text, 'async function cvPersistSetLogV51(')
draft = extract_braced(text, 'window.cvSaveDraftSet=async function(i,j)')
load_session = extract_braced(text, 'async function loadSession(')
start_workout = extract_braced(text, 'window.startWorkout=async function()')
open_day = extract_braced(text, 'window.openDay=async function(id)')
hydrate = extract_braced(text, 'async function hydrateHistory(')

for frag in ["select('id')", ".eq('id',s.set_log_id)", 'maybeSingle()', 'if(saved.error)throw saved.error', 'if(!saved.data?.id)throw new Error(confirmMessage']:
    if frag not in persist:
        raise SystemExit(f'V52 persistence confirmation contract missing: {frag}')
for frag in ['cvDraftSaveLocksV50', 'await cvPersistSetLogV51', 'draft update was not confirmed', 'cvSaveError', 'return false', 'duration_seconds:p.duration_seconds', 'weight_kg:null,reps:null']:
    if frag not in draft:
        raise SystemExit(f'V52 draft contract missing: {frag}')

# Validate the actually-final set handler. V56 intentionally supersedes the
# V48/V51 handler because the old final handler referenced helpers hidden in a
# different IIFE and therefore failed in a real browser.
toggle_anchor = 'window.cvToggleSet=async function(i,j)'
pos = text.rfind(toggle_anchor)
if pos < 0:
    raise SystemExit('V52 canonical toggle missing')
toggle = extract_braced(text[pos:], toggle_anchor)
if 'cv-set-toggle-runtime-v56' in text:
    for frag in ['cvSetToggleLocksV56', 'const started=await window.startWorkout()', 'p=parseSet(i,j)', 'await persistSet(p.ex,p.s,body)', "document.dispatchEvent(new CustomEvent('cv:set-state'", 'duration_seconds:p.duration_seconds', 'weight_kg:null,reps:null']:
        if frag not in toggle:
            raise SystemExit(f'V52/V56 toggle contract missing: {frag}')
    persist_pos = toggle.find('await persistSet(p.ex,p.s,body)')
    event_pos = toggle.find("document.dispatchEvent(new CustomEvent('cv:set-state'", persist_pos)
    if persist_pos < 0 or event_pos < persist_pos:
        raise SystemExit('V52/V56 success event can occur before confirmed persistence')
    for hidden in ['cvSetFromInputs(', 'cvPersistSetLogV51(', 'startRest(']:
        if hidden in toggle:
            raise SystemExit(f'V52/V56 final toggle depends on hidden helper: {hidden}')
    for frag in ['function persistSet(ex,s,body)', "throw new Error('set update was not confirmed')", ".update(body).eq('id',s.set_log_id).select('id').maybeSingle()"]:
        if frag not in text:
            raise SystemExit(f'V52/V56 persistence owner missing: {frag}')
else:
    for frag in ['cvSetToggleLocksV48', 'p=cvSetFromInputs(i,j)', 'await cvPersistSetLogV51', 'set update was not confirmed']:
        if frag not in toggle:
            raise SystemExit(f'V52 legacy toggle contract missing: {frag}')

for frag in ['epoch!==sessionEpoch', 'workout!==target', 'target.sessionId', 'applyDraftsModel(target)', 'await hydrateHistory(target,epoch)']:
    if frag not in load_session:
        raise SystemExit(f'V52 session load race contract missing: {frag}')
for frag in ['startPromise?.target===target', 'await loadSession(target,dayId,epoch)']:
    if frag not in start_workout:
        raise SystemExit(f'V52 start idempotency contract missing: {frag}')
for frag in ['++sessionEpoch', ".eq('status','in_progress')", 'effective=open.program_day_id', 'await loadSession(target,effective,epoch,{resuming:true']:
    if frag not in open_day:
        raise SystemExit(f'V52 resume contract missing: {frag}')
for frag in ['historyPromise?.sessionId===sessionId', 'epoch!==sessionEpoch', 'target.cvHistoryHydrated=true']:
    if frag not in hydrate:
        raise SystemExit(f'V52 history hydration contract missing: {frag}')

# Execute the original V51 persistence primitive independently. Draft saving
# still uses it, so it remains a protected invariant even after V56 owns ✓.
node_test = f"""
'use strict';
let mode='real';
{persist}
function makeSb(config) {{return {{from(name) {{if(name!=='set_logs')throw new Error('wrong table');return {{
  select() {{const q={{eq(){{return q}},async maybeSingle(){{return config.lookup}}}};return q}},
  update(body) {{config.lastBody=body;const q={{eq(){{return q}},select(){{return q}},async maybeSingle(){{return config.update}}}};return q}}
}}}}}}}}
(async()=>{{
 let cfg={{lookup:{{data:{{id:'log-1'}},error:null}},update:{{data:{{id:'log-1'}},error:null}},lastBody:null}};globalThis.sb=makeSb(cfg);
 const ex={{session_exercise_id:'ex-1'}},s={{set_number:1,set_log_id:null}};
 const ok=await cvPersistSetLogV51(ex,s,{{weight_kg:40,reps:10}},'missing','not confirmed');
 if(ok.id!=='log-1'||s.set_log_id!=='log-1'||cfg.lastBody.reps!==10)throw new Error('confirmed persistence failed');
 cfg={{lookup:{{data:null,error:null}},update:{{data:null,error:null}},lastBody:null}};globalThis.sb=makeSb(cfg);let rejected=false;
 try{{await cvPersistSetLogV51(ex,{{set_number:2,set_log_id:'log-2'}},{{reps:8}},'missing','set update was not confirmed')}}catch(e){{rejected=String(e.message).includes('set update was not confirmed')}}
 if(!rejected)throw new Error('unconfirmed update did not reject');
 cfg={{lookup:{{data:null,error:null}},update:{{data:{{id:'log-3'}},error:null}},lastBody:null}};globalThis.sb=makeSb(cfg);
 await cvPersistSetLogV51(ex,{{set_number:3,set_log_id:'log-3'}},{{weight_kg:null,reps:null,duration_seconds:45}},'missing','not confirmed');
 if(cfg.lastBody.duration_seconds!==45||cfg.lastBody.weight_kg!==null||cfg.lastBody.reps!==null)throw new Error('timed semantics failed');
 console.log('CV_WORKOUT_RUNTIME_V52_NODE_OK');
}})().catch(e=>{{console.error(e);process.exit(1)}});
"""
with tempfile.TemporaryDirectory() as tmp:
    path = Path(tmp) / 'runtime-v52.js'
    path.write_text(node_test, encoding='utf-8')
    result = subprocess.run(['node', str(path)], text=True, capture_output=True)
    if result.returncode != 0:
        raise SystemExit('V52 Node persistence simulation failed:\n' + result.stdout + result.stderr)
    if 'CV_WORKOUT_RUNTIME_V52_NODE_OK' not in result.stdout:
        raise SystemExit('V52 Node persistence simulation did not report success')

print('CV_WORKOUT_RUNTIME_V52_OK')
