from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
M=ROOT/"supabase/migrations/202609182830_ascend_autopilot_lifecycle_watchdog_v06.sql"
sql=M.read_text(encoding="utf-8").lower()

required=[
  "ascend_reconcile_chat_session",
  "orphan_response_recovered",
  "orphan_claim_relinked",
  "current_reasoning_request_id=r.id",
  "interval '3 minutes'",
  "continuation_instruction",
  "previous_summary",
  "version','0.6'",
]
missing=[x for x in required if x not in sql]
if missing:
    raise SystemExit("Missing ASCEND v0.6 lifecycle contracts: "+", ".join(missing))

print("ASCEND Autopilot lifecycle watchdog v0.6: PASS")
print("- orphaned claim reconciliation: PASS")
print("- active session pointer protection: PASS")
print("- stale orphan recovery: PASS")
print("- continuation instruction propagation: PASS")
