-- ARCH-1.0 · F1.M1.S5 Wave F1 — Competitive data tenant scope
-- Adds explicit Organization ownership to CV Rank / Seasons / Challenges.
-- Legacy PK/UNIQUE identities remain intact until Wave F2 rewires engine contracts.

alter table public.client_competitive_rank_v61 add column if not exists organization_id uuid;
alter table public.client_rank_history add column if not exists organization_id uuid;
alter table public.cv_rank_rating_ledger_v61 add column if not exists organization_id uuid;
alter table public.cv_rank_weekly_snapshots_v61 add column if not exists organization_id uuid;
alter table public.cv_rank_pause_periods_v61 add column if not exists organization_id uuid;
alter table public.cv_rank_transitions_v61 add column if not exists organization_id uuid;
alter table public.cv_rank_transition_receipts_v66 add column if not exists organization_id uuid;
alter table public.cv_rank_tutorial_ack_v61 add column if not exists organization_id uuid;
alter table public.cv_trophies_v61 add column if not exists organization_id uuid;
alter table public.cv_seasons_v61 add column if not exists organization_id uuid;
alter table public.cv_season_weekly_points_v61 add column if not exists organization_id uuid;
alter table public.cv_challenges_v61 add column if not exists organization_id uuid;
alter table public.cv_challenge_entries_v61 add column if not exists organization_id uuid;
alter table public.cv_challenge_winners_v61 add column if not exists organization_id uuid;

-- Existing client-scoped competitive records resolve from canonical Client membership.
update public.client_competitive_rank_v61 t
set organization_id=private.resolve_legacy_client_organization_v1(t.client_id,null)
where t.organization_id is null;

update public.client_rank_history t
set organization_id=private.resolve_legacy_client_organization_v1(t.client_id,null)
where t.organization_id is null;

update public.cv_rank_rating_ledger_v61 t
set organization_id=private.resolve_legacy_client_organization_v1(t.client_id,null)
where t.organization_id is null;

update public.cv_rank_weekly_snapshots_v61 t
set organization_id=private.resolve_legacy_client_organization_v1(t.client_id,null)
where t.organization_id is null;

update public.cv_rank_pause_periods_v61 t
set organization_id=private.resolve_legacy_client_organization_v1(t.client_id,null)
where t.organization_id is null;

update public.cv_rank_transitions_v61 t
set organization_id=private.resolve_legacy_client_organization_v1(t.client_id,null)
where t.organization_id is null;

update public.cv_rank_tutorial_ack_v61 t
set organization_id=private.resolve_legacy_client_organization_v1(t.client_id,null)
where t.organization_id is null;

update public.cv_trophies_v61 t
set organization_id=private.resolve_legacy_client_organization_v1(t.client_id,null)
where t.organization_id is null;

-- Parent competitive objects derive from their professional creator.
update public.cv_seasons_v61 t
set organization_id=private.resolve_legacy_professional_organization_v1(t.created_by,null)
where t.organization_id is null
  and t.created_by is not null;

update public.cv_challenges_v61 t
set organization_id=private.resolve_legacy_professional_organization_v1(t.created_by,null)
where t.organization_id is null
  and t.created_by is not null;

-- Children inherit the exact parent tenant.
update public.cv_season_weekly_points_v61 p
set organization_id=s.organization_id
from public.cv_seasons_v61 s
where s.id=p.season_id
  and p.organization_id is null;

update public.cv_challenge_entries_v61 e
set organization_id=c.organization_id
from public.cv_challenges_v61 c
where c.id=e.challenge_id
  and e.organization_id is null;

update public.cv_challenge_winners_v61 w
set organization_id=c.organization_id
from public.cv_challenges_v61 c
where c.id=w.challenge_id
  and w.organization_id is null;

update public.cv_rank_transition_receipts_v66 r
set organization_id=t.organization_id
from public.cv_rank_transitions_v61 t
where t.id=r.transition_id
  and r.organization_id is null;

