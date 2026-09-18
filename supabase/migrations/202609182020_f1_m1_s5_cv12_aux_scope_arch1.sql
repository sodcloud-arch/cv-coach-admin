-- ARCH-1.0 · F1.M1.S5 Wave E1B — CV12 auxiliary tenant scope
-- Scopes reward-processing idempotency staging and level history by Organization.
-- Legacy UNIQUE identities remain until E2A rewires their writers.

alter table private.cv12_reward_processing
  add column if not exists organization_id uuid;

alter table public.client_level_history
  add column if not exists organization_id uuid;

update private.cv12_reward_processing t
set organization_id=private.resolve_legacy_client_organization_v1(
  t.client_id,null
)
where t.organization_id is null;

update public.client_level_history t
set organization_id=private.resolve_legacy_client_organization_v1(
  t.client_id,null
)
where t.organization_id is null;

do $$
begin
  if exists(
    select 1 from private.cv12_reward_processing
    where organization_id is null
  ) or exists(
    select 1 from public.client_level_history
    where organization_id is null
  ) then
    raise exception 'F1.M1.S5 E1B backfill left unscoped rows';
  end if;
end $$;

alter table private.cv12_reward_processing
  alter column organization_id set not null;

alter table public.client_level_history
  alter column organization_id set not null;

do $$
begin
  if not exists(
    select 1 from pg_constraint
    where conname='cv12_reward_processing_organization_id_fkey'
      and connamespace='private'::regnamespace
  ) then
    alter table private.cv12_reward_processing
      add constraint cv12_reward_processing_organization_id_fkey
      foreign key (organization_id)
      references public.organizations(id)
      on delete restrict;
  end if;

  if not exists(
    select 1 from pg_constraint
    where conname='cv12_reward_processing_client_same_org'
      and connamespace='private'::regnamespace
  ) then
    alter table private.cv12_reward_processing
      add constraint cv12_reward_processing_client_same_org
      foreign key (organization_id,client_id)
      references public.clients(organization_id,user_id)
      on delete cascade;
  end if;

  if not exists(
    select 1 from pg_constraint
    where conname='client_level_history_organization_id_fkey'
      and connamespace='public'::regnamespace
  ) then
    alter table public.client_level_history
      add constraint client_level_history_organization_id_fkey
      foreign key (organization_id)
      references public.organizations(id)
      on delete restrict;
  end if;

  if not exists(
    select 1 from pg_constraint
    where conname='client_level_history_client_same_org'
      and connamespace='public'::regnamespace
  ) then
    alter table public.client_level_history
      add constraint client_level_history_client_same_org
      foreign key (organization_id,client_id)
      references public.clients(organization_id,user_id)
      on delete cascade;
  end if;
end $$;

drop trigger if exists trg_cv12_reward_processing_tenant_v1
  on private.cv12_reward_processing;

create trigger trg_cv12_reward_processing_tenant_v1
before insert or update on private.cv12_reward_processing
for each row execute function private.guard_legacy_client_scoped_row_v1();

drop trigger if exists trg_client_level_history_tenant_v1
  on public.client_level_history;

create trigger trg_client_level_history_tenant_v1
before insert or update on public.client_level_history
for each row execute function private.guard_legacy_client_scoped_row_v1();

drop policy if exists client_level_history_select
  on public.client_level_history;

create policy client_level_history_select_v2
on public.client_level_history for select
to authenticated
using (
  private.can_view_client_in_org(organization_id,client_id)
);

create index if not exists ix_cv12_reward_processing_org_client_event_date
  on private.cv12_reward_processing(
    organization_id,client_id,event_key,event_date desc
  );

create index if not exists ix_client_level_history_org_client_date
  on public.client_level_history(
    organization_id,client_id,reached_at desc
  );

revoke truncate,trigger,references
on table public.client_level_history
from public,anon,authenticated;

comment on column private.cv12_reward_processing.organization_id is
  'F1.M1.S5 E1B tenant boundary for CV12 reward idempotency staging. UNIQUE cutover deferred to E2A.';
comment on column public.client_level_history.organization_id is
  'F1.M1.S5 E1B tenant boundary for level history. UNIQUE cutover deferred to E2A.';
