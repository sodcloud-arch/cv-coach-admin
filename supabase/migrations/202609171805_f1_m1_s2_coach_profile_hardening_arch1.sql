-- ARCH-1.0 · F1.M1.S2 hardening
-- Professional capability requires both an active professional profile and active tenant membership.

create or replace function private.is_org_professional(
  target_organization uuid,
  target_user uuid default auth.uid()
)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select coalesce(exists(
    select 1
    from public.coach_profiles cp
    join public.organization_members om
      on om.organization_id=cp.organization_id
     and om.user_id=cp.user_id
    where cp.organization_id=target_organization
      and cp.user_id=target_user
      and cp.status='active'::public.coach_profile_status
      and om.status='active'::public.organization_member_status
  ),false)
$function$;

drop policy if exists coach_credentials_select_v1 on public.coach_credentials;
create policy coach_credentials_select_v1
on public.coach_credentials for select
to authenticated
using (
  exists(
    select 1 from public.coach_profiles cp
    where cp.id=coach_profile_id
      and (cp.user_id=(select auth.uid()) or private.is_org_admin(cp.organization_id))
  )
);