do $$
begin
  if exists(select 1 from public.client_competitive_rank_v61 where organization_id is null)
     or exists(select 1 from public.client_rank_history where organization_id is null)
     or exists(select 1 from public.cv_rank_rating_ledger_v61 where organization_id is null)
     or exists(select 1 from public.cv_rank_weekly_snapshots_v61 where organization_id is null)
     or exists(select 1 from public.cv_rank_pause_periods_v61 where organization_id is null)
     or exists(select 1 from public.cv_rank_transitions_v61 where organization_id is null)
     or exists(select 1 from public.cv_rank_transition_receipts_v66 where organization_id is null)
     or exists(select 1 from public.cv_rank_tutorial_ack_v61 where organization_id is null)
     or exists(select 1 from public.cv_trophies_v61 where organization_id is null)
     or exists(select 1 from public.cv_seasons_v61 where organization_id is null)
     or exists(select 1 from public.cv_season_weekly_points_v61 where organization_id is null)
     or exists(select 1 from public.cv_challenges_v61 where organization_id is null)
     or exists(select 1 from public.cv_challenge_entries_v61 where organization_id is null)
     or exists(select 1 from public.cv_challenge_winners_v61 where organization_id is null) then
    raise exception 'F1.M1.S5 F1 competitive backfill left unscoped rows';
  end if;
end $$;

alter table public.client_competitive_rank_v61 alter column organization_id set not null;
alter table public.client_rank_history alter column organization_id set not null;
alter table public.cv_rank_rating_ledger_v61 alter column organization_id set not null;
alter table public.cv_rank_weekly_snapshots_v61 alter column organization_id set not null;
alter table public.cv_rank_pause_periods_v61 alter column organization_id set not null;
alter table public.cv_rank_transitions_v61 alter column organization_id set not null;
alter table public.cv_rank_transition_receipts_v66 alter column organization_id set not null;
alter table public.cv_rank_tutorial_ack_v61 alter column organization_id set not null;
alter table public.cv_trophies_v61 alter column organization_id set not null;
alter table public.cv_seasons_v61 alter column organization_id set not null;
alter table public.cv_season_weekly_points_v61 alter column organization_id set not null;
alter table public.cv_challenges_v61 alter column organization_id set not null;
alter table public.cv_challenge_entries_v61 alter column organization_id set not null;
alter table public.cv_challenge_winners_v61 alter column organization_id set not null;

-- Parent composite identities for physical same-tenant child FKs.
create unique index if not exists ux_cv_seasons_v61_org_id
  on public.cv_seasons_v61(organization_id,id);
create unique index if not exists ux_cv_challenges_v61_org_id
  on public.cv_challenges_v61(organization_id,id);
create unique index if not exists ux_cv_rank_transitions_v61_org_id_client
  on public.cv_rank_transitions_v61(organization_id,id,client_id);

-- Canonical Organization / Client boundaries.
do $$
declare
  t text;
begin
  foreach t in array array[
    'client_competitive_rank_v61',
    'client_rank_history',
    'cv_rank_rating_ledger_v61',
    'cv_rank_weekly_snapshots_v61',
    'cv_rank_pause_periods_v61',
    'cv_rank_transitions_v61',
    'cv_rank_tutorial_ack_v61',
    'cv_trophies_v61'
  ]
  loop
    if not exists(
      select 1 from pg_constraint
      where connamespace='public'::regnamespace
        and conname=t||'_organization_id_fkey'
    ) then
      execute format(
        'alter table public.%I add constraint %I foreign key (organization_id) references public.organizations(id) on delete restrict',
        t,t||'_organization_id_fkey'
      );
    end if;

    if not exists(
      select 1 from pg_constraint
      where connamespace='public'::regnamespace
        and conname=t||'_client_same_org'
    ) then
      execute format(
        'alter table public.%I add constraint %I foreign key (organization_id,client_id) references public.clients(organization_id,user_id) on delete cascade',
        t,t||'_client_same_org'
      );
    end if;
  end loop;
