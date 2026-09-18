-- ARCH-1.0 · F1.M1.S4 CV Coach compatibility backfill
-- Maps current legacy coach_clients relationships into canonical tenant assignments.
-- Legacy relations remain untouched.

do $$
declare
  v_org_id uuid;
  v_owner_user_id uuid;
  v_coach_profile_id uuid;
begin
  select o.id,o.owner_user_id
    into v_org_id,v_owner_user_id
  from public.organizations o
  where o.slug='cv-coach';

  if v_org_id is null then
    raise exception 'CV Coach organization not found';
  end if;

  select cp.id into v_coach_profile_id
  from public.coach_profiles cp
  where cp.organization_id=v_org_id
    and cp.user_id=v_owner_user_id
    and cp.status='active'::public.coach_profile_status;

  if v_coach_profile_id is null then
    raise exception 'CV Coach owner coach_profile not found';
  end if;

  insert into public.client_coach_assignments(
    organization_id,client_id,coach_id,assignment_role,status,
    assigned_at,assigned_by
  )
  select distinct
    v_org_id,
    c.id,
    v_coach_profile_id,
    'primary'::public.client_coach_assignment_role,
    'active'::public.client_coach_assignment_status,
    cc.assigned_at,
    v_owner_user_id
  from public.coach_clients cc
  join public.clients c
    on c.organization_id=v_org_id
   and c.user_id=cc.client_id
  where cc.coach_id=v_owner_user_id
    and cc.status='active'::public.coach_client_status
    and not exists(
      select 1
      from public.client_coach_assignments a
      where a.organization_id=v_org_id
        and a.client_id=c.id
        and a.coach_id=v_coach_profile_id
        and a.status='active'::public.client_coach_assignment_status
    );
end $$;
