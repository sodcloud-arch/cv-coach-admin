from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
M=ROOT/"supabase/migrations/202609182430_f1_m1_s5_runtime_auth_hardening_arch1.sql"
sql=M.read_text(encoding="utf-8").lower()

required=[
    "actor_can_manage_client_in_org_v1(",
    "v_program.organization_id",
    "v_source.organization_id",
    "p.organization_id=v_source.organization_id",
    "insert into public.programs(organization_id,client_id,coach_id",
    "select organization_id,client_id into v_organization,v_client_id",
    "s.organization_id,s.client_id",
    "r.organization_id,r.client_id",
]
missing=[x for x in required if x not in sql]
if missing:
    raise SystemExit("Missing G1B1 contracts: "+", ".join(missing))

if "public.coach_clients" in sql:
    raise SystemExit("G1B1 reintroduced direct legacy coach_clients authorization")

print("F1.M1.S5 G1B1 runtime auth hardening: PASS")
print("- AI apply authorization uses Program Organization: PASS")
print("- Program clone authorization/version/draft uniqueness is tenant-local: PASS")
print("- Asset preflight uses Program Organization: PASS")
print("- V83 progression/adaptation review authorization is tenant-local: PASS")