end $$;

do $$
begin
  if not exists(select 1 from pg_constraint where conname='cv_seasons_v61_organization_id_fkey') then
    alter table public.cv_seasons_v61
      add constraint cv_seasons_v61_organization_id_fkey
      foreign key (organization_id) references public.organizations(id) on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='cv_seasons_v61_created_by_member_same_org') then
    alter table public.cv_seasons_v61
      add constraint cv_seasons_v61_created_by_member_same_org
      foreign key (organization_id,created_by)
      references public.organization_members(organization_id,user_id)
      on delete set null;
  end if;

  if not exists(select 1 from pg_constraint where conname='cv_challenges_v61_organization_id_fkey') then
    alter table public.cv_challenges_v61
      add constraint cv_challenges_v61_organization_id_fkey
      foreign key (organization_id) references public.organizations(id) on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='cv_challenges_v61_created_by_member_same_org') then
    alter table public.cv_challenges_v61
      add constraint cv_challenges_v61_created_by_member_same_org
      foreign key (organization_id,created_by)
      references public.organization_members(organization_id,user_id)
      on delete set null;
  end if;

  if not exists(select 1 from pg_constraint where conname='cv_season_weekly_points_v61_organization_id_fkey') then
    alter table public.cv_season_weekly_points_v61
      add constraint cv_season_weekly_points_v61_organization_id_fkey
      foreign key (organization_id) references public.organizations(id) on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='cv_season_weekly_points_v61_client_same_org') then
    alter table public.cv_season_weekly_points_v61
      add constraint cv_season_weekly_points_v61_client_same_org
      foreign key (organization_id,client_id)
      references public.clients(organization_id,user_id) on delete cascade;
  end if;
  if not exists(select 1 from pg_constraint where conname='cv_season_weekly_points_v61_season_same_org') then
    alter table public.cv_season_weekly_points_v61
      add constraint cv_season_weekly_points_v61_season_same_org
      foreign key (organization_id,season_id)
      references public.cv_seasons_v61(organization_id,id) on delete cascade;
  end if;

  if not exists(select 1 from pg_constraint where conname='cv_challenge_entries_v61_organization_id_fkey') then
    alter table public.cv_challenge_entries_v61
      add constraint cv_challenge_entries_v61_organization_id_fkey
      foreign key (organization_id) references public.organizations(id) on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='cv_challenge_entries_v61_client_same_org') then
    alter table public.cv_challenge_entries_v61
      add constraint cv_challenge_entries_v61_client_same_org
      foreign key (organization_id,client_id)
      references public.clients(organization_id,user_id) on delete cascade;
  end if;
  if not exists(select 1 from pg_constraint where conname='cv_challenge_entries_v61_challenge_same_org') then
    alter table public.cv_challenge_entries_v61
      add constraint cv_challenge_entries_v61_challenge_same_org
      foreign key (organization_id,challenge_id)
      references public.cv_challenges_v61(organization_id,id) on delete cascade;
  end if;

  if not exists(select 1 from pg_constraint where conname='cv_challenge_winners_v61_organization_id_fkey') then
    alter table public.cv_challenge_winners_v61
      add constraint cv_challenge_winners_v61_organization_id_fkey
      foreign key (organization_id) references public.organizations(id) on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='cv_challenge_winners_v61_client_same_org') then
    alter table public.cv_challenge_winners_v61
      add constraint cv_challenge_winners_v61_client_same_org
      foreign key (organization_id,client_id)
      references public.clients(organization_id,user_id) on delete cascade;
  end if;
  if not exists(select 1 from pg_constraint where conname='cv_challenge_winners_v61_challenge_same_org') then
    alter table public.cv_challenge_winners_v61
      add constraint cv_challenge_winners_v61_challenge_same_org
      foreign key (organization_id,challenge_id)
      references public.cv_challenges_v61(organization_id,id) on delete cascade;
  end if;
  if not exists(select 1 from pg_constraint where conname='cv_challenge_winners_v61_approved_by_member_same_org') then
    alter table public.cv_challenge_winners_v61
      add constraint cv_challenge_winners_v61_approved_by_member_same_org
      foreign key (organization_id,approved_by)
      references public.organization_members(organization_id,user_id)
      on delete set null;
  end if;

  if not exists(select 1 from pg_constraint where conname='cv_rank_transition_receipts_v66_organization_id_fkey') then
    alter table public.cv_rank_transition_receipts_v66
      add constraint cv_rank_transition_receipts_v66_organization_id_fkey
      foreign key (organization_id) references public.organizations(id) on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='cv_rank_transition_receipts_v66_client_same_org') then
    alter table public.cv_rank_transition_receipts_v66
      add constraint cv_rank_transition_receipts_v66_client_same_org
      foreign key (organization_id,client_id)
      references public.clients(organization_id,user_id) on delete cascade;
  end if;
  if not exists(select 1 from pg_constraint where conname='cv_rank_transition_receipts_v66_transition_same_org_client') then
    alter table public.cv_rank_transition_receipts_v66
      add constraint cv_rank_transition_receipts_v66_transition_same_org_client
      foreign key (organization_id,transition_id,client_id)
      references public.cv_rank_transitions_v61(organization_id,id,client_id)
      on delete cascade;
  end if;

  if not exists(select 1 from pg_constraint where conname='cv_rank_pause_periods_v61_created_by_member_same_org') then
    alter table public.cv_rank_pause_periods_v61
      add constraint cv_rank_pause_periods_v61_created_by_member_same_org
      foreign key (organization_id,created_by)
      references public.organization_members(organization_id,user_id)
      on delete set null;
  end if;
