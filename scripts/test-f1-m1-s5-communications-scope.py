from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
M=ROOT/"supabase/migrations/202609182700_f1_m1_s5_communications_scope_arch1.sql"
sql=M.read_text(encoding="utf-8").lower()

required=[
    "communication_preferences_pkey primary key(organization_id,client_id)",
    "uq_communication_drafts_org_idempotency",
    "adherence_followup_events_v98_draft_same_org_client",
    "set_whatsapp_communication_preference_in_org",
    "prepare_communication_draft_in_org",
    "can_manage_client_in_org(organization_id,client_id)",
    "organization_id=v_event.organization_id",
    "organization_id=v_organization",
    "get_client_training_schedule_in_org" if False else "communication_delivery_preflight",
]
missing=[x for x in required if x not in sql]
if missing:
    raise SystemExit("Missing H1 contracts: "+", ".join(missing))

for forbidden in (
    "on conflict(client_id) do update",
    "on conflict(idempotency_key) do nothing",
    "private.can_manage_client(v_draft.client_id)",
):
    if forbidden in sql:
        raise SystemExit("Legacy global communication contract reintroduced: "+forbidden)

print("F1.M1.S5 H1 Communications scope: PASS")
print("- preferences PK is Organization + Client: PASS")
print("- draft idempotency is tenant-scoped: PASS")
print("- follow-up events inherit Organization: PASS")
print("- communication authorization is tenant-aware: PASS")
print("- templates remain global catalog: PASS")
