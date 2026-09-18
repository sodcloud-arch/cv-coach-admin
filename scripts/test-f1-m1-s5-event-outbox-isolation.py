from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
M = ROOT / "supabase/migrations/202609181700_f1_m1_s5_event_outbox_isolation_arch1.sql"
sql = M.read_text(encoding="utf-8").lower()

required = [
    "add column if not exists organization_id uuid",
    "resolve_event_organization_v1",
    "event_outbox_organization_id_fkey",
    "uq_event_outbox_org_idempotency",
    "guard_event_outbox_tenant_v1",
    "event_outbox cannot cross organization boundary",
    "event_outbox tenant identity is immutable",
    "on conflict(organization_id,idempotency_key)",
    "organization_id,event_key,aggregate_type,aggregate_id,client_id",
]
missing = [token for token in required if token not in sql]
if missing:
    raise SystemExit("Missing Event Outbox isolation contracts: " + ", ".join(missing))

if "on conflict (idempotency_key)" in sql or "on conflict(idempotency_key)" in sql:
    raise SystemExit("Global Event Outbox idempotency reintroduced")

print("F1.M1.S5 Event Outbox isolation: PASS")
print("- aggregate-derived Organization: PASS")
print("- immutable tenant identity: PASS")
print("- tenant-scoped idempotency: PASS")
print("- producer signature preserved: PASS")