end $$;

-- Parent objects need a compatibility resolver because they do not carry client_id.
create or replace function private.guard_competitive_parent_tenant_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_org uuid;
begin
  if new.organization_id is null then
    if new.created_by is null then
      raise exception 'competitive parent requires organization_id or created_by';
    end if;
    v_org:=private.resolve_legacy_professional_organization_v1(new.created_by,null);
    new.organization_id:=v_org;
  end if;

  if new.created_by is not null
     and not exists(
       select 1
       from public.organization_members om
       where om.organization_id=new.organization_id
         and om.user_id=new.created_by
         and om.status='active'::public.organization_member_status
         and om.role in (
           'owner'::public.organization_member_role,
           'org_admin'::public.organization_member_role,
           'coach'::public.organization_member_role
         )
     ) then
    raise exception 'competitive parent creator is not active in organization';
  end if;

  if tg_op='UPDATE'
     and new.organization_id is distinct from old.organization_id then
    raise exception 'competitive parent organization is immutable';
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_cv_seasons_v61_tenant_v1 on public.cv_seasons_v61;
create trigger trg_cv_seasons_v61_tenant_v1
before insert or update on public.cv_seasons_v61
for each row execute function private.guard_competitive_parent_tenant_v1();

drop trigger if exists trg_cv_challenges_v61_tenant_v1 on public.cv_challenges_v61;
create trigger trg_cv_challenges_v61_tenant_v1
before insert or update on public.cv_challenges_v61
for each row execute function private.guard_competitive_parent_tenant_v1();

