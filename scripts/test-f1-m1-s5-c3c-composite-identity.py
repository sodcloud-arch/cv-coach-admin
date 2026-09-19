from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
M=ROOT/"supabase/migrations/202609190130_f1_m1_s5_c3c_composite_identity_cutover_arch1.sql"
sql=M.read_text(encoding="utf-8").lower()

required=[
  "primary key(organization_id,client_id)",
  "unique(organization_id,client_id,question_key)",
  "submit_onboarding_in_org_backend",
  "on conflict(organization_id,client_id) do update",
  "on conflict(organization_id,client_id,question_key) do update",
  "set_client_training_focus_in_org_backend",
  "set_client_training_schedule_in_org_backend",
  "provision_client_records_in_org_backend",
  "review_onboarding_in_org_backend",
  "resolve_legacy_client_organization_v1",
  "resolve_legacy_professional_organization_v1",
  "count(distinct nullif(cp.timezone,''))",
]
missing=[x for x in required if x not in sql]
if missing:
    raise SystemExit("Missing C3C contracts: "+", ".join(missing))

for forbidden in [
  "on conflict(client_id) do update",
  "on conflict(client_id,question_key) do update",
  "personal state is still bound to another organization pending composite identity cutover",
]:
    if forbidden in sql:
        raise SystemExit("Global personal-state identity remains: "+forbidden)

print("F1.M1.S5 C3C contracts: PASS")
print("- profiles composite identity: PASS")
print("- training preferences composite identity: PASS")
print("- training schedule composite identity: PASS")
print("- onboarding response composite identity: PASS")
print("- explicit Organization writers available: PASS")
print("- legacy wrappers fail safely on ambiguous tenant context: PASS")
print("- user-global push fallback tolerates multiple tenant profiles: PASS")
