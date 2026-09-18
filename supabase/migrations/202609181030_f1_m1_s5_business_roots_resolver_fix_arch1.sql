-- ARCH-1.0 · F1.M1.S5 Wave 2 hardening
-- Fix UUID aggregation in legacy tenant resolver discovered by transactional QA.

create or replace function private.resolve_legacy_client_organization_v1(
  target_client_user uuid,
  requested_organization uuid default null
)
returns uuid
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_organization uuid;
  v_count integer;
begin
  if target_client_user is null then
    raise exception 'legacy client user id is required';
  end if;

  if requested_organization is not null then
    if not exists(
      select 1
      from public.clients c
      join public.organization_members om
        on om.organization_id=c.organization_id
       and om.user_id=c.user_id
      where c.organization_id=requested_organization
        and c.user_id=target_client_user
        and c.status<>'archived'::public.client_status
        and om.status='active'::public.organization_member_status
    ) then
      raise exception 'legacy client is not active in requested organization';
    end if;
    return requested_organization;
  end if;

  select count(*) into v_count
  from public.clients c
  join public.organization_members om
    on om.organization_id=c.organization_id
   and om.user_id=c.user_id
  where c.user_id=target_client_user
    and c.status<>'archived'::public.client_status
    and om.status='active'::public.organization_member_status;

  if v_count=1 then
    select c.organization_id into v_organization
    from public.clients c
    join public.organization_members om
      on om.organization_id=c.organization_id
     and om.user_id=c.user_id
    where c.user_id=target_client_user
      and c.status<>'archived'::public.client_status
      and om.status='active'::public.organization_member_status
    limit 1;
    return v_organization;
  elsif v_count=0 then
    raise exception 'legacy client has no active canonical tenant';
  end if;

  raise exception 'legacy client belongs to multiple organizations; organization_id is required';
end;
$function$;
