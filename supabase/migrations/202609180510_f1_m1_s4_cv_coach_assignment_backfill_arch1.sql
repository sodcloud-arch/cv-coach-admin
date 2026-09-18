-- ARCH-1.0 · F1.M1.S4 compatibility backfill
-- Mirrors existing active legacy coach_clients into canonical assignments.
-- Existing legacy relations are read-only sources and remain untouched.

do $$
declare
  v_org_id uuid;
begin
  select id into v_org_id
  from public.organizations
  where slug='cv-coach';

  if v_org_id is null then
    raise exception 'CV Coach organization not found';
  end if;

  with legacy_active as (
    select
      v_org_id as organization_id,
      c.id as client_id,
      cp.id as coach_profile_id,
      cc.assigned_at,
      cc.coach_id as assigned_by,
      row_number() over(
        partition by c.id
        order by cc.assigned_at desc, cp.id
      ) as rn
    from public.coach_clients cc
    join public.clients c
      on c.organization_id=v_org_id
     and c.user_id=cc.client_id
    join public.coach_profiles cp
      on cp.organization_id=v_org_id
     and cp.user_id=cc.coach_id
    where cc.status='active'::public.coach_client_status
      and c.status<>'archived'::public.client_status
      and cp.status='active'::public.coach_profile_status
  )
  insert into public.client_coach_assignments(
    organization_id,
    client_id,
    coach_profile_id,
    assignment_role,
    status,
    assigned_at,
    assigned_by,
    metadata
  )
  select
    la.organization_id,
    la.client_id,
    la.coach_profile_id,
    case when la.rn=1
      then 'primary'::public.client_coach_assignment_role
      else 'secondary'::public.client_coach_assignment_role
    end,
    'active'::public.client_coach_assignment_status,
    la.assigned_at,
    la.assigned_by,
    jsonb_build_object('source','legacy_coach_clients')
  from legacy_active la
  where not exists(
    select 1
    from public.client_coach_assignments a
    where a.organization_id=la.organization_id
      and a.client_id=la.client_id
      and a.coach_profile_id=la.coach_profile_id
      and a.status='active'::public.client_coach_assignment_status
  )
  on conflict do nothing;
end $$;
