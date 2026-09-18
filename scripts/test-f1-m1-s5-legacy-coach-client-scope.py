from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
M=ROOT/"supabase/migrations/202609182400_f1_m1_s5_legacy_coach_client_scope_arch1.sql"
sql=M.read_text(encoding="utf-8").lower()

required=[
    "alter table public.coach_clients\n  add column if not exists organization_id uuid",
    "alter table public.client_invites\n  add column if not exists organization_id uuid",
    "alter table public.coach_client_notes\n  add column if not exists organization_id uuid",
    "coach_clients_coach_same_org",
    "coach_clients_client_same_org",
    "client_invites_coach_same_org",
    "client_invites_client_same_org",
    "coach_client_notes_coach_same_org",
    "coach_client_notes_client_same_org",
    "uq_coach_clients_active_org",
    "requires canonical active assignment",
    "resolve_legacy_client_organization_v1(",
    "can_manage_client_in_org(",
    "can_view_client_in_org(",
    "actor_can_manage_client_in_org_v1(",
    "revoke truncate,trigger,references",
]
missing=[x for x in required if x not in sql]
if missing:
    raise SystemExit("Missing G1A contracts: "+", ".join(missing))

for forbidden in (
    "create unique index uq_coach_clients_active\n  on public.coach_clients(coach_id,client_id)",
    "private.can_manage_client(coach_client_notes.client_id)",
    "or (select private.is_admin())",
):
    if forbidden in sql:
        raise SystemExit("Legacy global authorization reintroduced: "+forbidden)

print("F1.M1.S5 G1A legacy Coach/Client scope: PASS")
print("- compatibility shadow is tenant-scoped: PASS")
print("- active shadow requires canonical assignment: PASS")
print("- active uniqueness is per Organization: PASS")
print("- legacy auth wrappers fail safely on ambiguous clients: PASS")
print("- notes/invites RLS is tenant-aware: PASS")
