-- ARCH-1.0 · F1.M1.S5 Wave C3A — client profile scope
-- Adds explicit Organization ownership to profile/onboarding/preferences records
-- while intentionally preserving legacy global PK/UNIQUE contracts until C3B.

create or replace function private.resolve_legacy_professional_organization_v1(
  target_actor uuid,
  target_client_user uuid default null
)
returns uuid
language plpgsql
stable security definer
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
    join public.organizations o
      on o.id=om.organization_id
    join public.clients c
      on c.organization_id=om.organization_id
     and c.user_id=target_client_user
     and c.status<>'archived'::public.client_status
    where om.user_id=target_actor
      and om.status='active'::public.organization_member_status
      and om.role in (
        'owner'::public.organization_member_role,
        'org_admin'::public.organization_member_role,
        'coach'::public.organization_member_role
      )
      and o.status in (
        'trial'::public.organization_status,
        'active'::public.organization_status
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
  join public.organizations o
    on o.id=om.organization_id
  where om.user_id=target_actor
    and om.status='active'::public.organization_member_status
    and om.role in (
      'owner'::public.organization_member_role,
      'org_admin'::public.organization_member_role,
      'coach'::public.organization_member_role
    )
    and o.status in (
      'trial'::public.organization_status,
      'active'::public.organization_status
    );

  if coalesce(cardinality(v_orgs),0)=0 then
    raise exception 'actor has no active professional organization';
  elsif cardinality(v_orgs)>1 then
    raise exception 'actor belongs to multiple organizations; organization_id is required';
  end if;

  return v_orgs[1];
end;
$function$;

-- ---------------------------------------------------------------------------
-- 1) Explicit tenant columns + deterministic backfill
-- ---------------------------------------------------------------------------

alter table public.client_profiles
  add column if not exists organization_id uuid;
alter table public.client_training_constraints
  add column if not exists organization_id uuid;
alter table public.client_training_preferences
  add column if not exists organization_id uuid;
alter table public.client_training_schedule_preferences
  add column if not exists organization_id uuid;
alter table public.onboarding_responses
  add column if not exists organization_id uuid;

update public.client_profiles t
set organization_id=private.resolve_legacy_client_organization_v1(
  t.client_id,null
)
where t.organization_id is null;

update public.client_training_constraints t
set organization_id=private.resolve_legacy_client_organization_v1(
  t.client_id,null
)
where t.organization_id is null;

update public.client_training_preferences t
set organization_id=private.resolve_legacy_client_organization_v1(
  t.client_id,null
)
where t.organization_id is null;

update public.client_training_schedule_preferences t
set organization_id=private.resolve_legacy_client_organization_v1(
  t.client_id,null
)
where t.organization_id is null;

update public.onboarding_responses t
set organization_id=private.resolve_legacy_client_organization_v1(
  t.client_id,null
)
where t.organization_id is null;

do $$
begin
  if exists(
    select 1 from public.client_profiles where organization_id is null
  ) or exists(
    select 1 from public.client_training_constraints where organization_id is null
  ) or exists(
    select 1 from public.client_training_preferences where organization_id is null
  ) or exists(
    select 1 from public.client_training_schedule_preferences where organization_id is null
  ) or exists(
    select 1 from public.onboarding_responses where organization_id is null
  ) then
    raise exception 'F1.M1.S5 C3A tenant backfill left unscoped rows';
  end if;
end $$;

alter table public.client_profiles
  alter column organization_id set not null;
alter table public.client_training_constraints
  alter column organization_id set not null;
alter table public.client_training_preferences
  alter column organization_id set not null;
alter table public.client_training_schedule_preferences
  alter column organization_id set not null;
alter table public.onboarding_responses
  alter column organization_id set not null;

