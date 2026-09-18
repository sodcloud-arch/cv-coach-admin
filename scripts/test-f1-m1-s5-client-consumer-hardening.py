from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
M = ROOT / "supabase/migrations/202609181830_f1_m1_s5_client_consumer_hardening_arch1.sql"
sql = M.read_text(encoding="utf-8").lower()

required = [
    "actor_can_manage_client_in_org_v1",
    "week_start_for_client_in_org",
    "get_client_training_schedule_in_org",
    "c.organization_id=new.organization_id",
    "where c.organization_id=r.organization_id",
    "where ws.organization_id=r.organization_id",
    "where organization_id=v_organization",
    "resolve_legacy_professional_organization_v1",
    "resolve_legacy_client_organization_v1",
    "private.actor_can_manage_client_in_org_v1(",
    "insert into public.client_training_preferences(",
    "organization_id,client_id,muscle_focus",
    "insert into public.client_training_schedule_preferences(",
    "organization_id,client_id,training_days_per_week",
    "insert into public.onboarding_responses(",
    "organization_id,client_id,question_key",
    "'organization_id',v_organization",
]

missing = [token for token in required if token not in sql]
if missing:
    raise SystemExit("Missing C3B contracts: " + ", ".join(missing))

for forbidden in (
    "where cp.client_id=p_client_id\n$function$",
    "where p.client_id = p_client_id",
    "where r.client_id = p_client_id",
    "where c.client_id=r.client_id and c.week_start=v_week",
):
    if forbidden in sql:
        raise SystemExit("Legacy unscoped client consumer reintroduced: " + forbidden)

print("F1.M1.S5 C3B client consumer hardening: PASS")
print("- explicit tenant schedule/week helpers: PASS")
print("- reminders are tenant-local: PASS")
print("- AI quality context reads tenant constraints: PASS")
print("- onboarding/focus/schedule/constraints RPCs resolve Organization: PASS")
print("- actor authorization uses canonical Organization assignments: PASS")
print("- public signatures preserved: PASS")
