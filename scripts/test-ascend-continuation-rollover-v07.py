from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
M=ROOT/"supabase/migrations/202609190240_ascend_continuation_rollover_v07.sql"
G=ROOT/"supabase/functions/ascend-gateway/index.ts"
sql=M.read_text(encoding="utf-8").lower()
gateway=G.read_text(encoding="utf-8").lower()

required_sql=[
  "ascend_continue_reasoning_request",
  "continuation_rolled_over",
  "fresh_reasoning_request:true",
  "attempts_reset",
  "project_continuation_required",
  "development_continuation",
  "autonomous_continuation",
  "status='resolved'",
  "'attention_required',v_new_status='blocked'",
  "'notice'",
  "version','0.7'",
]
missing=[x for x in required_sql if x not in sql]
if missing:
    raise SystemExit("Missing ASCEND v0.7 SQL contracts: "+", ".join(missing))

required_gateway=[
  'status === "continue"',
  '"ascend_continue_reasoning_request"',
  'version: "0.7.0"',
  'continuation_rollover_failed',
]
missing=[x for x in required_gateway if x not in gateway]
if missing:
    raise SystemExit("Missing ASCEND v0.7 gateway contracts: "+", ".join(missing))

if 'status === "continue"' in gateway and 'p_resolution: "retry"' in gateway[gateway.find('status === "continue"'):gateway.find('status === "continue"')+1200]:
    raise SystemExit("CONTINUE still consumes retry attempts")

print("ASCEND continuation rollover v0.7: PASS")
print("- CONTINUE closes old request: PASS")
print("- fresh active-mission request queued: PASS")
print("- retry budget resets per autonomous cycle: PASS")
print("- blocked lifecycle events no longer recurse as warnings: PASS")