-- ---------------------------------------------------------------------------
-- 2) Physical tenant boundaries
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists(select 1 from pg_constraint where conname='client_profiles_organization_id_fkey') then
    alter table public.client_profiles
      add constraint client_profiles_organization_id_fkey
      foreign key (organization_id)
      references public.organizations(id)
      on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='client_profiles_client_same_org') then
    alter table public.client_profiles
      add constraint client_profiles_client_same_org
      foreign key (organization_id,client_id)
      references public.clients(organization_id,user_id)
      on delete cascade;
  end if;

  if not exists(select 1 from pg_constraint where conname='client_training_constraints_organization_id_fkey') then
    alter table public.client_training_constraints
      add constraint client_training_constraints_organization_id_fkey
      foreign key (organization_id)
      references public.organizations(id)
      on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='client_training_constraints_client_same_org') then
    alter table public.client_training_constraints
      add constraint client_training_constraints_client_same_org
      foreign key (organization_id,client_id)
      references public.clients(organization_id,user_id)
      on delete cascade;
  end if;

  if not exists(select 1 from pg_constraint where conname='client_training_preferences_organization_id_fkey') then
    alter table public.client_training_preferences
      add constraint client_training_preferences_organization_id_fkey
      foreign key (organization_id)
      references public.organizations(id)
      on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='client_training_preferences_client_same_org') then
    alter table public.client_training_preferences
      add constraint client_training_preferences_client_same_org
      foreign key (organization_id,client_id)
      references public.clients(organization_id,user_id)
      on delete cascade;
  end if;

  if not exists(select 1 from pg_constraint where conname='client_training_schedule_preferences_organization_id_fkey') then
    alter table public.client_training_schedule_preferences
      add constraint client_training_schedule_preferences_organization_id_fkey
      foreign key (organization_id)
      references public.organizations(id)
      on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='client_training_schedule_preferences_client_same_org') then
    alter table public.client_training_schedule_preferences
      add constraint client_training_schedule_preferences_client_same_org
      foreign key (organization_id,client_id)
      references public.clients(organization_id,user_id)
      on delete cascade;
  end if;

  if not exists(select 1 from pg_constraint where conname='onboarding_responses_organization_id_fkey') then
    alter table public.onboarding_responses
      add constraint onboarding_responses_organization_id_fkey
      foreign key (organization_id)
      references public.organizations(id)
      on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='onboarding_responses_client_same_org') then
    alter table public.onboarding_responses
      add constraint onboarding_responses_client_same_org
      foreign key (organization_id,client_id)
      references public.clients(organization_id,user_id)
      on delete cascade;
  end if;
end $$;

create index if not exists idx_client_profiles_org_client
  on public.client_profiles(organization_id,client_id);
create index if not exists idx_client_training_constraints_org_client
  on public.client_training_constraints(organization_id,client_id,active);
create index if not exists idx_client_training_preferences_org_client
  on public.client_training_preferences(organization_id,client_id);
create index if not exists idx_client_training_schedule_org_client
  on public.client_training_schedule_preferences(organization_id,client_id);
create index if not exists idx_onboarding_responses_org_client
  on public.onboarding_responses(organization_id,client_id,question_key);

-- ---------------------------------------------------------------------------
-- 3) Reuse the canonical S5 compatibility guard
-- ---------------------------------------------------------------------------

drop trigger if exists trg_client_profiles_tenant_v1
  on public.client_profiles;
create trigger trg_client_profiles_tenant_v1
before insert or update on public.client_profiles
for each row execute function private.guard_legacy_client_scoped_row_v1();

drop trigger if exists trg_client_training_constraints_tenant_v1
  on public.client_training_constraints;
create trigger trg_client_training_constraints_tenant_v1
before insert or update on public.client_training_constraints
for each row execute function private.guard_legacy_client_scoped_row_v1();

drop trigger if exists trg_client_training_preferences_tenant_v1
  on public.client_training_preferences;
create trigger trg_client_training_preferences_tenant_v1
before insert or update on public.client_training_preferences
for each row execute function private.guard_legacy_client_scoped_row_v1();

drop trigger if exists trg_client_training_schedule_tenant_v1
  on public.client_training_schedule_preferences;
create trigger trg_client_training_schedule_tenant_v1
before insert or update on public.client_training_schedule_preferences
for each row execute function private.guard_legacy_client_scoped_row_v1();

drop trigger if exists trg_onboarding_responses_tenant_v1
  on public.onboarding_responses;
create trigger trg_onboarding_responses_tenant_v1
before insert or update on public.onboarding_responses
for each row execute function private.guard_legacy_client_scoped_row_v1();

-- ---------------------------------------------------------------------------
-- 4) Tenant-aware RLS
-- ---------------------------------------------------------------------------

drop policy if exists client_profiles_insert_self on public.client_profiles;
drop policy if exists client_profiles_select on public.client_profiles;
drop policy if exists client_profiles_update_self on public.client_profiles;

create policy client_profiles_insert_self_v2
on public.client_profiles for insert
to authenticated
with check (
  client_id=(select auth.uid())
  and onboarding_status<>'approved'::public.onboarding_status
  and private.is_org_member(organization_id)
);

create policy client_profiles_select_v2
on public.client_profiles for select
to authenticated
using (
  private.can_view_client_in_org(organization_id,client_id)
);

create policy client_profiles_update_self_v2
on public.client_profiles for update
to authenticated
using (
  client_id=(select auth.uid())
  and onboarding_status<>'approved'::public.onboarding_status
  and private.is_org_member(organization_id)
)
with check (
  client_id=(select auth.uid())
  and onboarding_status<>'approved'::public.onboarding_status
  and private.is_org_member(organization_id)
);

