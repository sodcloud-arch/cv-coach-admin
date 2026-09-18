-- ARCH-1.0 · F1.M1.S3 Clients
-- Canonical tenant-scoped client identity independent from authentication/login.
-- Legacy client_profiles remains untouched; F1.M3 will own detailed 360° data.

do $$ begin
  create type public.client_status as enum ('lead','invited','active','paused','archived');
exception when duplicate_object then null;
end $$;

create table if not exists public.clients (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  user_id uuid references public.profiles(id) on delete set null,
  status public.client_status not null default 'lead',
  display_name text not null,
  contact_metadata jsonb not null default '{}'::jsonb,
  onboarding_state jsonb not null default '{}'::jsonb,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  constraint clients_display_name_not_blank check (length(btrim(display_name)) > 0),
  constraint clients_contact_metadata_object check (jsonb_typeof(contact_metadata) = 'object'),
  constraint clients_onboarding_state_object check (jsonb_typeof(onboarding_state) = 'object'),
  constraint clients_archive_consistency check (
    (status = 'archived' and archived_at is not null)
    or (status <> 'archived' and archived_at is null)
  )
);

create unique index if not exists idx_clients_org_user_unique
  on public.clients(organization_id,user_id)
  where user_id is not null;

create index if not exists idx_clients_org_status
  on public.clients(organization_id,status,created_at desc);
create index if not exists idx_clients_user
  on public.clients(user_id)
  where user_id is not null;
create index if not exists idx_clients_created_by
  on public.clients(created_by)
  where created_by is not null;

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
          or private.is_org_professional(c.organization_id)
          or (
            c.user_id=(select auth.uid())
            and private.is_org_member(c.organization_id)
          )
        )
    ),
    false
  )
$function$;

create or replace function private.guard_client_entity_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not exists(
    select 1 from public.organizations o
    where o.id=new.organization_id
      and o.status in ('trial'::public.organization_status,'active'::public.organization_status)
  ) then
    raise exception 'client requires an operational organization';
  end if;

  if tg_op='UPDATE' then
    if new.organization_id is distinct from old.organization_id then
      raise exception 'client organization is immutable';
    end if;
    if old.user_id is not null and new.user_id is distinct from old.user_id then
      raise exception 'linked client user is immutable through direct updates';
    end if;
    if old.status='archived'::public.client_status
       and new.status<>'archived'::public.client_status then
      raise exception 'archived client is terminal';
    end if;
  end if;

  if new.user_id is not null then
    if not exists(
      select 1 from public.profiles p
      where p.id=new.user_id and p.status='active'::public.profile_status
    ) then
      raise exception 'linked client user must be an active platform user';
    end if;
    if not exists(
      select 1 from public.organization_members om
      where om.organization_id=new.organization_id
        and om.user_id=new.user_id
        and om.status='active'::public.organization_member_status
    ) then
      raise exception 'linked client user requires active organization membership';
    end if;
  end if;

  new.display_name:=btrim(new.display_name);
  if new.status='archived'::public.client_status then
    new.archived_at:=coalesce(new.archived_at,now());
  else
    new.archived_at:=null;
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_clients_guard_v1 on public.clients;
create trigger trg_clients_guard_v1
before insert or update on public.clients
for each row execute function private.guard_client_entity_v1();

drop trigger if exists trg_clients_updated_at_v1 on public.clients;
create trigger trg_clients_updated_at_v1
before update on public.clients
for each row execute function private.set_updated_at();

alter table public.clients enable row level security;

drop policy if exists clients_select_v1 on public.clients;
create policy clients_select_v1
on public.clients for select
to authenticated
using (private.can_view_client_entity(id));

