-- F1.M2.S4 — PLATFORM_SUPERADMIN + auditable SupportContext
-- A platform role is global. It never becomes an Organization membership and never
-- grants raw tenant RLS access by itself.

do $$
begin
  create type public.platform_role as enum ('platform_superadmin');
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.platform_role_binding_status as enum ('active','revoked');
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.platform_support_mode as enum ('read_only','read_write');
exception when duplicate_object then null;
end $$;

create table if not exists public.platform_role_bindings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  role public.platform_role not null,
  status public.platform_role_binding_status not null default 'active',
  grant_reason text not null,
  granted_by uuid references public.profiles(id) on delete set null,
  granted_at timestamptz not null default now(),
  revoked_by uuid references public.profiles(id) on delete set null,
  revoked_at timestamptz,
  revoke_reason text,
  metadata jsonb not null default '{}'::jsonb,
  constraint platform_role_bindings_grant_reason_check
    check (char_length(btrim(grant_reason)) between 8 and 1000),
  constraint platform_role_bindings_revoke_shape_check
    check (
      (status='active'::public.platform_role_binding_status and revoked_at is null)
      or
      (status='revoked'::public.platform_role_binding_status and revoked_at is not null)
    ),
  constraint platform_role_bindings_metadata_object_check
    check (jsonb_typeof(metadata)='object')
);

create unique index if not exists platform_role_bindings_one_active_role
  on public.platform_role_bindings(user_id,role)
  where status='active'::public.platform_role_binding_status;

create index if not exists platform_role_bindings_user_status_idx
  on public.platform_role_bindings(user_id,status);