drop policy if exists client_training_constraints_select
  on public.client_training_constraints;
create policy client_training_constraints_select_v2
on public.client_training_constraints for select
to authenticated
using (
  private.can_manage_client_in_org(organization_id,client_id)
);

drop policy if exists client_training_preferences_select
  on public.client_training_preferences;
create policy client_training_preferences_select_v2
on public.client_training_preferences for select
to authenticated
using (
  (
    client_id=(select auth.uid())
    and private.is_org_member(organization_id)
  )
  or private.can_manage_client_in_org(organization_id,client_id)
);

drop policy if exists client_training_schedule_preferences_select
  on public.client_training_schedule_preferences;
create policy client_training_schedule_preferences_select_v2
on public.client_training_schedule_preferences for select
to authenticated
using (
  (
    client_id=(select auth.uid())
    and private.is_org_member(organization_id)
  )
  or private.can_manage_client_in_org(organization_id,client_id)
);

drop policy if exists onboarding_delete_self on public.onboarding_responses;
drop policy if exists onboarding_insert_self on public.onboarding_responses;
drop policy if exists onboarding_select on public.onboarding_responses;
drop policy if exists onboarding_update_self on public.onboarding_responses;

create policy onboarding_delete_self_v2
on public.onboarding_responses for delete
to authenticated
using (
  client_id=(select auth.uid())
  and private.is_org_member(organization_id)
);

create policy onboarding_insert_self_v2
on public.onboarding_responses for insert
to authenticated
with check (
  client_id=(select auth.uid())
  and private.is_org_member(organization_id)
);

create policy onboarding_select_v2
on public.onboarding_responses for select
to authenticated
using (
  private.can_view_client_in_org(organization_id,client_id)
);

create policy onboarding_update_self_v2
on public.onboarding_responses for update
to authenticated
using (
  client_id=(select auth.uid())
  and private.is_org_member(organization_id)
)
with check (
  client_id=(select auth.uid())
  and private.is_org_member(organization_id)
);

revoke truncate,trigger,references
on table public.client_profiles
from public,anon,authenticated;
revoke truncate,trigger,references
on table public.client_training_constraints
from public,anon,authenticated;
revoke truncate,trigger,references
on table public.client_training_preferences
from public,anon,authenticated;
revoke truncate,trigger,references
on table public.client_training_schedule_preferences
from public,anon,authenticated;
revoke truncate,trigger,references
on table public.onboarding_responses
from public,anon,authenticated;

-- ---------------------------------------------------------------------------
-- 5) Canonicalize legacy provisioning before profile writes
-- ---------------------------------------------------------------------------

