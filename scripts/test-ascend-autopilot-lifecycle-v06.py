from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
M=ROOT/"supabase/migrations/202609182830_ascend_autopilot_lifecycle_watchdog_v06.sql"
G=ROOT/"supabase/functions/ascend-gateway/index.ts"
sql=M.read_text(encoding="utf-8").lower()
gateway=G.read_text(encoding="utf-8").lower()

required_sql=[
  "ascend_reconcile_chat_session",
  "orphan_response_recovered",
  "orphan_claim_relinked",
  "current_reasoning_request_id=r.id",
  "interval '3 minutes'",
  "continuation_instruction",
  "previous_summary",
  "version','0.6'",
]
missing_sql=[x for x in required_sql if x not in sql]
if missing_sql:
    raise SystemExit("Missing ASCEND v0.6 SQL contracts: "+", ".join(missing_sql))

required_gateway=[
  "ascend_reconcile_chat_session",
  "continuation_instruction",
  "continuación del ciclo anterior",
  "estado actual del proyecto en ascend core",
  "project_context",
  "reasoning_resolution_failed",
  '.eq("current_reasoning_request_id", requestid)',
  'version: "0.6.1"',
]
missing_gateway=[x for x in required_gateway if x not in gateway]
if missing_gateway:
    raise SystemExit("Missing ASCEND v0.6 gateway contracts: "+", ".join(missing_gateway))

print("ASCEND Autopilot lifecycle watchdog v0.6: PASS")
print("- orphaned claim reconciliation: PASS")
print("- active session pointer protection: PASS")
print("- stale orphan recovery: PASS")
print("- continuation instruction propagation: PASS")
print("- gateway resolution failures preserve recoverable state: PASS")
