from pathlib import Path
import subprocess
import tempfile

HTML = Path("client-portal/stable/index.html")
if not HTML.exists():
    raise SystemExit("stable client artifact missing; build it before V52 regression guard")
text = HTML.read_text(encoding="utf-8")


def require(fragment: str, label: str) -> None:
    if fragment not in text:
        raise SystemExit(f"V52 missing {label}: {fragment}")


def forbid(fragment: str, label: str) -> None:
    if fragment in text:
        raise SystemExit(f"V52 forbidden {label}: {fragment}")


def extract_braced(source: str, anchor: str) -> str:
    start = source.find(anchor)
    if start < 0:
        raise SystemExit(f"V52 anchor missing: {anchor}")
    paren = source.find("(", start)
    if paren < 0:
        raise SystemExit(f"V52 parameter list missing: {anchor}")
    pdepth = 0
    quote = None
    escaped = False
    close_paren = -1
    i = paren
    while i < len(source):
        ch = source[i]
        if quote:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == quote:
                quote = None
        else:
            if ch in ("'", '"', "`"):
                quote = ch
            elif ch == "(":
                pdepth += 1
            elif ch == ")":
                pdepth -= 1
                if pdepth == 0:
                    close_paren = i
                    break
        i += 1
    if close_paren < 0:
        raise SystemExit(f"V52 unbalanced parameter list: {anchor}")
    brace = source.find("{", close_paren + 1)
    if brace < 0:
        raise SystemExit(f"V52 opening body brace missing: {anchor}")
    depth = 0
    quote = None
    escaped = False
    i = brace
    while i < len(source):
        ch = source[i]
        if quote:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == quote:
                quote = None
        else:
            if ch in ("'", '"', "`"):
                quote = ch
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    return source[start:i + 1]
        i += 1
    raise SystemExit(f"V52 unbalanced braces: {anchor}")


require("cv-workout-regression-guard-v52", "V52 marker")
require("cv-client-runtime-v51", "V51 runtime")
require("cvPersistSetLogV51", "shared persistence owner")
require("cvDraftSaveLocksV50", "draft serialization lock")
require("kg·reps", "volume unit")
forbid("cvRirInput", "athlete RIR input")
forbid("getElementById('cvri_'", "athlete RIR lookup")
forbid("baseRender=window.render", "historical render wrapper")
forbid("baseNav=window.nav", "historical navigation wrapper")

persist = extract_braced(text, "async function cvPersistSetLogV51(")
draft = extract_braced(text, "window.cvSaveDraftSet=async function(i,j)")
toggle_anchor = "window.cvToggleSet=async function(i,j)"
toggle_pos = text.rfind(toggle_anchor)
if toggle_pos < 0:
    raise SystemExit("V52 canonical toggle missing")
toggle = extract_braced(text[toggle_pos:], toggle_anchor)
start_workout = extract_braced(text, "window.startWorkout=async function()")
open_day = extract_braced(text, "window.openDay=async function(id)")
load_session = extract_braced(text, "async function loadSession(")
hydrate = extract_braced(text, "async function hydrateHistory(")

for frag in [
    "select('id')",
    ".eq('id',s.set_log_id)",
    "maybeSingle()",
    "if(saved.error)throw saved.error",
    "if(!saved.data?.id)throw new Error(confirmMessage",
]:
    if frag not in persist:
        raise SystemExit(f"V52 persistence confirmation contract missing: {frag}")

for frag in [
    "cvDraftSaveLocksV50",
    "await cvPersistSetLogV51",
    "draft update was not confirmed",
    "cvSaveError",
    "return false",
    "duration_seconds:p.duration_seconds",
    "weight_kg:null,reps:null",
]:
    if frag not in draft:
        raise SystemExit(f"V52 draft contract missing: {frag}")

# V56 supersedes the historical V48/V51 click handler. Keep validating the
# historical path on older artifacts, but validate the actual final handler
# when V56 is present. This prevents a regression guard from forcing us back
# to the cross-IIFE bug fixed by V56.
if "cv-set-toggle-runtime-v56" in text:
    require("cvSetToggleLocksV56", "V56 toggle lock")
    for frag in [
        "cvSetToggleLocksV56",
        "const started=await window.startWorkout()",
        "p=parseSet(i,j)",
        "snapshot={w:p.s.weight_kg,r:p.s.reps,d:p.s.duration_seconds,c:!!p.s.completed}",
        "await persistSet(p.ex,p.s,body)",
        "set update was not confirmed",
        "document.dispatchEvent(new CustomEvent('cv:set-state'",
        "duration_seconds:p.duration_seconds",
        "weight_kg:null,reps:null",
    ]:
        if frag not in toggle:
            raise SystemExit(f"V52/V56 toggle contract missing: {frag}")
    persist_call = toggle.find("await persistSet(p.ex,p.s,body)")
    event_call = toggle.find("document.dispatchEvent(new CustomEvent('cv:set-state'", persist_call)
    if persist_call < 0 or event_call < persist_call:
        raise SystemExit("V52/V56 false-check guard broken: success event can occur before verified persistence")
    for hidden in ["cvSetFromInputs(", "cvPersistSetLogV51(", "startRest("]:
        if hidden in toggle:
            raise SystemExit(f"V52/V56 final toggle depends on hidden-scope helper: {hidden}")
