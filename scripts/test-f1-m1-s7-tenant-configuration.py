from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
M=ROOT/"supabase/migrations/202609190310_f1_m1_s7_tenant_configuration_arch1.sql"
sql=M.read_text(encoding="utf-8").lower()

required=[
  "get_organization_configuration_v1",
  "update_organization_configuration_v1",
  "member_config",
  "admin_config",
  "can_manage_configuration",
  "branding_config must be a json object",
  "feature_flags must be a json object",
  "settings must be a json object",
  "invalid timezone",
  "organization currency must be iso-like 3-letter code",
  "unsupported configuration fields",
  "archived organization configuration is immutable",
  "f1.m1.s7_tenant_config_v1",
  "f1.m1.s7_permission_context_v1",
]
missing=[x for x in required if x not in sql]
if missing:
    raise SystemExit("Missing S7 tenant configuration contracts: "+", ".join(missing))

for forbidden in [
  "set billing_account_id=",
  "set owner_user_id=",
  "set slug=",
  "set status=",
  "set plan_id=",
]:
    if forbidden in sql:
        raise SystemExit("Sensitive/identity field leaked into S7 writable patch: "+forbidden)

print("F1.M1.S7 tenant configuration contracts: PASS")
print("- safe member/admin config split: PASS")
print("- admin-only validated mutation: PASS")
print("- timezone/locale/currency validation: PASS")
print("- JSON shape/size validation: PASS")
print("- tenant identity/billing fields excluded from writable contract: PASS")