create or replace function private.guard_challenge_child_tenant_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_org uuid;
begin
  select c.organization_id into v_org
  from public.cv_challenges_v61 c
  where c.id=new.challenge_id;

  if v_org is null then
    raise exception 'challenge child requires a valid challenge';
  end if;

  if new.organization_id is null then
    new.organization_id:=v_org;
  elsif new.organization_id<>v_org then
    raise exception 'challenge child cannot cross organization boundary';
  end if;

  if not exists(
    select 1 from public.clients cl
    where cl.organization_id=new.organization_id
      and cl.user_id=new.client_id
      and cl.status<>'archived'::public.client_status
  ) then
    raise exception 'challenge client is not active in organization';
  end if;

  if tg_op='UPDATE'
     and (
       new.organization_id is distinct from old.organization_id
       or new.client_id is distinct from old.client_id
       or new.challenge_id is distinct from old.challenge_id
     ) then
    raise exception 'challenge child tenant identity is immutable';
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_cv_challenge_entries_v61_tenant_v1 on public.cv_challenge_entries_v61;
create trigger trg_cv_challenge_entries_v61_tenant_v1
before insert or update on public.cv_challenge_entries_v61
for each row execute function private.guard_challenge_child_tenant_v1();

drop trigger if exists trg_cv_challenge_winners_v61_tenant_v1 on public.cv_challenge_winners_v61;
create trigger trg_cv_challenge_winners_v61_tenant_v1
before insert or update on public.cv_challenge_winners_v61
for each row execute function private.guard_challenge_child_tenant_v1();

create or replace function private.guard_season_points_tenant_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_org uuid;
begin
  select s.organization_id into v_org
  from public.cv_seasons_v61 s
  where s.id=new.season_id;

  if v_org is null then
    raise exception 'season points require a valid season';
  end if;

  if new.organization_id is null then
    new.organization_id:=v_org;
  elsif new.organization_id<>v_org then
    raise exception 'season points cannot cross organization boundary';
  end if;

  if not exists(
    select 1 from public.clients cl
    where cl.organization_id=new.organization_id
      and cl.user_id=new.client_id
      and cl.status<>'archived'::public.client_status
  ) then
    raise exception 'season points client is not active in organization';
  end if;

  if tg_op='UPDATE'
     and (
       new.organization_id is distinct from old.organization_id
       or new.client_id is distinct from old.client_id
       or new.season_id is distinct from old.season_id
     ) then
    raise exception 'season points tenant identity is immutable';
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_cv_season_weekly_points_v61_tenant_v1 on public.cv_season_weekly_points_v61;
create trigger trg_cv_season_weekly_points_v61_tenant_v1
before insert or update on public.cv_season_weekly_points_v61
for each row execute function private.guard_season_points_tenant_v1();

create or replace function private.guard_rank_transition_receipt_tenant_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_org uuid;
  v_client uuid;
begin
  select t.organization_id,t.client_id into v_org,v_client
  from public.cv_rank_transitions_v61 t
  where t.id=new.transition_id;

  if v_org is null then
    raise exception 'rank transition receipt requires a valid transition';
  end if;
  if new.client_id<>v_client then
    raise exception 'rank transition receipt client must match transition client';
  end if;

  if new.organization_id is null then
    new.organization_id:=v_org;
  elsif new.organization_id<>v_org then
    raise exception 'rank transition receipt cannot cross organization boundary';
  end if;

  if tg_op='UPDATE'
     and (
       new.organization_id is distinct from old.organization_id
       or new.client_id is distinct from old.client_id
       or new.transition_id is distinct from old.transition_id
     ) then
    raise exception 'rank transition receipt tenant identity is immutable';
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_cv_rank_transition_receipts_v66_tenant_v1 on public.cv_rank_transition_receipts_v66;
create trigger trg_cv_rank_transition_receipts_v66_tenant_v1
before insert or update on public.cv_rank_transition_receipts_v66
for each row execute function private.guard_rank_transition_receipt_tenant_v1();

-- Direct client-scoped competitive tables can reuse the canonical S5 guard.
drop trigger if exists trg_client_competitive_rank_v61_tenant_v1 on public.client_competitive_rank_v61;
create trigger trg_client_competitive_rank_v61_tenant_v1
before insert or update on public.client_competitive_rank_v61
for each row execute function private.guard_legacy_client_scoped_row_v1();