create or replace function public.create_client(
  p_organization_id uuid,
  p_display_name text,
  p_user_id uuid default null,
  p_status public.client_status default 'lead'::public.client_status,
  p_contact_metadata jsonb default '{}'::jsonb,
  p_onboarding_state jsonb default '{}'::jsonb,
  p_created_by uuid default null
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_client_id uuid;
  v_display_name text:=btrim(coalesce(p_display_name,''));
  v_member public.organization_members%rowtype;
begin
  if auth.role()<>'service_role' then
    raise exception 'client creation is backend-only';
  end if;
  if v_display_name='' then
    raise exception 'display_name is required';
  end if;
  if jsonb_typeof(coalesce(p_contact_metadata,'{}'::jsonb))<>'object'
     or jsonb_typeof(coalesce(p_onboarding_state,'{}'::jsonb))<>'object' then
    raise exception 'contact_metadata and onboarding_state must be JSON objects';
  end if;
  if not exists(
    select 1 from public.organizations o
    where o.id=p_organization_id
      and o.status in ('trial'::public.organization_status,'active'::public.organization_status)
  ) then
    raise exception 'organization is not operational';
  end if;

  if p_user_id is not null then
    if not exists(select 1 from public.profiles p where p.id=p_user_id and p.status='active'::public.profile_status) then
      raise exception 'linked client user must be an active platform user';
    end if;
    select * into v_member
    from public.organization_members om
    where om.organization_id=p_organization_id and om.user_id=p_user_id;
    if not found then
      insert into public.organization_members(organization_id,user_id,role,status,joined_at)
      values(p_organization_id,p_user_id,'client'::public.organization_member_role,'active'::public.organization_member_status,now());
    elsif v_member.status<>'active'::public.organization_member_status then
      raise exception 'linked client organization membership is not active';
    end if;
  end if;

  insert into public.clients(
    organization_id,user_id,status,display_name,contact_metadata,onboarding_state,created_by
  ) values(
    p_organization_id,p_user_id,p_status,v_display_name,
    coalesce(p_contact_metadata,'{}'::jsonb),coalesce(p_onboarding_state,'{}'::jsonb),p_created_by
  ) returning id into v_client_id;

  return v_client_id;
end;
$function$;

create or replace function public.link_client_user(
  p_client_id uuid,
  p_user_id uuid
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_client public.clients%rowtype;
  v_member public.organization_members%rowtype;
begin
  if auth.role()<>'service_role' then
    raise exception 'client account linking is backend-only';
  end if;

  select * into v_client from public.clients where id=p_client_id for update;
  if not found then raise exception 'client not found'; end if;
  if v_client.status='archived'::public.client_status then raise exception 'archived client cannot be linked'; end if;
  if v_client.user_id is not null then
    if v_client.user_id=p_user_id then return v_client.id; end if;
    raise exception 'client is already linked to another user';
  end if;
  if not exists(select 1 from public.profiles p where p.id=p_user_id and p.status='active'::public.profile_status) then
    raise exception 'linked client user must be an active platform user';
  end if;
  if exists(select 1 from public.clients c where c.organization_id=v_client.organization_id and c.user_id=p_user_id and c.id<>v_client.id) then
    raise exception 'user is already linked to another client in this organization';
  end if;

  select * into v_member from public.organization_members om
  where om.organization_id=v_client.organization_id and om.user_id=p_user_id;
  if not found then
    insert into public.organization_members(organization_id,user_id,role,status,joined_at)
    values(v_client.organization_id,p_user_id,'client'::public.organization_member_role,'active'::public.organization_member_status,now());
  elsif v_member.status<>'active'::public.organization_member_status then
    raise exception 'linked client organization membership is not active';
  end if;

  update public.clients
  set user_id=p_user_id,
      status=case when status in ('lead'::public.client_status,'invited'::public.client_status)
                  then 'active'::public.client_status else status end
  where id=p_client_id;

  return p_client_id;
end;
$function$;

revoke all on table public.clients from public,anon;
grant select on table public.clients to authenticated;
grant all on table public.clients to service_role;

revoke all on function public.create_client(uuid,text,uuid,public.client_status,jsonb,jsonb,uuid) from public;
grant execute on function public.create_client(uuid,text,uuid,public.client_status,jsonb,jsonb,uuid) to service_role;
revoke all on function public.link_client_user(uuid,uuid) from public;
grant execute on function public.link_client_user(uuid,uuid) to service_role;

comment on table public.clients is 'ARCH-1.0 canonical tenant-scoped client identity, independent from login. F1.M1.S3.';
comment on function public.link_client_user(uuid,uuid) is 'Links an accountless tenant client to a global User without merging cross-tenant data.';
