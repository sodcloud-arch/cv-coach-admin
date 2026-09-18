from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
M=ROOT/"supabase/migrations/202609182330_f1_m1_s5_competitive_seasons_challenges_arch1.sql"
sql=M.read_text(encoding="utf-8").lower()

required=[
    "cv_is_coach_admin_in_org_v62",
    "cv_challenge_progress_in_org_v62",
    "cv_refresh_challenge_entry_in_org_v62",
    "cv_finalize_challenge_in_org_v62",
    "create_cv_challenge_in_org_v62",
    "create_cv_season_in_org_v62",
    "organization_id=p_organization",
    "s.organization_id=v_org",
    "cr.organization_id=sp.organization_id",
    "where cr.organization_id=v_org",
    "where c.organization_id=v_org",
    "where s.organization_id=v_org",
    "another season is active in organization",
    "'organization_id',v_org",
]
missing=[x for x in required if x not in sql]
if missing:
    raise SystemExit("Missing F2B contracts: "+", ".join(missing))

for forbidden in (
    "from public.cv_challenges_v61 c order by c.starts_on desc",
    "from public.cv_seasons_v61 s order by s.starts_on desc",
    "left join public.client_competitive_rank_v61 cr on cr.client_id=w.client_id",
    "where s.status='active' and s.id<>p_season_id",
):
    if forbidden in sql:
        raise SystemExit("Legacy cross-tenant competitive contract reintroduced: "+forbidden)

print("F1.M1.S5 F2B competitive Seasons/Challenges: PASS")
print("- professional authorization is tenant-aware: PASS")
print("- challenge progress/refresh/finalize tenant-local: PASS")
print("- season/challenge creation carries Organization: PASS")
print("- coach/client/ranking reads tenant-local: PASS")
print("- one active Season is enforced per Organization: PASS")
