-- CV Coach V92 — CV12 Admin Operations
-- Read-only audit surface for the admin UI. Sensitive mutations remain in V90.

create or replace function public.get_cv12_cutover_audit_v92(
  p_pilot_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_role public.app_role;
  v_items jsonb := '[]'::jsonb;
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;

  select p.role
    into v_role
  from public.profiles p
  where p.id = v_uid
    and p.status = 'active'::public.profile_status;

  if v_role is null or v_role not in ('admin'::public.app_role, 'coach'::public.app_role) then
    raise exception 'Coach/admin required';
  end if;

  if p_pilot_id is not null
     and v_role = 'coach'::public.app_role
     and not exists (
       select 1
       from public.coach_intelligence_pilots cp
       where cp.id = p_pilot_id
         and cp.coach_id = v_uid
     ) then
    raise exception 'Pilot not available to this coach';
  end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
    into v_items
  from (
    select
      a.id,
      a.pilot_id,
      a.client_id,
      a.actor_id,
      a.action,
      a.idempotency_key,
      a.readiness,
      a.created_at,
      a.updated_at
    from public.cv12_cutover_audit_v90 a
    join public.coach_intelligence_pilots cp on cp.id = a.pilot_id
    where (p_pilot_id is null or a.pilot_id = p_pilot_id)
      and (
        v_role = 'admin'::public.app_role
        or cp.coach_id = v_uid
      )
    order by a.created_at desc
    limit 100
  ) x;

  return jsonb_build_object(
    'ok', true,
    'engine_version', 'CV12_CUTOVER_ADMIN_V92',
    'pilot_id', p_pilot_id,
    'count', jsonb_array_length(v_items),
    'items', v_items,
    'guardrails', jsonb_build_object(
      'read_only', true,
      'mutations_via_v90_only', true,
      'auto_publish', false,
      'auto_program_edit', false
    )
  );
end;
$$;

revoke all on function public.get_cv12_cutover_audit_v92(uuid) from public;
grant execute on function public.get_cv12_cutover_audit_v92(uuid) to authenticated;

comment on function public.get_cv12_cutover_audit_v92(uuid) is
'V92 read-only audit feed for CV12 cutover operations. Mutations remain exclusively in V90.';
