-- F1.M2.S5 — tenant-scoped multi-role ORG_ADMIN foundation
-- organization_members.role remains a compatibility projection while
-- organization_member_roles becomes the authoritative multi-role assignment source.

do $$
begin
  create type public.organization_member_role_assignment_status
    as enum ('active','revoked');
exception when duplicate_object then null;
end $$;

create table if not exists public.organization_member_roles (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.organization_members(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role public.organization_member_role not null,
  status public.organization_member_role_assignment_status not null default 'active',
  grant_reason text not null,
  granted_by uuid references public.profiles(id) on delete set null,
  granted_at timestamptz not null default now(),
  revoked_by uuid references public.profiles(id) on delete set null,
  revoked_at timestamptz,
  revoke_reason text,
  metadata jsonb not null default '{}'::jsonb,
  constraint organization_member_roles_grant_reason_check
    check (char_length(btrim(grant_reason)) between 4 and 1000),
  constraint organization_member_roles_revoke_shape_check
    check (
      (status='active'::public.organization_member_role_assignment_status and revoked_at is null)
      or
      (status='revoked'::public.organization_member_role_assignment_status and revoked_at is not null)
    ),
  constraint organization_member_roles_metadata_object_check
    check (jsonb_typeof(metadata)='object')
);

create unique index if not exists organization_member_roles_one_active
  on public.organization_member_roles(member_id,role)
  where status='active'::public.organization_member_role_assignment_status;

create index if not exists organization_member_roles_org_user_idx
  on public.organization_member_roles(organization_id,user_id,status);

create table if not exists public.organization_permission_audit (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  member_id uuid references public.organization_members(id) on delete set null,
  target_user_id uuid references public.profiles(id) on delete set null,
  actor_user_id uuid references public.profiles(id) on delete set null,
  action text not null,
  role public.organization_member_role,
  reason text,
  payload jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(),
  constraint organization_permission_audit_action_check
    check (char_length(btrim(action)) between 3 and 120),
  constraint organization_permission_audit_payload_object_check
    check (jsonb_typeof(payload)='object')
);

create index if not exists organization_permission_audit_org_time_idx
  on public.organization_permission_audit(organization_id,occurred_at desc);

alter table public.organization_member_roles enable row level security;
alter table public.organization_permission_audit enable row level security;

revoke insert,update,delete on public.organization_member_roles from anon,authenticated;
revoke insert,update,delete on public.organization_permission_audit from anon,authenticated;

create or replace function private.guard_organization_member_role_identity_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_member public.organization_members%rowtype;
begin
  select * into v_member
  from public.organization_members om
  where om.id=new.member_id;

  if not found then
    raise exception 'Organization membership not found';
  end if;

  if new.organization_id is null then new.organization_id:=v_member.organization_id; end if;
  if new.user_id is null then new.user_id:=v_member.user_id; end if;

  if new.organization_id<>v_member.organization_id or new.user_id<>v_member.user_id then
    raise exception 'Role assignment cannot cross membership tenant identity';
  end if;

  if tg_op='UPDATE' and (
    new.member_id is distinct from old.member_id
    or new.organization_id is distinct from old.organization_id
    or new.user_id is distinct from old.user_id
  ) then
    raise exception 'Role assignment tenant identity is immutable';
  end if;

  return new;
end;
$function$;

drop trigger if exists organization_member_roles_identity_v1 on public.organization_member_roles;
create trigger organization_member_roles_identity_v1
before insert or update on public.organization_member_roles
for each row execute function private.guard_organization_member_role_identity_v1();

create or replace function private.prevent_organization_permission_audit_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  raise exception 'organization permission audit is immutable';
end;
$function$;

drop trigger if exists organization_permission_audit_immutable_v1
  on public.organization_permission_audit;
create trigger organization_permission_audit_immutable_v1
before update or delete on public.organization_permission_audit
for each row execute function private.prevent_organization_permission_audit_mutation_v1();

-- Seed one authoritative role assignment from every existing legacy membership.
insert into public.organization_member_roles(
  member_id,organization_id,user_id,role,status,grant_reason,granted_by,granted_at,metadata
)
select
  om.id,om.organization_id,om.user_id,om.role,
  'active'::public.organization_member_role_assignment_status,
  'F1.M2.S5 trusted migration from organization_members.role',
  null,
  coalesce(om.joined_at,om.created_at,now()),
  jsonb_build_object('source','legacy_membership_role_migration','migration','F1.M2.S5')
from public.organization_members om
where not exists (
  select 1
  from public.organization_member_roles mr
  where mr.member_id=om.id
    and mr.role=om.role
    and mr.status='active'::public.organization_member_role_assignment_status
);

create or replace function private.member_has_org_role_v1(
  p_organization_id uuid,
  p_user_id uuid,
  p_role public.organization_member_role
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(exists(
    select 1
    from public.organization_members om
    join public.organization_member_roles mr
      on mr.member_id=om.id
     and mr.organization_id=om.organization_id
     and mr.user_id=om.user_id
    where om.organization_id=p_organization_id
      and om.user_id=p_user_id
      and om.status='active'::public.organization_member_status
      and mr.role=p_role
      and mr.status='active'::public.organization_member_role_assignment_status
  ),false)
$function$;

create or replace function private.current_org_roles_v1(
  p_organization_id uuid,
  p_user_id uuid default auth.uid()
)
returns public.organization_member_role[]
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    array_agg(
      mr.role
      order by case mr.role
        when 'owner'::public.organization_member_role then 1
        when 'org_admin'::public.organization_member_role then 2
        when 'coach'::public.organization_member_role then 3
        when 'client'::public.organization_member_role then 4
        else 99
      end
    ),
    array[]::public.organization_member_role[]
  )
  from public.organization_members om
  join public.organization_member_roles mr
    on mr.member_id=om.id
   and mr.status='active'::public.organization_member_role_assignment_status
  where om.organization_id=p_organization_id
    and om.user_id=p_user_id
    and om.status='active'::public.organization_member_status
$function$;

create or replace function private.current_org_role_v1(
  p_organization_id uuid,
  p_user_id uuid default auth.uid()
)
returns public.organization_member_role
language sql
stable
security definer
set search_path to ''
as $function$
  select roles[1]
  from (
    select private.current_org_roles_v1(p_organization_id,p_user_id) as roles
  ) x
$function$;

create or replace function private.is_org_owner_v1(
  p_organization_id uuid,
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    exists(
      select 1
      from public.organizations o
      where o.id=p_organization_id
        and o.owner_user_id=p_user_id
    )
    and private.member_has_org_role_v1(
      p_organization_id,p_user_id,'owner'::public.organization_member_role
    ),
    false
  )
$function$;

-- S4 global SuperAdmin remains separate; tenant administration is resolved only
-- from active tenant role assignments (plus service_role for backend operations).
create or replace function private.is_org_admin(target_organization uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    auth.role()='service_role'
    or private.is_org_owner_v1(target_organization,auth.uid())
    or private.member_has_org_role_v1(
      target_organization,auth.uid(),'org_admin'::public.organization_member_role
    ),
    false
  )
$function$;

create or replace function private.cv_is_coach_admin_in_org_v62(
  p_organization uuid,
  p_actor uuid
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    exists(
      select 1
      from public.organization_members om
      join public.profiles p on p.id=om.user_id
      where om.organization_id=p_organization
        and om.user_id=p_actor
        and om.status='active'::public.organization_member_status
        and p.status='active'::public.profile_status
    )
    and (
      private.is_org_owner_v1(p_organization,p_actor)
      or private.member_has_org_role_v1(
        p_organization,p_actor,'org_admin'::public.organization_member_role
      )
      or private.member_has_org_role_v1(
        p_organization,p_actor,'coach'::public.organization_member_role
      )
    ),
    false
  )
$function$;

create or replace function private.actor_can_manage_client_in_org_v1(
  p_actor_id uuid,
  p_organization_id uuid,
  p_client_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    (
      private.is_org_owner_v1(p_organization_id,p_actor_id)
      or private.member_has_org_role_v1(
        p_organization_id,p_actor_id,'org_admin'::public.organization_member_role
      )
    )
    and exists(
      select 1
      from public.clients c
      where c.organization_id=p_organization_id
        and c.user_id=p_client_user_id
        and c.status<>'archived'::public.client_status
    )
    or exists(
      select 1
      from public.clients c
      join public.coach_profiles cp
        on cp.organization_id=c.organization_id
       and cp.user_id=p_actor_id
       and cp.status='active'::public.coach_profile_status
      join public.client_coach_assignments a
        on a.organization_id=c.organization_id
       and a.client_id=c.id
       and a.coach_id=cp.id
       and a.status='active'::public.client_coach_assignment_status
      where c.organization_id=p_organization_id
        and c.user_id=p_client_user_id
        and c.status<>'archived'::public.client_status
        and private.member_has_org_role_v1(
          p_organization_id,p_actor_id,'coach'::public.organization_member_role
        )
    ),
    false
  )
$function$;

create or replace function private.resolve_legacy_professional_organization_v1(
  target_actor uuid,
  target_client_user uuid default null::uuid
)
returns uuid
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_orgs uuid[];
begin
  if target_actor is null then
    raise exception 'actor is required';
  end if;

  if target_client_user is not null then
    select array_agg(distinct om.organization_id order by om.organization_id)
      into v_orgs
    from public.organization_members om
    join public.organizations o on o.id=om.organization_id
    join public.clients c
      on c.organization_id=om.organization_id
     and c.user_id=target_client_user
     and c.status<>'archived'::public.client_status
    where om.user_id=target_actor
      and om.status='active'::public.organization_member_status
      and o.status in (
        'trial'::public.organization_status,
        'active'::public.organization_status
      )
      and (
        private.is_org_owner_v1(om.organization_id,target_actor)
        or private.member_has_org_role_v1(
          om.organization_id,target_actor,'org_admin'::public.organization_member_role
        )
        or private.member_has_org_role_v1(
          om.organization_id,target_actor,'coach'::public.organization_member_role
        )
      );

    if coalesce(cardinality(v_orgs),0)=1 then
      return v_orgs[1];
    elsif coalesce(cardinality(v_orgs),0)>1 then
      raise exception 'actor/client belongs to multiple organizations; organization_id is required';
    end if;
  end if;

  select array_agg(distinct om.organization_id order by om.organization_id)
    into v_orgs
  from public.organization_members om
  join public.organizations o on o.id=om.organization_id
  where om.user_id=target_actor
    and om.status='active'::public.organization_member_status
    and o.status in (
      'trial'::public.organization_status,
      'active'::public.organization_status
    )
    and (
      private.is_org_owner_v1(om.organization_id,target_actor)
      or private.member_has_org_role_v1(
        om.organization_id,target_actor,'org_admin'::public.organization_member_role
      )
      or private.member_has_org_role_v1(
        om.organization_id,target_actor,'coach'::public.organization_member_role
      )
    );

  if coalesce(cardinality(v_orgs),0)=0 then
    raise exception 'actor has no active professional organization';
  elsif cardinality(v_orgs)>1 then
    raise exception 'actor belongs to multiple organizations; organization_id is required';
  end if;

  return v_orgs[1];
end;
$function$;

create or replace function private.recompute_organization_member_primary_role_v1(
  p_member_id uuid
)
returns public.organization_member_role
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_role public.organization_member_role;
begin
  select mr.role into v_role
  from public.organization_member_roles mr
  where mr.member_id=p_member_id
    and mr.status='active'::public.organization_member_role_assignment_status
  order by case mr.role
    when 'owner'::public.organization_member_role then 1
    when 'org_admin'::public.organization_member_role then 2
    when 'coach'::public.organization_member_role then 3
    when 'client'::public.organization_member_role then 4
    else 99
  end
  limit 1;

  if v_role is not null then
    update public.organization_members
    set role=v_role,updated_at=now()
    where id=p_member_id
      and role is distinct from v_role;
  end if;

  return v_role;
end;
$function$;

create or replace function private.sync_legacy_organization_member_role_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if new.role='owner'::public.organization_member_role
     and not exists(
       select 1
       from public.organizations o
       where o.id=new.organization_id
         and o.owner_user_id=new.user_id
     ) then
    raise exception 'owner role is reserved for organization.owner_user_id';
  end if;

  insert into public.organization_member_roles(
    member_id,organization_id,user_id,role,status,grant_reason,granted_by,granted_at,metadata
  )
  values(
    new.id,new.organization_id,new.user_id,new.role,
    'active'::public.organization_member_role_assignment_status,
    'Legacy organization_members.role synchronization',
    auth.uid(),
    now(),
    jsonb_build_object('source','organization_members_role_sync')
  )
  on conflict (member_id,role)
    where status='active'::public.organization_member_role_assignment_status
  do nothing;

  if tg_op='UPDATE' and new.role is distinct from old.role then
    insert into public.organization_permission_audit(
      organization_id,member_id,target_user_id,actor_user_id,action,role,reason,payload
    )
    values(
      new.organization_id,new.id,new.user_id,auth.uid(),
      'legacy_primary_role_changed',new.role,
      'Compatibility projection changed through organization_members.role',
      jsonb_build_object('old_role',old.role,'new_role',new.role)
    );
  end if;

  return new;
end;
$function$;

drop trigger if exists organization_members_role_sync_v1 on public.organization_members;
create trigger organization_members_role_sync_v1
after insert or update of role on public.organization_members
for each row execute function private.sync_legacy_organization_member_role_v1();

create or replace function private.prevent_organization_permission_audit_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  raise exception 'organization permission audit is immutable';
end;
$function$;

drop trigger if exists organization_permission_audit_immutable_v1
  on public.organization_permission_audit;
create trigger organization_permission_audit_immutable_v1
before update or delete on public.organization_permission_audit
for each row execute function private.prevent_organization_permission_audit_mutation_v1();

create policy organization_member_roles_select_v1
on public.organization_member_roles
for select
to authenticated
using (
  private.can_view_org_member_v1(organization_id,user_id)
);

create policy organization_permission_audit_select_v1
on public.organization_permission_audit
for select
to authenticated
using (
  private.is_org_admin(organization_id)
);

grant select on public.organization_member_roles to authenticated;
grant select on public.organization_permission_audit to authenticated;

create or replace function private.resolve_org_capabilities_v1(
  p_organization_id uuid,
  p_user_id uuid default auth.uid()
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_roles public.organization_member_role[];
  v_owner boolean:=false;
  v_admin boolean:=false;
  v_coach boolean:=false;
  v_client boolean:=false;
begin
  v_roles:=private.current_org_roles_v1(p_organization_id,p_user_id);
  v_owner:=private.is_org_owner_v1(p_organization_id,p_user_id);
  v_admin:=private.member_has_org_role_v1(
    p_organization_id,p_user_id,'org_admin'::public.organization_member_role
  );
  v_coach:=private.member_has_org_role_v1(
    p_organization_id,p_user_id,'coach'::public.organization_member_role
  );
  v_client:=private.member_has_org_role_v1(
    p_organization_id,p_user_id,'client'::public.organization_member_role
  );

  return jsonb_build_object(
    'organization_id',p_organization_id,
    'user_id',p_user_id,
    'roles',to_jsonb(v_roles),
    'is_owner',v_owner,
    'is_org_admin',v_admin,
    'is_coach',v_coach,
    'is_client',v_client,
    'capabilities',jsonb_build_object(
      'manage_members',v_owner or v_admin,
      'manage_coaches',v_owner or v_admin,
      'manage_clients',v_owner or v_admin,
      'manage_programs',v_owner or v_admin or v_coach,
      'manage_configuration',v_owner or v_admin,
      'manage_billing',v_owner,
      'transfer_ownership',v_owner,
      'manage_custom_domain',v_owner,
      'coach_clients',v_coach
    ),
    'version','F1.M2.S5_ORG_CAPABILITIES_V1'
  );
end;
$function$;

create or replace function public.get_organization_member_capabilities_v1(
  p_organization_id uuid,
  p_user_id uuid default auth.uid()
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_actor uuid:=auth.uid();
begin
  if v_actor is null then
    raise exception 'Authentication required';
  end if;

  if p_user_id<>v_actor and not private.is_org_admin(p_organization_id) then
    raise exception 'Organization member outside actor scope';
  end if;

  if not exists(
    select 1
    from public.organization_members om
    where om.organization_id=p_organization_id
      and om.user_id=p_user_id
      and om.status='active'::public.organization_member_status
  ) then
    raise exception 'Active organization membership required';
  end if;

  return private.resolve_org_capabilities_v1(p_organization_id,p_user_id);
end;
$function$;

create or replace function public.set_organization_member_role_v1(
  p_organization_id uuid,
  p_target_user_id uuid,
  p_role public.organization_member_role,
  p_enabled boolean,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid:=auth.uid();
  v_reason text:=btrim(coalesce(p_reason,''));
  v_member public.organization_members%rowtype;
  v_assignment public.organization_member_roles%rowtype;
  v_remaining integer:=0;
  v_primary public.organization_member_role;
begin
  if v_actor is null then
    raise exception 'Authentication required';
  end if;

  if not private.is_org_admin(p_organization_id) then
    raise exception 'ORG_ADMIN or ORG_OWNER required';
  end if;

  if char_length(v_reason)<4 or char_length(v_reason)>1000 then
    raise exception 'permission change reason must be 4..1000 characters';
  end if;

  if p_role='owner'::public.organization_member_role then
    raise exception 'OWNER role changes require the dedicated ownership transfer flow';
  end if;

  if p_role='org_admin'::public.organization_member_role
     and not private.is_org_owner_v1(p_organization_id,v_actor) then
    raise exception 'Only ORG_OWNER can grant or revoke ORG_ADMIN';
  end if;

  select * into v_member
  from public.organization_members om
  where om.organization_id=p_organization_id
    and om.user_id=p_target_user_id
    and om.status<>'removed'::public.organization_member_status
  for update;

  if not found then
    raise exception 'Target organization membership not found';
  end if;

  if p_enabled then
    insert into public.organization_member_roles(
      member_id,organization_id,user_id,role,status,grant_reason,granted_by,granted_at,metadata
    )
    values(
      v_member.id,p_organization_id,p_target_user_id,p_role,
      'active'::public.organization_member_role_assignment_status,
      v_reason,v_actor,now(),
      jsonb_build_object('source','set_organization_member_role_v1')
    )
    on conflict (member_id,role)
      where status='active'::public.organization_member_role_assignment_status
    do update set
      grant_reason=excluded.grant_reason,
      granted_by=excluded.granted_by,
      granted_at=excluded.granted_at,
      metadata=excluded.metadata
    returning * into v_assignment;

    insert into public.organization_permission_audit(
      organization_id,member_id,target_user_id,actor_user_id,action,role,reason,payload
    )
    values(
      p_organization_id,v_member.id,p_target_user_id,v_actor,
      'role_granted',p_role,v_reason,
      jsonb_build_object('assignment_id',v_assignment.id)
    );
  else
    select * into v_assignment
    from public.organization_member_roles mr
    where mr.member_id=v_member.id
      and mr.role=p_role
      and mr.status='active'::public.organization_member_role_assignment_status
    for update;

    if found then
      select count(*)::integer into v_remaining
      from public.organization_member_roles mr
      where mr.member_id=v_member.id
        and mr.status='active'::public.organization_member_role_assignment_status
        and mr.role<>p_role;

      if v_remaining=0 then
        raise exception 'A membership must retain at least one active tenant role';
      end if;

      update public.organization_member_roles
      set
        status='revoked'::public.organization_member_role_assignment_status,
        revoked_by=v_actor,
        revoked_at=now(),
        revoke_reason=v_reason
      where id=v_assignment.id;

      insert into public.organization_permission_audit(
        organization_id,member_id,target_user_id,actor_user_id,action,role,reason,payload
      )
      values(
        p_organization_id,v_member.id,p_target_user_id,v_actor,
        'role_revoked',p_role,v_reason,
        jsonb_build_object('assignment_id',v_assignment.id)
      );
    end if;
  end if;

  v_primary:=private.recompute_organization_member_primary_role_v1(v_member.id);

  return private.resolve_org_capabilities_v1(
    p_organization_id,p_target_user_id
  ) || jsonb_build_object(
    'primary_role',v_primary,
    'permission_change_audited',true
  );
end;
$function$;

revoke all on function public.get_organization_member_capabilities_v1(uuid,uuid)
  from public,anon;
revoke all on function public.set_organization_member_role_v1(
  uuid,uuid,public.organization_member_role,boolean,text
) from public,anon;

grant execute on function public.get_organization_member_capabilities_v1(uuid,uuid)
  to authenticated,service_role;
grant execute on function public.set_organization_member_role_v1(
  uuid,uuid,public.organization_member_role,boolean,text
) to authenticated,service_role;

comment on table public.organization_member_roles is
'F1.M2.S5 authoritative tenant multi-role assignments. organization_members.role remains a compatibility primary-role projection.';
comment on table public.organization_permission_audit is
'F1.M2.S5 immutable audit trail for tenant permission/role changes.';
comment on function public.set_organization_member_role_v1(
  uuid,uuid,public.organization_member_role,boolean,text
) is
'F1.M2.S5 audited tenant role mutation. OWNER is excluded and platform roles are structurally impossible.';
