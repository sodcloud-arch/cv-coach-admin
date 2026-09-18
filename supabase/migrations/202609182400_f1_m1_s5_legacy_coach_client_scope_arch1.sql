-- ARCH-1.0 · F1.M1.S5 Wave G1A — Legacy Coach/Client shadow tenant scope
-- Keeps legacy compatibility tables, but makes their ownership and authorization
-- explicitly Organization-scoped so they cannot become a cross-tenant side channel.

alter table public.coach_clients
  add column if not exists organization_id uuid;

alter table public.client_invites
  add column if not exists organization_id uuid;

alter table public.coach_client_notes
  add column if not exists organization_id uuid;

-- ---------------------------------------------------------------------------
-- 1) Deterministic backfill
-- ---------------------------------------------------------------------------

update public.coach_clients cc
set organization_id=(
  select a.organization_id
  from public.coach_profiles cp
  join public.clients c
    on c.organization_id=cp.organization_id
   and c.user_id=cc.client_id
   and c.status<>'archived'::public.client_status
  join public.client_coach_assignments a
    on a.organization_id=cp.organization_id
   and a.coach_id=cp.id
   and a.client_id=c.id
  where cp.user_id=cc.coach_id
    and cp.status='active'::public.coach_profile_status
    and (
      cc.status<>'active'::public.coach_client_status
      or a.status='active'::public.client_coach_assignment_status
    )
  order by
    (a.status='active'::public.client_coach_assignment_status) desc,
    a.assigned_at desc
  limit 1
)
where cc.organization_id is null;

update public.client_invites i
set organization_id=coalesce(
  (
    select c.organization_id
    from public.clients c
    join public.organization_members om
      on om.organization_id=c.organization_id
     and om.user_id=i.coach_id
     and om.status='active'::public.organization_member_status
     and om.role in (
       'owner'::public.organization_member_role,
       'org_admin'::public.organization_member_role,
       'coach'::public.organization_member_role
     )
    where i.client_id is not null
      and c.user_id=i.client_id
      and c.status<>'archived'::public.client_status
    order by c.created_at
    limit 1
  ),
  private.resolve_legacy_professional_organization_v1(i.coach_id,null)
)
where i.organization_id is null;

update public.coach_client_notes n
set organization_id=private.resolve_legacy_professional_organization_v1(
  n.coach_id,n.client_id
)
where n.organization_id is null;

do $$
begin
  if exists(
    select 1 from public.coach_clients where organization_id is null
  ) or exists(
    select 1 from public.client_invites where organization_id is null
  ) or exists(
    select 1 from public.coach_client_notes where organization_id is null
  ) then
    raise exception 'F1.M1.S5 G1A backfill left unscoped rows';
  end if;

  if exists(
    select 1
    from public.coach_clients cc
    where not exists(
      select 1
      from public.coach_profiles cp
      join public.clients c
        on c.organization_id=cp.organization_id
       and c.user_id=cc.client_id
       and c.status<>'archived'::public.client_status
      where cp.organization_id=cc.organization_id
        and cp.user_id=cc.coach_id
        and cp.status='active'::public.coach_profile_status
    )
  ) then
    raise exception 'F1.M1.S5 G1A coach_clients canonical tenant validation failed';
  end if;
end $$;

alter table public.coach_clients
  alter column organization_id set not null;
alter table public.client_invites
  alter column organization_id set not null;
alter table public.coach_client_notes
  alter column organization_id set not null;

-- ---------------------------------------------------------------------------
-- 2) Physical tenant boundaries
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists(
    select 1 from pg_constraint
    where connamespace='public'::regnamespace
      and conname='coach_clients_organization_id_fkey'
  ) then
    alter table public.coach_clients
      add constraint coach_clients_organization_id_fkey
      foreign key (organization_id)
      references public.organizations(id)
      on delete restrict;
  end if;

  if not exists(
    select 1 from pg_constraint
    where connamespace='public'::regnamespace
      and conname='coach_clients_coach_same_org'
  ) then
    alter table public.coach_clients
      add constraint coach_clients_coach_same_org
      foreign key (organization_id,coach_id)
      references public.coach_profiles(organization_id,user_id)
      on delete cascade;
  end if;

  if not exists(
    select 1 from pg_constraint
    where connamespace='public'::regnamespace
      and conname='coach_clients_client_same_org'
  ) then
    alter table public.coach_clients
      add constraint coach_clients_client_same_org
      foreign key (organization_id,client_id)
      references public.clients(organization_id,user_id)
      on delete cascade;
  end if;

  if not exists(
    select 1 from pg_constraint
    where connamespace='public'::regnamespace
      and conname='client_invites_organization_id_fkey'
  ) then
    alter table public.client_invites
      add constraint client_invites_organization_id_fkey
      foreign key (organization_id)
      references public.organizations(id)
      on delete restrict;
  end if;

  if not exists(
    select 1 from pg_constraint
    where connamespace='public'::regnamespace
      and conname='client_invites_coach_same_org'
  ) then
    alter table public.client_invites
      add constraint client_invites_coach_same_org
      foreign key (organization_id,coach_id)
      references public.organization_members(organization_id,user_id)
      on delete restrict;
  end if;

  if not exists(
    select 1 from pg_constraint
    where connamespace='public'::regnamespace
      and conname='client_invites_client_same_org'
  ) then
    alter table public.client_invites
      add constraint client_invites_client_same_org
      foreign key (organization_id,client_id)
      references public.clients(organization_id,user_id)
      on delete cascade;
  end if;

  if not exists(
    select 1 from pg_constraint
    where connamespace='public'::regnamespace
      and conname='coach_client_notes_organization_id_fkey'
  ) then
    alter table public.coach_client_notes
      add constraint coach_client_notes_organization_id_fkey
      foreign key (organization_id)
      references public.organizations(id)
      on delete restrict;
  end if;

  if not exists(
    select 1 from pg_constraint
    where connamespace='public'::regnamespace
      and conname='coach_client_notes_coach_same_org'
  ) then
    alter table public.coach_client_notes
      add constraint coach_client_notes_coach_same_org
      foreign key (organization_id,coach_id)
      references public.coach_profiles(organization_id,user_id)
      on delete cascade;
  end if;

  if not exists(
    select 1 from pg_constraint
    where connamespace='public'::regnamespace
      and conname='coach_client_notes_client_same_org'
  ) then
    alter table public.coach_client_notes
      add constraint coach_client_notes_client_same_org
      foreign key (organization_id,client_id)
      references public.clients(organization_id,user_id)
      on delete cascade;
  end if;