drop trigger if exists trg_client_rank_history_tenant_v1 on public.client_rank_history;
create trigger trg_client_rank_history_tenant_v1
before insert or update on public.client_rank_history
for each row execute function private.guard_legacy_client_scoped_row_v1();

drop trigger if exists trg_cv_rank_rating_ledger_v61_tenant_v1 on public.cv_rank_rating_ledger_v61;
create trigger trg_cv_rank_rating_ledger_v61_tenant_v1
before insert or update on public.cv_rank_rating_ledger_v61
for each row execute function private.guard_legacy_client_scoped_row_v1();

drop trigger if exists trg_cv_rank_weekly_snapshots_v61_tenant_v1 on public.cv_rank_weekly_snapshots_v61;
create trigger trg_cv_rank_weekly_snapshots_v61_tenant_v1
before insert or update on public.cv_rank_weekly_snapshots_v61
for each row execute function private.guard_legacy_client_scoped_row_v1();

drop trigger if exists trg_cv_rank_pause_periods_v61_tenant_v1 on public.cv_rank_pause_periods_v61;
create trigger trg_cv_rank_pause_periods_v61_tenant_v1
before insert or update on public.cv_rank_pause_periods_v61
for each row execute function private.guard_legacy_client_scoped_row_v1();

drop trigger if exists trg_cv_rank_transitions_v61_tenant_v1 on public.cv_rank_transitions_v61;
create trigger trg_cv_rank_transitions_v61_tenant_v1
before insert or update on public.cv_rank_transitions_v61
for each row execute function private.guard_legacy_client_scoped_row_v1();

drop trigger if exists trg_cv_rank_tutorial_ack_v61_tenant_v1 on public.cv_rank_tutorial_ack_v61;
create trigger trg_cv_rank_tutorial_ack_v61_tenant_v1
before insert or update on public.cv_rank_tutorial_ack_v61
for each row execute function private.guard_legacy_client_scoped_row_v1();

drop trigger if exists trg_cv_trophies_v61_tenant_v1 on public.cv_trophies_v61;
create trigger trg_cv_trophies_v61_tenant_v1
before insert or update on public.cv_trophies_v61
for each row execute function private.guard_legacy_client_scoped_row_v1();

-- Tenant-aware read policies.
drop policy if exists cv_rank_profile_read_v61 on public.client_competitive_rank_v61;
create policy cv_rank_profile_read_v61_org
on public.client_competitive_rank_v61 for select
to authenticated
using (private.can_view_client_in_org(organization_id,client_id));

drop policy if exists client_rank_history_select on public.client_rank_history;
create policy client_rank_history_select_org
on public.client_rank_history for select
to authenticated
using (private.can_view_client_in_org(organization_id,client_id));

drop policy if exists cv_rank_week_read_v61 on public.cv_rank_weekly_snapshots_v61;
create policy cv_rank_week_read_v61_org
on public.cv_rank_weekly_snapshots_v61 for select
to authenticated
using (private.can_view_client_in_org(organization_id,client_id));

drop policy if exists cv_rank_trophy_read_v61 on public.cv_trophies_v61;
create policy cv_rank_trophy_read_v61_org
on public.cv_trophies_v61 for select
to authenticated
using (private.can_view_client_in_org(organization_id,client_id));

drop policy if exists cv_rank_challenge_read_v61 on public.cv_challenges_v61;
create policy cv_rank_challenge_read_v61_org
on public.cv_challenges_v61 for select
to authenticated
using (
  private.is_org_member(organization_id)
  and status in ('active','closed')
);

drop policy if exists cv_rank_season_read_v61 on public.cv_seasons_v61;
create policy cv_rank_season_read_v61_org
on public.cv_seasons_v61 for select
to authenticated
using (
  private.is_org_member(organization_id)
  and status in ('active','closed')
);

-- Tenant-first indexes while compatibility identities remain intact.
create index if not exists ix_client_competitive_rank_v61_org_client
  on public.client_competitive_rank_v61(organization_id,client_id);
