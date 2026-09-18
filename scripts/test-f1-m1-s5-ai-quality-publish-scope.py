from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
M = ROOT / "supabase/migrations/202609182600_f1_m1_s5_ai_quality_publish_scope_arch1.sql"
sql = M.read_text(encoding="utf-8").lower()

required = [
    "uq_ai_program_generations_org_idempotency",
    "on public.ai_program_generations(organization_id,idempotency_key)",
    "get_client_training_schedule_in_org(",
    "new.organization_id,new.client_id",
    "get_client_time_learning_in_org(new.organization_id,new.client_id)",
    "g.organization_id=v_organization and g.idempotency_key=v_key",
    "r.organization_id=v_organization and r.client_id=p_client_id",
    "wc.organization_id=v_organization and wc.client_id=p_client_id",
    "tp.organization_id=v_organization and tp.client_id=p_client_id",
    "sp.organization_id=v_organization and sp.client_id=p_client_id",
    "get_client_time_learning_in_org(v_organization,p_client_id)",
    "compute_mesocycle_intelligence_in_org_v85(v_organization,p_client_id,v_program.id)",
    "insert into public.ai_program_generations(organization_id,program_id",
    "actor_can_manage_client_in_org_v1(",
    "where organization_id=v_organization and client_id=v_client_id and status='active'::public.program_status",
]
missing = [x for x in required if x not in sql]
if missing:
    raise SystemExit("Missing G1B3B contracts: " + ", ".join(missing))

forbidden = [
    "public.coach_clients",
    "private.get_client_training_schedule(p_client_id)",
    "private.get_client_time_learning(p_client_id)",
    "private.compute_mesocycle_intelligence_v85(p_client_id",
    "where g.idempotency_key=v_key limit 1",
    "from public.onboarding_responses r where r.client_id=p_client_id",
    "from public.weekly_checkins wc where wc.client_id=p_client_id",
    "from public.client_training_preferences tp where tp.client_id=p_client_id",
    "from public.client_training_schedule_preferences sp where sp.client_id=p_client_id",
]
bad = [x for x in forbidden if x in sql]
if bad:
    raise SystemExit("Legacy/unscoped AI quality contract reintroduced: " + ", ".join(bad))

print("F1.M1.S5 G1B3B AI Quality Publish scope: PASS")
print("- AI idempotency is Organization-scoped: PASS")
print("- AI preparation context is tenant-local: PASS")
print("- AI context triggers are tenant-local: PASS")
print("- Program quality audit reads tenant-local context: PASS")
print("- Publish authorization and active Program lifecycle are tenant-local: PASS")