end $$;

-- Active compatibility shadow is independent per Organization.
drop index if exists public.uq_coach_clients_active;
create unique index uq_coach_clients_active_org
  on public.coach_clients(organization_id,coach_id,client_id)
  where status='active'::public.coach_client_status;

create index if not exists ix_coach_clients_org_coach_status
  on public.coach_clients(organization_id,coach_id,status);
create index if not exists ix_coach_clients_org_client_status
  on public.coach_clients(organization_id,client_id,status);
create index if not exists ix_client_invites_org_coach_status
  on public.client_invites(organization_id,coach_id,status,created_at desc);
create index if not exists ix_coach_client_notes_org_client
  on public.coach_client_notes(organization_id,client_id,created_at desc);

-- ---------------------------------------------------------------------------
-- 3) Compatibility guards
-- ---------------------------------------------------------------------------

create or replace function private.guard_legacy_coach_client_relation_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_org uuid;
  v_coach_entity uuid;
  v_client_entity uuid;
begin
  if new.organization_id is null then
    v_org:=private.resolve_legacy_professional_organization_v1(
      new.coach_id,new.client_id
    );
    new.organization_id:=v_org;
  end if;

  select cp.id,c.id
    into v_coach_entity,v_client_entity
  from public.coach_profiles cp
  join public.clients c
    on c.organization_id=cp.organization_id
   and c.user_id=new.client_id
   and c.status<>'archived'::public.client_status
  where cp.organization_id=new.organization_id
    and cp.user_id=new.coach_id
    and cp.status='active'::public.coach_profile_status
  limit 1;

  if v_coach_entity is null or v_client_entity is null then
    raise exception 'legacy coach/client relation crosses organization boundary';
  end if;

  -- The legacy shadow may mirror authority, but may never create authority.
  if (
      tg_table_name='coach_client_notes'
      or (
        tg_table_name='coach_clients'
        and new.status='active'::public.coach_client_status
      )
     )
     and not exists(
       select 1
       from public.client_coach_assignments a
       where a.organization_id=new.organization_id
         and a.coach_id=v_coach_entity
         and a.client_id=v_client_entity
         and a.status='active'::public.client_coach_assignment_status
     ) then
    raise exception 'legacy coach/client write requires canonical active assignment';
  end if;

  if tg_op='UPDATE' and (
    new.organization_id is distinct from old.organization_id
    or new.coach_id is distinct from old.coach_id
    or new.client_id is distinct from old.client_id
  ) then
    raise exception 'legacy coach/client tenant identity is immutable';
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_coach_clients_tenant_v1
  on public.coach_clients;
create trigger trg_coach_clients_tenant_v1
before insert or update on public.coach_clients
for each row execute function private.guard_legacy_coach_client_relation_v1();

drop trigger if exists trg_coach_client_notes_tenant_v1
  on public.coach_client_notes;
create trigger trg_coach_client_notes_tenant_v1
before insert or update on public.coach_client_notes
for each row execute function private.guard_legacy_coach_client_relation_v1();

