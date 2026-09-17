-- ARCH-1.0 · F1.M1.S3 compatibility backfill
-- Mirrors existing CV Coach legacy clients into canonical tenant-scoped clients.
-- Does not modify or delete legacy client data.

do $$
declare
  v_org_id uuid;
  v_owner_user_id uuid;
begin
  select id,owner_user_id into v_org_id,v_owner_user_id
  from public.organizations
  where slug='cv-coach';

  if v_org_id is null then
    raise exception 'CV Coach organization not found';
  end if;

  insert into public.organization_members(organization_id,user_id,role,status,joined_at)
  select distinct
    v_org_id,
    p.id,
    'client'::public.organization_member_role,
    'active'::public.organization_member_status,
    now()
  from public.profiles p
  join public.coach_clients cc
    on cc.client_id=p.id
   and cc.coach_id=v_owner_user_id
   and cc.status='active'::public.coach_client_status
  where p.status='active'::public.profile_status
  on conflict (organization_id,user_id) do nothing;

  insert into public.clients(
    organization_id,user_id,status,display_name,contact_metadata,onboarding_state,created_by
  )
  select distinct
    v_org_id,
    p.id,
    'active'::public.client_status,
    coalesce(nullif(btrim(concat_ws(' ',p.first_name,p.last_name)),''),'Client'),
    jsonb_strip_nulls(jsonb_build_object(
      'phone',nullif(btrim(coalesce(p.phone,'')),''),
      'source','legacy_cv_coach'
    )),
    jsonb_strip_nulls(jsonb_build_object(
      'legacy_onboarding_status',cp.onboarding_status::text,
      'source','legacy_cv_coach'
    )),
    v_owner_user_id
  from public.profiles p
  join public.coach_clients cc
    on cc.client_id=p.id
   and cc.coach_id=v_owner_user_id
   and cc.status='active'::public.coach_client_status
  left join public.client_profiles cp on cp.client_id=p.id
  where p.status='active'::public.profile_status
    and not exists(
      select 1 from public.clients c
      where c.organization_id=v_org_id and c.user_id=p.id
    );
end $$;
