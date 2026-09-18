from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
M=ROOT/"supabase/migrations/202609182600_f1_m1_s5_ai_quality_publish_scope_arch1.sql"
sql=M.read_text(encoding="utf-8").lower()

required=[
    "uq_ai_program_generations_org_idempotency",
    "get_client_training_schedule_in_org(",
    "get_client_time_learning_in_org(",
    "compute_mesocycle_intelligence_in_org_v85(",
    "g.organization_id=v_organization",
    "insert into public.ai_program_generations(organization_id,program_id",
    "actor_can_manage_client_in_org_v1(",
    "organization_id=v_organization and client_id=v_client_id",
    "new.organization_id,new.client_id",
]
missing=[x for x in required if x not in sql]
if missing:
    raise SystemExit("Missing G1B3B contracts: "+", ".join(missing))

for forbidden in (
    "public.coach_clients",
    "private.get_client_training_schedule(p_client_id)",
    "private.get_client_time_learning(p_client_id)",
    "private.compute_mesocycle_intelligence_v85(p_client_id",
    "where g.idempotency_key=v_key limit 1",
):
    if forbidden in sql:
        raise SystemExit("Legacy global AI/quality contract reintroduced: "+forbidden)

print("F1.M1.S5 G1B3B AI Quality Publish scope: PASS")
print("- AI idempotency is Organization-scoped: PASS")
print("- AI context triggers are tenant-local: PASS")
print("- Program quality audit reads tenant-local context: PASS")
print("- Publish authorization and active Program lifecycle are tenant-local: PASS")