create or replace function private.guard_client_invite_tenant_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_org uuid;
begin
  if new.organization_id is null then
    if new.client_id is not null then
      v_org:=private.resolve_legacy_professional_organization_v1(
        new.coach_id,new.client_id
      );
    else
      v_org:=private.resolve_legacy_professional_organization_v1(
        new.coach_id,null
      );
    end if;
    new.organization_id:=v_org;
  end if;

  if not exists(
    select 1
    from public.organization_members om
    where om.organization_id=new.organization_id
      and om.user_id=new.coach_id
      and om.status='active'::public.organization_member_status
      and om.role in (
        'owner'::public.organization_member_role,
        'org_admin'::public.organization_member_role,
        'coach'::public.organization_member_role
      )
  ) then
    raise exception 'invite coach is not active in organization';
  end if;

  if new.client_id is not null
     and not exists(
       select 1
       from public.clients c
       where c.organization_id=new.organization_id
         and c.user_id=new.client_id
         and c.status<>'archived'::public.client_status
     ) then
    raise exception 'invite client crosses organization boundary';
  end if;

  if tg_op='UPDATE' and (
    new.organization_id is distinct from old.organization_id
    or new.coach_id is distinct from old.coach_id
    or new.client_id is distinct from old.client_id
  ) then
    raise exception 'invite tenant identity is immutable';
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_client_invites_tenant_v1
  on public.client_invites;
create trigger trg_client_invites_tenant_v1
before insert or update on public.client_invites
for each row execute function private.guard_client_invite_tenant_v1();

-- ---------------------------------------------------------------------------
-- 4) Safe legacy authorization wrappers
-- ---------------------------------------------------------------------------

create or replace function private.can_manage_client(
  target_client uuid
)
returns boolean
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_org uuid;
begin
  if target_client is null or auth.uid() is null then
    return false;
  end if;

  -- Legacy calls do not carry tenant context. Resolve only when the client
  -- currently belongs to exactly one active canonical Organization.
  v_org:=private.resolve_legacy_client_organization_v1(
    target_client,null
  );

  return private.can_manage_client_in_org(
    v_org,target_client
  );
end;
$function$;

create or replace function private.can_view_client(
  target_client uuid
)
returns boolean
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_org uuid;
begin
  if target_client is null or auth.uid() is null then
    return false;
  end if;

  v_org:=private.resolve_legacy_client_organization_v1(
    target_client,null
  );

  return private.can_view_client_in_org(
    v_org,target_client
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 5) Tenant-aware RLS for compatibility tables
-- ---------------------------------------------------------------------------

drop policy if exists coach_clients_select on public.coach_clients;
create policy coach_clients_select_v2
on public.coach_clients for select
to authenticated
using (
  (
    client_id=(select auth.uid())
    and private.is_org_member(organization_id)
  )
  or (
    coach_id=(select auth.uid())
    and private.actor_can_manage_client_in_org_v1(
      coach_id,organization_id,client_id
    )
  )
  or private.is_org_admin(organization_id)
);

drop policy if exists client_invites_select on public.client_invites;
create policy client_invites_select_v2
on public.client_invites for select
to authenticated
using (
  (
    coach_id=(select auth.uid())
    and private.is_org_member(organization_id)
  )
  or private.is_org_admin(organization_id)
);

drop policy if exists coach_client_notes_delete on public.coach_client_notes;
drop policy if exists coach_client_notes_insert on public.coach_client_notes;
drop policy if exists coach_client_notes_select on public.coach_client_notes;
drop policy if exists coach_client_notes_update on public.coach_client_notes;

create policy coach_client_notes_select_v2
on public.coach_client_notes for select
to authenticated
using (
  (
    coach_id=(select auth.uid())
    and private.actor_can_manage_client_in_org_v1(
      coach_id,organization_id,client_id
    )
  )
  or private.is_org_admin(organization_id)
);

create policy coach_client_notes_insert_v2
on public.coach_client_notes for insert
to authenticated
with check (
  coach_id=(select auth.uid())
  and private.actor_can_manage_client_in_org_v1(
    coach_id,organization_id,client_id
  )
);

create policy coach_client_notes_update_v2
on public.coach_client_notes for update
to authenticated
using (
  (
    coach_id=(select auth.uid())
    and private.actor_can_manage_client_in_org_v1(
      coach_id,organization_id,client_id
    )
  )
  or private.is_org_admin(organization_id)
)
with check (
  private.actor_can_manage_client_in_org_v1(
    coach_id,organization_id,client_id
  )
);

create policy coach_client_notes_delete_v2
on public.coach_client_notes for delete
to authenticated
using (
  (
    coach_id=(select auth.uid())
    and private.actor_can_manage_client_in_org_v1(
      coach_id,organization_id,client_id
    )
  )
  or private.is_org_admin(organization_id)
);

revoke truncate,trigger,references
on table public.coach_clients
from public,anon,authenticated;
revoke truncate,trigger,references
on table public.client_invites
from public,anon,authenticated;
revoke truncate,trigger,references
on table public.coach_client_notes
from public,anon,authenticated;

comment on column public.coach_clients.organization_id is
  'F1.M1.S5 G1A tenant scope for the compatibility Coach/Client shadow. Canonical authorization remains client_coach_assignments.';
comment on function private.can_manage_client(uuid) is
  'F1.M1.S5 safe legacy wrapper. Resolves exactly one Client Organization; ambiguous multi-tenant calls fail instead of authorizing globally.';
