-- ARCH-1.0 · F1.M1.S4 assigned-client visibility hardening
-- After canonical assignments are backfilled, professionals only see clients
-- with an active assignment. Org Admin retains tenant-wide visibility and
-- Client retains self visibility.

create or replace function private.can_view_client_entity(target_client uuid)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select coalesce(
    auth.role()='service_role'
    or exists(
      select 1
      from public.clients c
      where c.id=target_client
        and (
          private.is_platform_admin()
          or private.is_org_admin(c.organization_id)
          or (
            c.user_id=(select auth.uid())
            and private.is_org_member(c.organization_id)
          )
          or exists(
            select 1
            from public.client_coach_assignments a
            join public.coach_profiles cp
              on cp.id=a.coach_id
             and cp.organization_id=a.organization_id
            where a.organization_id=c.organization_id
              and a.client_id=c.id
              and a.status='active'::public.client_coach_assignment_status
              and cp.status='active'::public.coach_profile_status
              and cp.user_id=(select auth.uid())
              and private.is_org_member(c.organization_id)
          )
        )
    ),
    false
  )
$function$;

comment on function private.can_view_client_entity(uuid) is
  'F1.M1.S4: Org Admin sees tenant clients; Client sees self; Coach sees only clients with active canonical assignment.';
