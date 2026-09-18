-- ARCH-1.0 · F1.M1.S5 Wave E1 — CV12 Core tenant scope
-- Adds explicit Organization ownership to the core CV12 state/ledger layer.
-- Legacy PK/UNIQUE identities remain temporarily intact until E2 rewires the engine.

alter table public.client_cv_state
  add column if not exists organization_id uuid;
alter table public.xp_ledger
  add column if not exists organization_id uuid;
alter table public.credit_ledger
  add column if not exists organization_id uuid;
alter table public.client_missions
  add column if not exists organization_id uuid;
alter table public.client_achievements
  add column if not exists organization_id uuid;
alter table public.cv_score_snapshots
  add column if not exists organization_id uuid;
alter table public.reward_redemptions
  add column if not exists organization_id uuid;

-- Deterministic backfill while every current client resolves to one active Organization.
update public.client_cv_state t
set organization_id=private.resolve_legacy_client_organization_v1(t.client_id,null)
where t.organization_id is null;

update public.xp_ledger t
set organization_id=private.resolve_legacy_client_organization_v1(t.client_id,null)
where t.organization_id is null;

update public.credit_ledger t
set organization_id=private.resolve_legacy_client_organization_v1(t.client_id,null)
where t.organization_id is null;

update public.client_missions t
set organization_id=private.resolve_legacy_client_organization_v1(t.client_id,null)
where t.organization_id is null;

update public.client_achievements t
set organization_id=private.resolve_legacy_client_organization_v1(t.client_id,null)
where t.organization_id is null;

update public.cv_score_snapshots t
set organization_id=private.resolve_legacy_client_organization_v1(t.client_id,null)
where t.organization_id is null;

update public.reward_redemptions t
set organization_id=private.resolve_legacy_client_organization_v1(t.client_id,null)
where t.organization_id is null;

do $$
begin
  if exists(select 1 from public.client_cv_state where organization_id is null)
     or exists(select 1 from public.xp_ledger where organization_id is null)
     or exists(select 1 from public.credit_ledger where organization_id is null)
     or exists(select 1 from public.client_missions where organization_id is null)
     or exists(select 1 from public.client_achievements where organization_id is null)
     or exists(select 1 from public.cv_score_snapshots where organization_id is null)
     or exists(select 1 from public.reward_redemptions where organization_id is null) then
    raise exception 'F1.M1.S5 E1 CV12 backfill left unscoped rows';
  end if;
end $$;

alter table public.client_cv_state alter column organization_id set not null;
alter table public.xp_ledger alter column organization_id set not null;
alter table public.credit_ledger alter column organization_id set not null;
alter table public.client_missions alter column organization_id set not null;
alter table public.client_achievements alter column organization_id set not null;
alter table public.cv_score_snapshots alter column organization_id set not null;
alter table public.reward_redemptions alter column organization_id set not null;

