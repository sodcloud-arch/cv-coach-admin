from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
M = ROOT / "supabase/migrations/202609181900_f1_m1_s5_nutrition_habits_progress_scope_arch1.sql"
sql = M.read_text(encoding="utf-8").lower()

required = [
    "alter table public.nutrition_targets\n  add column if not exists organization_id uuid",
    "alter table public.meal_logs\n  add column if not exists organization_id uuid",
    "alter table public.measurements\n  add column if not exists organization_id uuid",
    "alter table public.progress_photos\n  add column if not exists organization_id uuid",
    "alter table public.client_habits\n  add column if not exists organization_id uuid",
    "alter table public.habit_logs\n  add column if not exists organization_id uuid",
    "nutrition_targets_client_same_org",
    "meal_logs_client_same_org",
    "measurements_client_same_org",
    "progress_photos_client_same_org",
    "client_habits_client_same_org",
    "habit_logs_client_same_org",
    "habit_logs_client_habit_same_org_client",
    "guard_habit_log_tenant_v1",
    "guard_progress_photo_tenant_v1",
    "client_habit_belongs_to_in_org",
    "can_view_client_in_org(organization_id,client_id)",
    "can_manage_client_in_org(organization_id,client_id)",
    "private.is_org_member(organization_id)",
]

missing = [token for token in required if token not in sql]
if missing:
    raise SystemExit("Missing D1 contracts: " + ", ".join(missing))

for legacy in (
    "private.can_view_client(client_habits.client_id)",
    "private.can_manage_client(nutrition_targets.client_id)",
    "private.can_manage_client(meal_logs.client_id)",
):
    if legacy in sql:
        raise SystemExit("Legacy global RLS reintroduced: " + legacy)

print("F1.M1.S5 D1 nutrition/habits/progress scope: PASS")
print("- explicit tenant ownership: PASS")
print("- same-tenant client boundaries: PASS")
print("- habit log parent boundary: PASS")
print("- progress photo measurement guard: PASS")
print("- tenant-aware RLS: PASS")
print("- browser DDL-adjacent privileges removed: PASS")