create index if not exists ix_client_rank_history_org_client
  on public.client_rank_history(organization_id,client_id,reached_at desc);
create index if not exists ix_cv_rank_rating_ledger_v61_org_client
  on public.cv_rank_rating_ledger_v61(organization_id,client_id,created_at desc);
create index if not exists ix_cv_rank_weekly_snapshots_v61_org_client
  on public.cv_rank_weekly_snapshots_v61(organization_id,client_id,week_start desc);
create index if not exists ix_cv_rank_pause_periods_v61_org_client
  on public.cv_rank_pause_periods_v61(organization_id,client_id,starts_on desc);
create index if not exists ix_cv_rank_transitions_v61_org_client
  on public.cv_rank_transitions_v61(organization_id,client_id,created_at desc);
create index if not exists ix_cv_rank_tutorial_ack_v61_org_client
  on public.cv_rank_tutorial_ack_v61(organization_id,client_id,completed_at desc);
create index if not exists ix_cv_trophies_v61_org_client
  on public.cv_trophies_v61(organization_id,client_id,earned_at desc);
create index if not exists ix_cv_seasons_v61_org_status
  on public.cv_seasons_v61(organization_id,status,starts_on desc);
create index if not exists ix_cv_challenges_v61_org_status
  on public.cv_challenges_v61(organization_id,status,starts_on desc);
create index if not exists ix_cv_season_weekly_points_v61_org_client
  on public.cv_season_weekly_points_v61(organization_id,client_id,week_start desc);
create index if not exists ix_cv_challenge_entries_v61_org_client
  on public.cv_challenge_entries_v61(organization_id,client_id,updated_at desc);
create index if not exists ix_cv_challenge_winners_v61_org_client
  on public.cv_challenge_winners_v61(organization_id,client_id,created_at desc);
create index if not exists ix_cv_rank_transition_receipts_v66_org_client
  on public.cv_rank_transition_receipts_v66(organization_id,client_id,seen_at desc);

-- Remove DDL-adjacent browser privileges from competitive tables.
revoke truncate,trigger,references on table public.client_competitive_rank_v61 from public,anon,authenticated;
revoke truncate,trigger,references on table public.client_rank_history from public,anon,authenticated;
revoke truncate,trigger,references on table public.cv_rank_rating_ledger_v61 from public,anon,authenticated;
revoke truncate,trigger,references on table public.cv_rank_weekly_snapshots_v61 from public,anon,authenticated;
revoke truncate,trigger,references on table public.cv_rank_pause_periods_v61 from public,anon,authenticated;
revoke truncate,trigger,references on table public.cv_rank_transitions_v61 from public,anon,authenticated;
revoke truncate,trigger,references on table public.cv_rank_transition_receipts_v66 from public,anon,authenticated;
revoke truncate,trigger,references on table public.cv_rank_tutorial_ack_v61 from public,anon,authenticated;
revoke truncate,trigger,references on table public.cv_trophies_v61 from public,anon,authenticated;
revoke truncate,trigger,references on table public.cv_seasons_v61 from public,anon,authenticated;
revoke truncate,trigger,references on table public.cv_season_weekly_points_v61 from public,anon,authenticated;
revoke truncate,trigger,references on table public.cv_challenges_v61 from public,anon,authenticated;
revoke truncate,trigger,references on table public.cv_challenge_entries_v61 from public,anon,authenticated;
revoke truncate,trigger,references on table public.cv_challenge_winners_v61 from public,anon,authenticated;

comment on column public.client_competitive_rank_v61.organization_id is
  'F1.M1.S5 F1 tenant boundary for competitive rank state. PK cutover deferred to F2.';
comment on column public.cv_seasons_v61.organization_id is
  'F1.M1.S5 F1 Organization owner of competitive season.';
comment on column public.cv_challenges_v61.organization_id is
  'F1.M1.S5 F1 Organization owner of competitive challenge.';