create or replace function public.provision_client_records_backend(
  p_actor_id uuid,
  p_client_id uuid,
  p_email text,
  p_first_name text,
  p_last_name text default null::text,
  p_phone text default null::text,
  p_created_user boolean default false,
  p_client_url text default 'https://cv-coach-roan.vercel.app'::text,
  p_record_invite boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','private'
as $function$
declare
  v_actor_role public.app_role;
  v_actor_status public.profile_status;
  v_existing_role public.app_role;
  v_email text:=lower(trim(coalesce(p_email,'')));
  v_first_name text:=trim(coalesce(p_first_name,''));
  v_last_name text:=nullif(trim(coalesce(p_last_name,'')),'');
  v_phone text:=nullif(trim(coalesce(p_phone,'')),'');
  v_organization uuid;
  v_member public.organization_members%rowtype;
  v_client_entity uuid;
  v_coach_entity uuid;
  v_assignment_role public.client_coach_assignment_role;
begin
  select role,status into v_actor_role,v_actor_status
  from public.profiles
  where id=p_actor_id;

  if not found
     or v_actor_status<>'active'::public.profile_status
     or v_actor_role not in (
       'admin'::public.app_role,
       'coach'::public.app_role
     ) then
    raise exception 'Forbidden' using errcode='42501';
  end if;

  if p_client_id is null or p_actor_id=p_client_id then
    return jsonb_build_object('ok',false,'code','invalid_client');
  end if;
  if v_email='' or v_first_name='' then
    return jsonb_build_object('ok',false,'code','invalid_input');
  end if;
  if p_client_url<>'https://cv-coach-roan.vercel.app' then
    return jsonb_build_object('ok',false,'code','invalid_client_url');
  end if;

  v_organization:=private.resolve_legacy_professional_organization_v1(
    p_actor_id,p_client_id
  );

  select role into v_existing_role
  from public.profiles
  where id=p_client_id;

  if found and v_existing_role<>'client'::public.app_role then
    return jsonb_build_object('ok',false,'code','internal_account');
  end if;

  insert into public.profiles(
    id,role,status,first_name,last_name,phone
  )
  values(
    p_client_id,'client','active',
    left(v_first_name,80),left(v_last_name,80),left(v_phone,40)
  )
  on conflict(id) do update set
    first_name=excluded.first_name,
    last_name=excluded.last_name,
    phone=excluded.phone,
    status='active',
    updated_at=now();

  select * into v_member
  from public.organization_members om
  where om.organization_id=v_organization
    and om.user_id=p_client_id
  for update;

  if not found then
    insert into public.organization_members(
      organization_id,user_id,role,status,joined_at
    )
    values(
      v_organization,p_client_id,
      'client'::public.organization_member_role,
      'active'::public.organization_member_status,
      now()
    );
  else
    if v_member.role<>'client'::public.organization_member_role then
      raise exception 'client user already has a non-client role in organization';
    end if;
    if v_member.status<>'active'::public.organization_member_status then
      raise exception 'client organization membership is not active';
    end if;
  end if;

  insert into public.clients(
    organization_id,user_id,status,display_name,
    contact_metadata,onboarding_state,created_by
  )
  values(
    v_organization,
    p_client_id,
    'active'::public.client_status,
    left(
      btrim(
        v_first_name||coalesce(' '||v_last_name,'')
      ),
      160
    ),
    jsonb_strip_nulls(jsonb_build_object(
      'email',v_email,
      'phone',v_phone,
      'source','provision_client_records_backend'
    )),
    jsonb_build_object('status','pending'),
    p_actor_id
  )
  on conflict(organization_id,user_id) do update set
    status='active'::public.client_status,
    display_name=excluded.display_name,
    contact_metadata=
      public.clients.contact_metadata||excluded.contact_metadata,
    updated_at=now()
  returning id into v_client_entity;

  insert into public.client_profiles(
    organization_id,client_id,onboarding_status,timezone
  )
  values(
    v_organization,p_client_id,
    'pending'::public.onboarding_status,
    'America/Santiago'
  )
  on conflict(client_id) do update set
    organization_id=excluded.organization_id;

  select cp.id into v_coach_entity
  from public.coach_profiles cp
  where cp.organization_id=v_organization
    and cp.user_id=p_actor_id
    and cp.status='active'::public.coach_profile_status
  limit 1;

  if v_coach_entity is not null
     and not exists(
       select 1
       from public.client_coach_assignments a
       where a.organization_id=v_organization
         and a.client_id=v_client_entity
         and a.coach_id=v_coach_entity
         and a.status='active'::public.client_coach_assignment_status
     ) then

    v_assignment_role:=case
      when exists(
        select 1
        from public.client_coach_assignments a
        where a.organization_id=v_organization
          and a.client_id=v_client_entity
          and a.assignment_role='primary'::public.client_coach_assignment_role
          and a.status='active'::public.client_coach_assignment_status
      )
      then 'secondary'::public.client_coach_assignment_role
      else 'primary'::public.client_coach_assignment_role
    end;

    insert into public.client_coach_assignments(
      organization_id,client_id,coach_id,assignment_role,
      status,assigned_at,assigned_by
    )
    values(
      v_organization,v_client_entity,v_coach_entity,v_assignment_role,
      'active'::public.client_coach_assignment_status,
      now(),p_actor_id
    );
  end if;

  -- Compatibility shadow for legacy callers that still read coach_clients.
  if not exists(
    select 1
    from public.coach_clients
    where coach_id=p_actor_id
      and client_id=p_client_id
      and status='active'::public.coach_client_status
  ) then
    insert into public.coach_clients(
      coach_id,client_id,status
    )
    values(
      p_actor_id,p_client_id,'active'::public.coach_client_status
    );
  end if;

  if p_record_invite then
    insert into public.client_invites(
      coach_id,client_id,email,status,metadata
    )
    values(
      p_actor_id,
      p_client_id,
      v_email,
      'generated',
      jsonb_build_object(
        'organization_id',v_organization,
        'created_user',coalesce(p_created_user,false),
        'client_url',p_client_url
      )
    );
  end if;

  return jsonb_build_object(
    'ok',true,
    'organization_id',v_organization,
    'client_id',p_client_id,
    'client_entity_id',v_client_entity,
    'invite_recorded',p_record_invite
  );
end;
$function$;

comment on function private.resolve_legacy_professional_organization_v1(uuid,uuid) is
  'F1.M1.S5 compatibility resolver. Returns exactly one active professional Organization and rejects ambiguous multi-tenant calls.';
comment on column public.client_profiles.organization_id is
  'F1.M1.S5 C3A tenant boundary. Global PK remains temporarily for legacy compatibility until C3B.';
comment on column public.onboarding_responses.organization_id is
  'F1.M1.S5 C3A tenant boundary. Composite uniqueness is deferred to C3B after all consumers are tenant-aware.';
