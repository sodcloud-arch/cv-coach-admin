from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/202609181640_f1_m1_s5_weekly_checkin_tenant_compat_fix.sql"
sql = MIGRATION.read_text(encoding="utf-8").lower()

required = [
    "v_organization:=private.resolve_legacy_client_organization_v1(v_client,null)",
    "ws.organization_id=v_organization",
    "ndl.organization_id=v_organization",
    "organization_id,client_id,week_start",
    "on conflict(organization_id,client_id,week_start)",
    "'weekly_checkin:'||v_organization::text||':'||v_client::text",
    "where organization_id=c.organization_id",
    "insert into public.weekly_program_reviews(",
    "organization_id,client_id,coach_id,program_id,checkin_id",
    "insert into public.coach_alerts(",
    "organization_id,coach_id,client_id,alert_type",
    "v_review_key:=c.organization_id::text",
]

missing = [token for token in required if token not in sql]
if missing:
    raise SystemExit("Missing weekly tenant compatibility contracts: " + ", ".join(missing))

for forbidden in (
    "on conflict(client_id,week_start) do update",
    "where client_id=c.client_id and status='active'::public.program_status",
):
    if forbidden in sql:
        raise SystemExit("Legacy global weekly contract reintroduced: " + forbidden)

print("F1.M1.S5 weekly check-in tenant compatibility: PASS")
print("- legacy RPC resolves one canonical tenant: PASS")
print("- weekly metrics scope canonical tenant roots: PASS")
print("- weekly uniqueness uses Organization + Client + Week: PASS")
print("- review/alert flow preserves Organization: PASS")