-- Same-tenant boundaries.
do $$
begin
  if not exists(select 1 from pg_constraint where conname='client_cv_state_organization_id_fkey') then
    alter table public.client_cv_state
      add constraint client_cv_state_organization_id_fkey
      foreign key (organization_id) references public.organizations(id) on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='client_cv_state_client_same_org') then
    alter table public.client_cv_state
      add constraint client_cv_state_client_same_org
      foreign key (organization_id,client_id)
      references public.clients(organization_id,user_id) on delete cascade;
  end if;

  if not exists(select 1 from pg_constraint where conname='xp_ledger_organization_id_fkey') then
    alter table public.xp_ledger
      add constraint xp_ledger_organization_id_fkey
      foreign key (organization_id) references public.organizations(id) on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='xp_ledger_client_same_org') then
    alter table public.xp_ledger
      add constraint xp_ledger_client_same_org
      foreign key (organization_id,client_id)
      references public.clients(organization_id,user_id) on delete cascade;
  end if;

  if not exists(select 1 from pg_constraint where conname='credit_ledger_organization_id_fkey') then
    alter table public.credit_ledger
      add constraint credit_ledger_organization_id_fkey
      foreign key (organization_id) references public.organizations(id) on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='credit_ledger_client_same_org') then
    alter table public.credit_ledger
      add constraint credit_ledger_client_same_org
      foreign key (organization_id,client_id)
      references public.clients(organization_id,user_id) on delete cascade;
  end if;

  if not exists(select 1 from pg_constraint where conname='client_missions_organization_id_fkey') then
    alter table public.client_missions
      add constraint client_missions_organization_id_fkey
      foreign key (organization_id) references public.organizations(id) on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='client_missions_client_same_org') then
    alter table public.client_missions
      add constraint client_missions_client_same_org
      foreign key (organization_id,client_id)
      references public.clients(organization_id,user_id) on delete cascade;
  end if;
  if not exists(select 1 from pg_constraint where conname='client_missions_assigned_by_member_same_org') then
    alter table public.client_missions
      add constraint client_missions_assigned_by_member_same_org
      foreign key (organization_id,assigned_by)
      references public.organization_members(organization_id,user_id)
      on delete set null;
  end if;

  if not exists(select 1 from pg_constraint where conname='client_achievements_organization_id_fkey') then
    alter table public.client_achievements
      add constraint client_achievements_organization_id_fkey
      foreign key (organization_id) references public.organizations(id) on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='client_achievements_client_same_org') then
    alter table public.client_achievements
      add constraint client_achievements_client_same_org
      foreign key (organization_id,client_id)
      references public.clients(organization_id,user_id) on delete cascade;
  end if;

  if not exists(select 1 from pg_constraint where conname='cv_score_snapshots_organization_id_fkey') then
    alter table public.cv_score_snapshots
      add constraint cv_score_snapshots_organization_id_fkey
      foreign key (organization_id) references public.organizations(id) on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='cv_score_snapshots_client_same_org') then
    alter table public.cv_score_snapshots
      add constraint cv_score_snapshots_client_same_org
      foreign key (organization_id,client_id)
      references public.clients(organization_id,user_id) on delete cascade;
  end if;

  if not exists(select 1 from pg_constraint where conname='reward_redemptions_organization_id_fkey') then
    alter table public.reward_redemptions
      add constraint reward_redemptions_organization_id_fkey
      foreign key (organization_id) references public.organizations(id) on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='reward_redemptions_client_same_org') then
    alter table public.reward_redemptions
      add constraint reward_redemptions_client_same_org
      foreign key (organization_id,client_id)
      references public.clients(organization_id,user_id) on delete cascade;
  end if;
end $$;

-- Generic immutable tenant guard keeps existing legacy writers working while E2 is pending.
drop trigger if exists trg_client_cv_state_tenant_v1 on public.client_cv_state;
create trigger trg_client_cv_state_tenant_v1
before insert or update on public.client_cv_state
for each row execute function private.guard_legacy_client_scoped_row_v1();

drop trigger if exists trg_xp_ledger_tenant_v1 on public.xp_ledger;
create trigger trg_xp_ledger_tenant_v1
before insert or update on public.xp_ledger
for each row execute function private.guard_legacy_client_scoped_row_v1();

drop trigger if exists trg_credit_ledger_tenant_v1 on public.credit_ledger;
create trigger trg_credit_ledger_tenant_v1
before insert or update on public.credit_ledger
for each row execute function private.guard_legacy_client_scoped_row_v1();

drop trigger if exists trg_client_missions_tenant_v1 on public.client_missions;
create trigger trg_client_missions_tenant_v1
before insert or update on public.client_missions
for each row execute function private.guard_legacy_client_scoped_row_v1();

drop trigger if exists trg_client_achievements_tenant_v1 on public.client_achievements;
create trigger trg_client_achievements_tenant_v1
before insert or update on public.client_achievements
for each row execute function private.guard_legacy_client_scoped_row_v1();

drop trigger if exists trg_cv_score_snapshots_tenant_v1 on public.cv_score_snapshots;
create trigger trg_cv_score_snapshots_tenant_v1
before insert or update on public.cv_score_snapshots
for each row execute function private.guard_legacy_client_scoped_row_v1();

drop trigger if exists trg_reward_redemptions_tenant_v1 on public.reward_redemptions;
create trigger trg_reward_redemptions_tenant_v1
before insert or update on public.reward_redemptions
for each row execute function private.guard_legacy_client_scoped_row_v1();

-- Tenant-aware RLS.
drop policy if exists client_cv_state_select on public.client_cv_state;
create policy client_cv_state_select_v2
on public.client_cv_state for select
to authenticated
using (private.can_view_client_in_org(organization_id,client_id));

