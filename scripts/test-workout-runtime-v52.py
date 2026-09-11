from pathlib import Path
import re
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
    brace = source.find("{", start)
    if brace < 0:
        raise SystemExit(f"V52 opening brace missing: {anchor}")
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


# Artifact/version contracts.
require("cv-workout-regression-guard-v52", "V52 marker")
require("cv-client-runtime-v51", "V51 runtime")
require("cvPersistSetLogV51", "shared persistence owner")
require("cvDraftSaveLocksV50", "draft serialization lock")
require("cvSetToggleLocksV48", "toggle lock")
require("kg·reps", "volume unit")
forbid("cvRirInput", "athlete RIR input")
forbid("getElementById('cvri_'", "athlete RIR lookup")
forbid("baseRender=window.render", "historical render wrapper")
forbid("baseNav=window.nav", "historical navigation wrapper")

persist = extract_braced(text, "async function cvPersistSetLogV51(")
draft = extract_braced(text, "window.cvSaveDraftSet=async function(i,j)")
# Last assignment is the canonical V51 toggle. Extract from its last occurrence.
toggle_anchor = "window.cvToggleSet=async function(i,j)"
toggle_pos = text.rfind(toggle_anchor)
if toggle_pos < 0:
    raise SystemExit("V52 canonical toggle missing")
toggle = extract_braced(text[toggle_pos:], toggle_anchor)
start_workout = extract_braced(text, "window.startWorkout=async function()")
open_day = extract_braced(text, "window.openDay=async function(id)")
load_session = extract_braced(text, "async function loadSession(")
hydrate = extract_braced(text, "async function hydrateHistory(")

# Shared persistence must confirm the exact row after UPDATE.
for frag in [
    "select('id')",
    ".eq('id',s.set_log_id)",
    "maybeSingle()",
    "if(saved.error)throw saved.error",
    "if(!saved.data?.id)throw new Error(confirmMessage",
]:
    if frag not in persist:
        raise SystemExit(f"V52 persistence confirmation contract missing: {frag}")

# Draft save: serialized, same helper, failure is visible and returns false.
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

# Toggle: parse once, optimistic UI allowed, but success event/rest only after verified persistence.
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
if persist_call < 0 or commit_return < 0 or commit_return < persist_call:
    raise SystemExit("V52 false-check guard broken: success can occur before verified persistence")
if "startRest(" not in toggle[toggle.find("const commitSuccess=()=>"):persist_call]:
    raise SystemExit("V52 rest start is not owned by confirmed success path")
catch_pos = toggle.find("catch(e)", persist_call)
rollback_pos = toggle.find("rollback()", catch_pos)
if catch_pos < 0 or rollback_pos < catch_pos:
    raise SystemExit("V52 rollback is not guaranteed on persistence failure")

# Session lifecycle and resume race guards.
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

# Execute the persistence primitive with a real JS engine and controlled Supabase mocks.
# This verifies confirmed success, missing-row failure and database-error failure.
node_test = f"""
'use strict';
let mode='real';
{persist}

function makeSb(config) {{
  return {{
    from(name) {{
      if(name!=='set_logs') throw new Error('wrong table');
      return {{
        select() {{
          const chain={{
            eq() {{ return chain; }},
            async maybeSingle() {{ return config.lookup; }}
          }};
          return chain;
        }},
        update(body) {{
          config.lastBody=body;
          const chain={{
            eq() {{ return chain; }},
            select() {{ return chain; }},
            async maybeSingle() {{ return config.update; }}
          }};
          return chain;
        }}
      }};
    }}
  }};
}}

(async()=>{{
  // 1) Missing set_log_id is resolved, then update is confirmed.
  let cfg={{lookup:{{data:{{id:'log-1'}},error:null}},update:{{data:{{id:'log-1'}},error:null}},lastBody:null}};
  globalThis.sb=makeSb(cfg);
  const ex={{session_exercise_id:'exercise-1'}},s={{set_number:1,set_log_id:null}};
  const ok=await cvPersistSetLogV51(ex,s,{{weight_kg:40,reps:10}},'missing','not confirmed');
  if(ok.id!=='log-1'||s.set_log_id!=='log-1'||cfg.lastBody.reps!==10) throw new Error('confirmed persistence scenario failed');

  // 2) UPDATE without a returned row must reject.
  cfg={{lookup:{{data:null,error:null}},update:{{data:null,error:null}},lastBody:null}};
  globalThis.sb=makeSb(cfg);
  let rejected=false;
  try{{await cvPersistSetLogV51(ex,{{set_number:2,set_log_id:'log-2'}},{{reps:8}},'missing','set update was not confirmed')}}catch(e){{rejected=String(e.message).includes('set update was not confirmed')}}
  if(!rejected) throw new Error('unconfirmed update did not reject');

  // 3) Supabase update error must reject.
  cfg={{lookup:{{data:null,error:null}},update:{{data:null,error:new Error('db down')}},lastBody:null}};
  globalThis.sb=makeSb(cfg);
  rejected=false;
  try{{await cvPersistSetLogV51(ex,{{set_number:3,set_log_id:'log-3'}},{{reps:6}},'missing','not confirmed')}}catch(e){{rejected=String(e.message).includes('db down')}}
  if(!rejected) throw new Error('database error did not reject');

  // 4) Timed exercise body preserves seconds semantics and clears load/reps.
  cfg={{lookup:{{data:null,error:null}},update:{{data:{{id:'log-4'}},error:null}},lastBody:null}};
  globalThis.sb=makeSb(cfg);
  await cvPersistSetLogV51(ex,{{set_number:4,set_log_id:'log-4'}},{{weight_kg:null,reps:null,duration_seconds:45}},'missing','not confirmed');
  if(cfg.lastBody.duration_seconds!==45||cfg.lastBody.weight_kg!==null||cfg.lastBody.reps!==null) throw new Error('timed-set semantics failed');

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