else:
    require("cvSetToggleLocksV48", "toggle lock")
    for frag in [
        "cvSetToggleLocksV48",
        "const old={w:s.weight_kg,r:s.reps,d:s.duration_seconds,c:s.completed}",
        "p=cvSetFromInputs(i,j)",
        "const rollback=()=>",
        "const commitSuccess=()=>",
        "await cvPersistSetLogV51",
        "set update was not confirmed",
        "rollback();toast?.('No pude confirmar el guardado de la serie.",
        "duration_seconds:performed",
        "weight_kg:null,reps:null",
    ]:
        if frag not in toggle:
            raise SystemExit(f"V52 toggle contract missing: {frag}")
    persist_call = toggle.find("await cvPersistSetLogV51")
    commit_return = toggle.find("return commitSuccess()", persist_call)
    if persist_call < 0 or commit_return < persist_call:
        raise SystemExit("V52 false-check guard broken: success can occur before verified persistence")

for frag in [
    "epoch!==sessionEpoch",
    "workout!==target",
    "target.sessionId",
    "applyDraftsModel(target)",
    "await hydrateHistory(target,epoch)",
]:
    if frag not in load_session:
        raise SystemExit(f"V52 session load race contract missing: {frag}")
for frag in ["startPromise?.target===target", "await loadSession(target,dayId,epoch)"]:
    if frag not in start_workout:
        raise SystemExit(f"V52 start idempotency contract missing: {frag}")
for frag in [
    "++sessionEpoch",
    ".eq('status','in_progress')",
    "effective=open.program_day_id",
    "await loadSession(target,effective,epoch,{resuming:true",
]:
    if frag not in open_day:
        raise SystemExit(f"V52 resume contract missing: {frag}")
for frag in [
    "historyPromise?.sessionId===sessionId",
    "epoch!==sessionEpoch",
    "target.cvHistoryHydrated=true",
]:
    if frag not in hydrate:
        raise SystemExit(f"V52 history hydration contract missing: {frag}")

node_test = f"""
'use strict';
let mode='real';
{persist}
function makeSb(config) {{
  return {{from(name) {{if(name!=='set_logs') throw new Error('wrong table');return {{
    select() {{const chain={{eq(){{return chain;}},async maybeSingle(){{return config.lookup;}}}};return chain;}},
    update(body) {{config.lastBody=body;const chain={{eq(){{return chain;}},select(){{return chain;}},async maybeSingle(){{return config.update;}}}};return chain;}}
  }};}}}};
}}
(async()=>{{
  let cfg={{lookup:{{data:{{id:'log-1'}},error:null}},update:{{data:{{id:'log-1'}},error:null}},lastBody:null}};globalThis.sb=makeSb(cfg);
  const ex={{session_exercise_id:'exercise-1'}},s={{set_number:1,set_log_id:null}};
  const ok=await cvPersistSetLogV51(ex,s,{{weight_kg:40,reps:10}},'missing','not confirmed');
  if(ok.id!=='log-1'||s.set_log_id!=='log-1'||cfg.lastBody.reps!==10)throw new Error('confirmed persistence scenario failed');
  cfg={{lookup:{{data:null,error:null}},update:{{data:null,error:null}},lastBody:null}};globalThis.sb=makeSb(cfg);let rejected=false;
  try{{await cvPersistSetLogV51(ex,{{set_number:2,set_log_id:'log-2'}},{{reps:8}},'missing','set update was not confirmed')}}catch(e){{rejected=String(e.message).includes('set update was not confirmed')}}
  if(!rejected)throw new Error('unconfirmed update did not reject');
  cfg={{lookup:{{data:null,error:null}},update:{{data:null,error:new Error('db down')}},lastBody:null}};globalThis.sb=makeSb(cfg);rejected=false;
  try{{await cvPersistSetLogV51(ex,{{set_number:3,set_log_id:'log-3'}},{{reps:6}},'missing','not confirmed')}}catch(e){{rejected=String(e.message).includes('db down')}}
  if(!rejected)throw new Error('database error did not reject');
  cfg={{lookup:{{data:null,error:null}},update:{{data:{{id:'log-4'}},error:null}},lastBody:null}};globalThis.sb=makeSb(cfg);
  await cvPersistSetLogV51(ex,{{set_number:4,set_log_id:'log-4'}},{{weight_kg:null,reps:null,duration_seconds:45}},'missing','not confirmed');
  if(cfg.lastBody.duration_seconds!==45||cfg.lastBody.weight_kg!==null||cfg.lastBody.reps!==null)throw new Error('timed-set semantics failed');
  console.log('CV_WORKOUT_RUNTIME_V52_NODE_OK');
}})().catch(e=>{{console.error(e);process.exit(1)}});
"""
with tempfile.TemporaryDirectory() as tmp:
    path = Path(tmp) / "runtime-v52.js"
    path.write_text(node_test, encoding="utf-8")
    result = subprocess.run(["node", str(path)], text=True, capture_output=True)
    if result.returncode != 0:
        raise SystemExit("V52 Node persistence simulation failed:\n" + result.stdout + result.stderr)
    if "CV_WORKOUT_RUNTIME_V52_NODE_OK" not in result.stdout:
        raise SystemExit("V52 Node persistence simulation did not report success")

print("CV_WORKOUT_RUNTIME_V52_OK")