drop policy if exists xp_ledger_select on public.xp_ledger;
create policy xp_ledger_select_v2
on public.xp_ledger for select
to authenticated
using (private.can_view_client_in_org(organization_id,client_id));

drop policy if exists credit_ledger_select on public.credit_ledger;
create policy credit_ledger_select_v2
on public.credit_ledger for select
to authenticated
using (private.can_view_client_in_org(organization_id,client_id));

drop policy if exists client_missions_delete on public.client_missions;
drop policy if exists client_missions_insert on public.client_missions;
drop policy if exists client_missions_select on public.client_missions;
drop policy if exists client_missions_update on public.client_missions;

create policy client_missions_delete_v2
on public.client_missions for delete
to authenticated
using (private.can_manage_client_in_org(organization_id,client_id));

create policy client_missions_insert_v2
on public.client_missions for insert
to authenticated
with check (private.can_manage_client_in_org(organization_id,client_id));

create policy client_missions_select_v2
on public.client_missions for select
to authenticated
using (private.can_view_client_in_org(organization_id,client_id));

create policy client_missions_update_v2
on public.client_missions for update
to authenticated
using (private.can_manage_client_in_org(organization_id,client_id))
with check (private.can_manage_client_in_org(organization_id,client_id));

drop policy if exists client_achievements_select on public.client_achievements;
create policy client_achievements_select_v2
on public.client_achievements for select
to authenticated
using (private.can_view_client_in_org(organization_id,client_id));

drop policy if exists cv_score_select on public.cv_score_snapshots;
create policy cv_score_select_v2
on public.cv_score_snapshots for select
to authenticated
using (private.can_view_client_in_org(organization_id,client_id));

drop policy if exists reward_redemptions_select on public.reward_redemptions;
drop policy if exists reward_redemptions_update_coach on public.reward_redemptions;

create policy reward_redemptions_select_v2
on public.reward_redemptions for select
to authenticated
using (private.can_view_client_in_org(organization_id,client_id));

create policy reward_redemptions_update_coach_v2
on public.reward_redemptions for update
to authenticated
using (private.can_manage_client_in_org(organization_id,client_id))
with check (private.can_manage_client_in_org(organization_id,client_id));

-- Tenant-first access paths. Global compatibility identities remain until E2.
create index if not exists ix_client_cv_state_org_client
  on public.client_cv_state(organization_id,client_id,current_level);

create index if not exists ix_xp_ledger_org_client_date
  on public.xp_ledger(organization_id,client_id,created_at desc);

create index if not exists ix_credit_ledger_org_client_date
  on public.credit_ledger(organization_id,client_id,created_at desc);

create index if not exists ix_client_missions_org_client_status
  on public.client_missions(organization_id,client_id,status,expires_at);

create index if not exists ix_client_achievements_org_client
  on public.client_achievements(organization_id,client_id,unlocked_at desc);

create index if not exists ix_cv_score_org_client_asof
  on public.cv_score_snapshots(
    organization_id,client_id,as_of_date desc,calculated_at desc
  );

create index if not exists ix_reward_redemptions_org_client_status
  on public.reward_redemptions(
    organization_id,client_id,status,requested_at desc
  );

revoke truncate,trigger,references on table public.client_cv_state from public,anon,authenticated;
revoke truncate,trigger,references on table public.xp_ledger from public,anon,authenticated;
revoke truncate,trigger,references on table public.credit_ledger from public,anon,authenticated;
revoke truncate,trigger,references on table public.client_missions from public,anon,authenticated;
revoke truncate,trigger,references on table public.client_achievements from public,anon,authenticated;
revoke truncate,trigger,references on table public.cv_score_snapshots from public,anon,authenticated;
revoke truncate,trigger,references on table public.reward_redemptions from public,anon,authenticated;

comment on column public.client_cv_state.organization_id is
  'F1.M1.S5 E1 tenant boundary for CV12 state. PK cutover deferred to E2.';
comment on column public.xp_ledger.organization_id is
  'F1.M1.S5 E1 tenant boundary for XP ledger. Idempotency cutover deferred to E2.';
comment on column public.credit_ledger.organization_id is
  'F1.M1.S5 E1 tenant boundary for credit ledger. Idempotency cutover deferred to E2.';