create table if not exists public.platform_support_contexts (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid not null references public.profiles(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  mode public.platform_support_mode not null default 'read_only',
  reason text not null,
  started_at timestamptz not null default now(),
  expires_at timestamptz not null,
  ended_at timestamptz,
  end_reason text,
  metadata jsonb not null default '{}'::jsonb,
  constraint platform_support_contexts_reason_check
    check (char_length(btrim(reason)) between 12 and 2000),
  constraint platform_support_contexts_expiry_check
    check (
      expires_at>started_at
      and expires_at<=started_at+interval '2 hours'
    ),
  constraint platform_support_contexts_end_check
    check (ended_at is null or ended_at>=started_at),
  constraint platform_support_contexts_metadata_object_check
    check (jsonb_typeof(metadata)='object')
);

create unique index if not exists platform_support_contexts_one_open_per_actor
  on public.platform_support_contexts(actor_user_id)
  where ended_at is null;

create index if not exists platform_support_contexts_org_time_idx
  on public.platform_support_contexts(organization_id,started_at desc);

create table if not exists public.platform_audit_events (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references public.profiles(id) on delete set null,
  event_type text not null,
  organization_id uuid references public.organizations(id) on delete set null,
  support_context_id uuid references public.platform_support_contexts(id) on delete set null,
  reason text,
  payload jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(),
  constraint platform_audit_events_type_check
    check (char_length(btrim(event_type)) between 3 and 120),
  constraint platform_audit_events_payload_object_check
    check (jsonb_typeof(payload)='object')
);

create index if not exists platform_audit_events_actor_time_idx
  on public.platform_audit_events(actor_user_id,occurred_at desc);
create index if not exists platform_audit_events_org_time_idx
  on public.platform_audit_events(organization_id,occurred_at desc);

alter table public.platform_role_bindings enable row level security;
alter table public.platform_support_contexts enable row level security;
alter table public.platform_audit_events enable row level security;

revoke all on public.platform_role_bindings from public,anon,authenticated;
revoke all on public.platform_support_contexts from public,anon,authenticated;
revoke all on public.platform_audit_events from public,anon,authenticated;
grant select,insert,update,delete on public.platform_role_bindings to service_role;
grant select,insert,update,delete on public.platform_support_contexts to service_role;
grant select,insert on public.platform_audit_events to service_role;

create or replace function private.prevent_platform_audit_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  raise exception 'platform audit events are immutable';
end;
$function$;

drop trigger if exists platform_audit_events_immutable_v1 on public.platform_audit_events;
create trigger platform_audit_events_immutable_v1
before update or delete on public.platform_audit_events
for each row execute function private.prevent_platform_audit_mutation_v1();

-- One-time compatibility cutover. Legacy active app_role=admin actors become explicit
-- global superadmins through a trusted migration, never through tenant membership.
insert into public.platform_role_bindings(
  user_id,role,status,grant_reason,granted_by,granted_at,metadata
)
select
  p.id,
  'platform_superadmin'::public.platform_role,
  'active'::public.platform_role_binding_status,
  'F1.M2.S4 trusted migration from legacy profiles.role=admin',
  null,
  now(),
  jsonb_build_object('source','legacy_app_role_admin_migration','migration','F1.M2.S4')
from public.profiles p
where p.role='admin'::public.app_role
  and p.status='active'::public.profile_status
  and not exists (
    select 1
    from public.platform_role_bindings b
    where b.user_id=p.id
      and b.role='platform_superadmin'::public.platform_role
      and b.status='active'::public.platform_role_binding_status
  );

create or replace function private.is_platform_superadmin_v1(
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    auth.role()='service_role'
    or exists(
      select 1
      from public.platform_role_bindings b
      where b.user_id=p_user_id
        and b.role='platform_superadmin'::public.platform_role
        and b.status='active'::public.platform_role_binding_status
    ),
    false
  )
$function$;

-- Compatibility name used by existing platform operations. The authority source is
-- now the global binding, never profiles.role nor Organization membership.
create or replace function private.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select private.is_platform_superadmin_v1(auth.uid())
$function$;

create or replace function private.active_platform_support_context_v1(
  p_organization_id uuid,
  p_require_write boolean default false
)
returns uuid
language sql
stable
security definer
set search_path to ''
as $function$
  select c.id
  from public.platform_support_contexts c
  where c.actor_user_id=auth.uid()
    and c.organization_id=p_organization_id
    and c.ended_at is null
    and c.expires_at>now()
    and (
      not p_require_write
      or c.mode='read_write'::public.platform_support_mode
    )
    and private.is_platform_superadmin_v1(auth.uid())
  order by c.started_at desc
  limit 1
$function$;

create or replace function private.platform_support_can_read_org_v1(
  p_organization_id uuid
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    auth.role()='service_role'
    or private.active_platform_support_context_v1(p_organization_id,false) is not null,
    false
  )
$function$;

create or replace function private.platform_support_can_write_org_v1(
  p_organization_id uuid
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    auth.role()='service_role'
    or private.active_platform_support_context_v1(p_organization_id,true) is not null,
    false
  )
$function$;

-- Raw tenant RLS helpers no longer grant access merely because an actor has a
-- global platform role.
create or replace function private.is_org_member(target_organization uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    auth.role()='service_role'
    or exists(
      select 1
      from public.organization_members om
      where om.organization_id=target_organization
        and om.user_id=auth.uid()
        and om.status='active'::public.organization_member_status
    ),
    false
  )
$function$;

create or replace function private.is_org_admin(target_organization uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    auth.role()='service_role'
    or exists(
      select 1
      from public.organization_members om
      where om.organization_id=target_organization
        and om.user_id=auth.uid()
        and om.status='active'::public.organization_member_status
        and om.role in (
          'owner'::public.organization_member_role,
          'org_admin'::public.organization_member_role
        )
    ),
    false
  )
$function$;

create or replace function private.can_view_organization(target_organization uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    auth.role()='service_role'
    or private.is_org_member(target_organization),
    false
  )
$function$;

create or replace function private.can_view_org_member_v1(
  p_organization_id uuid,
  p_member_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    auth.role()='service_role'
    or private.is_org_admin(p_organization_id)
    or (
      p_member_user_id=auth.uid()
      and private.is_org_member(p_organization_id)
    ),
    false
  )
$function$;

create or replace function private.can_view_coach_profile_v1(
  p_organization_id uuid,
  p_coach_user_id uuid,
  p_status public.coach_profile_status
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    auth.role()='service_role'
    or private.is_org_admin(p_organization_id)
    or (
      p_coach_user_id=auth.uid()
      and private.is_org_member(p_organization_id)
    )
    or (
      p_status='active'::public.coach_profile_status
      and private.is_org_member(p_organization_id)
    ),
    false
  )
$function$;

create or replace function private.can_view_client_coach_assignment(
  target_organization uuid,
  target_client uuid,
  target_coach uuid
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    auth.role()='service_role'
    or private.is_org_admin(target_organization)
    or exists(
      select 1
      from public.coach_profiles cp
      where cp.id=target_coach
        and cp.organization_id=target_organization
        and cp.user_id=auth.uid()
        and cp.status='active'::public.coach_profile_status
        and private.is_org_member(target_organization)
    )
    or exists(
      select 1
      from public.clients c
      where c.id=target_client
        and c.organization_id=target_organization
        and c.user_id=auth.uid()
        and private.is_org_member(target_organization)
    ),
    false
  )
$function$;

create or replace function private.can_view_client_entity(target_client uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    auth.role()='service_role'
    or exists(
      select 1
      from public.clients c
      where c.id=target_client
        and (
          private.is_org_admin(c.organization_id)
          or (
            c.user_id=auth.uid()
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
              and cp.user_id=auth.uid()
              and private.is_org_member(c.organization_id)
          )
        )
    ),
    false
  )
$function$;

create or replace function public.get_platform_access_context_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_uid uuid:=auth.uid();
  v_is_superadmin boolean:=false;
  v_context public.platform_support_contexts%rowtype;
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;

  v_is_superadmin:=private.is_platform_superadmin_v1(v_uid);
  if not v_is_superadmin then
    return jsonb_build_object(
      'is_platform_superadmin',false,
      'support_context',null,
      'version','F1.M2.S4_PLATFORM_ACCESS_V1'
    );
  end if;

  select * into v_context
  from public.platform_support_contexts c
  where c.actor_user_id=v_uid
    and c.ended_at is null
    and c.expires_at>now()
  order by c.started_at desc
  limit 1;

  return jsonb_build_object(
    'is_platform_superadmin',true,
    'support_context',case when found then jsonb_build_object(
      'id',v_context.id,
      'organization_id',v_context.organization_id,
      'mode',v_context.mode,
      'reason',v_context.reason,
      'started_at',v_context.started_at,
      'expires_at',v_context.expires_at
    ) else null end,
    'version','F1.M2.S4_PLATFORM_ACCESS_V1'
  );
end;
$function$;

create or replace function public.list_platform_organizations_v1()
returns table(
  organization_id uuid,
  slug text,
  display_name text,
  status public.organization_status,
  locale text,
  timezone text,
  currency text
)
language plpgsql
stable
security definer
set search_path to ''
as $function$
begin
  if not private.is_platform_superadmin_v1(auth.uid()) then
    raise exception 'PLATFORM_SUPERADMIN required';
  end if;

  return query
  select o.id,o.slug,o.display_name,o.status,o.locale,o.timezone,o.currency
  from public.organizations o
  order by lower(o.display_name),o.id;
end;
$function$;

create or replace function public.start_platform_support_context_v1(
  p_organization_id uuid,
  p_reason text,
  p_mode public.platform_support_mode default 'read_only'::public.platform_support_mode,
  p_ttl_minutes integer default 30
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid:=auth.uid();
  v_reason text:=btrim(coalesce(p_reason,''));
  v_context public.platform_support_contexts%rowtype;
  v_org_status public.organization_status;
begin
  if v_uid is null or not private.is_platform_superadmin_v1(v_uid) then
    raise exception 'PLATFORM_SUPERADMIN required';
  end if;
  if char_length(v_reason)<12 or char_length(v_reason)>2000 then
    raise exception 'support reason must be 12..2000 characters';
  end if;
  if p_ttl_minutes<5 or p_ttl_minutes>120 then
    raise exception 'support context TTL must be 5..120 minutes';
  end if;

  select o.status into v_org_status
  from public.organizations o
  where o.id=p_organization_id;
  if not found then
    raise exception 'Organization not found';
  end if;
  if v_org_status='archived'::public.organization_status
     and p_mode='read_write'::public.platform_support_mode then
    raise exception 'Archived organizations are read-only';
  end if;

  update public.platform_support_contexts c
  set ended_at=now(),
      end_reason=case
        when c.expires_at<=now() then 'expired_before_new_context'
        else 'superseded_by_new_context'
      end
  where c.actor_user_id=v_uid
    and c.ended_at is null;

  insert into public.platform_support_contexts(
    actor_user_id,organization_id,mode,reason,started_at,expires_at,metadata
  )
  values(
    v_uid,p_organization_id,p_mode,v_reason,now(),
    now()+make_interval(mins=>p_ttl_minutes),
    jsonb_build_object('source','superadmin_operations_plane')
  )
  returning * into v_context;

  insert into public.platform_audit_events(
    actor_user_id,event_type,organization_id,support_context_id,reason,payload
  )
  values(
    v_uid,'support_context_started',p_organization_id,v_context.id,v_reason,
    jsonb_build_object('mode',p_mode,'ttl_minutes',p_ttl_minutes)
  );

  return jsonb_build_object(
    'support_context_id',v_context.id,
    'organization_id',v_context.organization_id,
    'mode',v_context.mode,
    'started_at',v_context.started_at,
    'expires_at',v_context.expires_at,
    'version','F1.M2.S4_SUPPORT_CONTEXT_V1'
  );
end;
$function$;

create or replace function public.end_platform_support_context_v1(
  p_support_context_id uuid,
  p_reason text default 'manual_exit'
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid:=auth.uid();
  v_reason text:=btrim(coalesce(p_reason,'manual_exit'));
  v_context public.platform_support_contexts%rowtype;
begin
  if v_uid is null or not private.is_platform_superadmin_v1(v_uid) then
    raise exception 'PLATFORM_SUPERADMIN required';
  end if;

  select * into v_context
  from public.platform_support_contexts c
  where c.id=p_support_context_id
    and c.actor_user_id=v_uid
  for update;

  if not found then
    raise exception 'SupportContext not found';
  end if;

  if v_context.ended_at is null then
    update public.platform_support_contexts
    set ended_at=now(),end_reason=nullif(v_reason,'')
    where id=v_context.id;

    insert into public.platform_audit_events(
      actor_user_id,event_type,organization_id,support_context_id,reason,payload
    )
    values(
      v_uid,'support_context_ended',v_context.organization_id,v_context.id,v_reason,
      jsonb_build_object('mode',v_context.mode)
    );
  end if;

  return jsonb_build_object(
    'support_context_id',v_context.id,
    'ended',true,
    'version','F1.M2.S4_SUPPORT_CONTEXT_V1'
  );
end;
$function$;

-- Audited read-only tenant entry point for the Operations plane. Raw tenant RLS
-- remains membership-based; SupportContext access occurs through explicit RPCs.
create or replace function public.get_platform_support_organization_snapshot_v1(
  p_organization_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid:=auth.uid();
  v_context_id uuid;
  v_org public.organizations%rowtype;
  v_members integer:=0;
  v_coaches integer:=0;
  v_clients integer:=0;
begin
  v_context_id:=private.active_platform_support_context_v1(p_organization_id,false);
  if v_uid is null or v_context_id is null then
    raise exception 'Active SupportContext required';
  end if;

  select * into v_org
  from public.organizations o
  where o.id=p_organization_id;
  if not found then
    raise exception 'Organization not found';
  end if;

  select count(*)::integer into v_members
  from public.organization_members om
  where om.organization_id=p_organization_id
    and om.status='active'::public.organization_member_status;

  select count(*)::integer into v_coaches
  from public.coach_profiles cp
  where cp.organization_id=p_organization_id
    and cp.status='active'::public.coach_profile_status;

  select count(*)::integer into v_clients
  from public.clients c
  where c.organization_id=p_organization_id
    and c.status<>'archived'::public.client_status;

  insert into public.platform_audit_events(
    actor_user_id,event_type,organization_id,support_context_id,reason,payload
  )
  values(
    v_uid,'support_tenant_snapshot_read',p_organization_id,v_context_id,null,
    jsonb_build_object(
      'active_members',v_members,
      'active_coaches',v_coaches,
      'non_archived_clients',v_clients
    )
  );

  return jsonb_build_object(
    'organization',jsonb_build_object(
      'id',v_org.id,
      'slug',v_org.slug,
      'display_name',v_org.display_name,
      'status',v_org.status,
      'locale',v_org.locale,
      'timezone',v_org.timezone,
      'currency',v_org.currency,
      'branding_config',v_org.branding_config,
      'feature_flags',v_org.feature_flags
    ),
    'counts',jsonb_build_object(
      'active_members',v_members,
      'active_coaches',v_coaches,
      'non_archived_clients',v_clients
    ),
    'support_context_id',v_context_id,
    'version','F1.M2.S4_SUPPORT_SNAPSHOT_V1'
  );
end;
$function$;

revoke all on function public.get_platform_access_context_v1() from public,anon;
revoke all on function public.list_platform_organizations_v1() from public,anon;
revoke all on function public.start_platform_support_context_v1(uuid,text,public.platform_support_mode,integer) from public,anon;
revoke all on function public.end_platform_support_context_v1(uuid,text) from public,anon;
revoke all on function public.get_platform_support_organization_snapshot_v1(uuid) from public,anon;

grant execute on function public.get_platform_access_context_v1() to authenticated,service_role;
grant execute on function public.list_platform_organizations_v1() to authenticated,service_role;
grant execute on function public.start_platform_support_context_v1(uuid,text,public.platform_support_mode,integer) to authenticated,service_role;
grant execute on function public.end_platform_support_context_v1(uuid,text) to authenticated,service_role;
grant execute on function public.get_platform_support_organization_snapshot_v1(uuid) to authenticated,service_role;

grant execute on function private.is_platform_superadmin_v1(uuid) to authenticated,service_role;
grant execute on function private.platform_support_can_read_org_v1(uuid) to authenticated,service_role;
grant execute on function private.platform_support_can_write_org_v1(uuid) to authenticated,service_role;

comment on table public.platform_role_bindings is
'F1.M2.S4 global platform roles. PLATFORM_SUPERADMIN is independent from Organization membership.';
comment on table public.platform_support_contexts is
'F1.M2.S4 time-boxed, explicit tenant support scope for PLATFORM_SUPERADMIN.';
comment on table public.platform_audit_events is
'F1.M2.S4 immutable audit trail for privileged platform/support activity.';
comment on function public.start_platform_support_context_v1(uuid,text,public.platform_support_mode,integer) is
'F1.M2.S4 opens an explicit, reasoned and expiring SupportContext. It never creates tenant membership.';
