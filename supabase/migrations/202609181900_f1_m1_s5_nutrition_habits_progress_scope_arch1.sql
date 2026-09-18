-- ARCH-1.0 · F1.M1.S5 Wave D1 — Nutrition / Habits / Progress tenant scope
-- Adds explicit Organization ownership and tenant-aware RLS while preserving
-- existing compatibility identities until later consumer/identity cutovers.

alter table public.nutrition_targets
  add column if not exists organization_id uuid;
alter table public.meal_logs
  add column if not exists organization_id uuid;
alter table public.measurements
  add column if not exists organization_id uuid;
alter table public.progress_photos
  add column if not exists organization_id uuid;
alter table public.client_habits
  add column if not exists organization_id uuid;
alter table public.habit_logs
  add column if not exists organization_id uuid;

-- Canonical client-scoped roots.
update public.nutrition_targets t
set organization_id=private.resolve_legacy_client_organization_v1(
  t.client_id,null
)
where t.organization_id is null;

update public.meal_logs t
set organization_id=private.resolve_legacy_client_organization_v1(
  t.client_id,null
)
where t.organization_id is null;

update public.measurements t
set organization_id=private.resolve_legacy_client_organization_v1(
  t.client_id,null
)
where t.organization_id is null;

update public.progress_photos t
set organization_id=private.resolve_legacy_client_organization_v1(
  t.client_id,null
)
where t.organization_id is null;

update public.client_habits t
set organization_id=private.resolve_legacy_client_organization_v1(
  t.client_id,null
)
where t.organization_id is null;

-- Habit logs inherit the exact tenant from their canonical parent.
update public.habit_logs hl
set organization_id=ch.organization_id
from public.client_habits ch
where ch.id=hl.client_habit_id
  and ch.client_id=hl.client_id
  and hl.organization_id is null;

do $$
begin
  if exists(select 1 from public.nutrition_targets where organization_id is null)
     or exists(select 1 from public.meal_logs where organization_id is null)
     or exists(select 1 from public.measurements where organization_id is null)
     or exists(select 1 from public.progress_photos where organization_id is null)
     or exists(select 1 from public.client_habits where organization_id is null)
     or exists(select 1 from public.habit_logs where organization_id is null) then
    raise exception 'F1.M1.S5 D1 backfill left unscoped rows';
  end if;

  if exists(
    select 1
    from public.habit_logs hl
    join public.client_habits ch on ch.id=hl.client_habit_id
    where hl.organization_id<>ch.organization_id
       or hl.client_id<>ch.client_id
  ) then
    raise exception 'F1.M1.S5 D1 habit log parent mismatch';
  end if;

  if exists(
    select 1
    from public.progress_photos pp
    join public.measurements m on m.id=pp.measurement_id
    where pp.measurement_id is not null
      and (
        pp.organization_id<>m.organization_id
        or pp.client_id<>m.client_id
      )
  ) then
    raise exception 'F1.M1.S5 D1 progress photo measurement mismatch';
  end if;
end $$;

alter table public.nutrition_targets alter column organization_id set not null;
alter table public.meal_logs alter column organization_id set not null;
alter table public.measurements alter column organization_id set not null;
alter table public.progress_photos alter column organization_id set not null;
alter table public.client_habits alter column organization_id set not null;
alter table public.habit_logs alter column organization_id set not null;

-- Legacy uniqueness must be tenant-scoped. A single platform user can
-- legitimately be an active client in more than one Organization.
drop index if exists public.uq_client_habits_active;
create unique index uq_client_habits_active_org
  on public.client_habits(organization_id,client_id,habit_id)
  where active=true;

drop index if exists public.nutrition_targets_one_active_per_client;
create unique index nutrition_targets_one_active_per_org_client
  on public.nutrition_targets(organization_id,client_id)
  where active=true;

-- Supporting composite identities for same-tenant child relations.
create unique index if not exists ux_client_habits_org_id_client
  on public.client_habits(organization_id,id,client_id);

create unique index if not exists ux_measurements_org_id_client
  on public.measurements(organization_id,id,client_id);

-- Same-tenant Organization + Client boundaries.
do $$
begin
  if not exists(select 1 from pg_constraint where conname='nutrition_targets_organization_id_fkey') then
    alter table public.nutrition_targets
      add constraint nutrition_targets_organization_id_fkey
      foreign key (organization_id)
      references public.organizations(id)
      on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='nutrition_targets_client_same_org') then
    alter table public.nutrition_targets
      add constraint nutrition_targets_client_same_org
      foreign key (organization_id,client_id)
      references public.clients(organization_id,user_id)
      on delete cascade;
  end if;
  if not exists(select 1 from pg_constraint where conname='nutrition_targets_created_by_member_same_org') then
    alter table public.nutrition_targets
      add constraint nutrition_targets_created_by_member_same_org
      foreign key (organization_id,created_by)
      references public.organization_members(organization_id,user_id)
      on delete restrict;
  end if;

  if not exists(select 1 from pg_constraint where conname='meal_logs_organization_id_fkey') then
    alter table public.meal_logs
      add constraint meal_logs_organization_id_fkey
      foreign key (organization_id)
      references public.organizations(id)
      on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='meal_logs_client_same_org') then
    alter table public.meal_logs
      add constraint meal_logs_client_same_org
      foreign key (organization_id,client_id)
      references public.clients(organization_id,user_id)
      on delete cascade;
  end if;

  if not exists(select 1 from pg_constraint where conname='measurements_organization_id_fkey') then
    alter table public.measurements
      add constraint measurements_organization_id_fkey
      foreign key (organization_id)
      references public.organizations(id)
      on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='measurements_client_same_org') then
    alter table public.measurements
      add constraint measurements_client_same_org
      foreign key (organization_id,client_id)
      references public.clients(organization_id,user_id)
      on delete cascade;
  end if;

  if not exists(select 1 from pg_constraint where conname='progress_photos_organization_id_fkey') then
    alter table public.progress_photos
      add constraint progress_photos_organization_id_fkey
      foreign key (organization_id)
      references public.organizations(id)
      on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='progress_photos_client_same_org') then
    alter table public.progress_photos
      add constraint progress_photos_client_same_org
      foreign key (organization_id,client_id)
      references public.clients(organization_id,user_id)
      on delete cascade;
  end if;

  if not exists(select 1 from pg_constraint where conname='client_habits_organization_id_fkey') then
    alter table public.client_habits
      add constraint client_habits_organization_id_fkey
      foreign key (organization_id)
      references public.organizations(id)
      on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='client_habits_client_same_org') then
    alter table public.client_habits
      add constraint client_habits_client_same_org
      foreign key (organization_id,client_id)
      references public.clients(organization_id,user_id)
      on delete cascade;
  end if;

  if not exists(select 1 from pg_constraint where conname='habit_logs_organization_id_fkey') then
    alter table public.habit_logs
      add constraint habit_logs_organization_id_fkey
      foreign key (organization_id)
      references public.organizations(id)
      on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='habit_logs_client_same_org') then
    alter table public.habit_logs
      add constraint habit_logs_client_same_org
      foreign key (organization_id,client_id)
      references public.clients(organization_id,user_id)
      on delete cascade;
  end if;
  if not exists(select 1 from pg_constraint where conname='habit_logs_client_habit_same_org_client') then
    alter table public.habit_logs
      add constraint habit_logs_client_habit_same_org_client
      foreign key (organization_id,client_habit_id,client_id)
      references public.client_habits(organization_id,id,client_id)
      on delete cascade;
  end if;
end $$;

-- Reuse the generic immutable client-scoped guard for direct client roots.
drop trigger if exists trg_nutrition_targets_tenant_v1 on public.nutrition_targets;
create trigger trg_nutrition_targets_tenant_v1
before insert or update on public.nutrition_targets
for each row execute function private.guard_legacy_client_scoped_row_v1();

drop trigger if exists trg_meal_logs_tenant_v1 on public.meal_logs;
create trigger trg_meal_logs_tenant_v1
before insert or update on public.meal_logs
for each row execute function private.guard_legacy_client_scoped_row_v1();

drop trigger if exists trg_measurements_tenant_v1 on public.measurements;
create trigger trg_measurements_tenant_v1
before insert or update on public.measurements
for each row execute function private.guard_legacy_client_scoped_row_v1();

drop trigger if exists trg_client_habits_tenant_v1 on public.client_habits;
create trigger trg_client_habits_tenant_v1
before insert or update on public.client_habits
for each row execute function private.guard_legacy_client_scoped_row_v1();

-- Habit logs are anchored to the parent client_habit.
create or replace function private.guard_habit_log_tenant_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_org uuid;
  v_client uuid;
begin
  select ch.organization_id,ch.client_id
    into v_org,v_client
  from public.client_habits ch
  where ch.id=new.client_habit_id;

  if v_org is null then
    raise exception 'habit log parent client_habit not found';
  end if;
  if new.client_id<>v_client then
    raise exception 'habit log client must match parent client_habit client';
  end if;

  if new.organization_id is null then
    new.organization_id:=v_org;
  elsif new.organization_id<>v_org then
    raise exception 'habit log cannot cross client_habit organization boundary';
  end if;

  if tg_op='UPDATE' and (
    new.organization_id is distinct from old.organization_id
    or new.client_id is distinct from old.client_id
    or new.client_habit_id is distinct from old.client_habit_id
  ) then
    raise exception 'habit log tenant identity is immutable';
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_habit_logs_tenant_v1 on public.habit_logs;
create trigger trg_habit_logs_tenant_v1
before insert or update on public.habit_logs
for each row execute function private.guard_habit_log_tenant_v1();

-- Progress photos inherit client tenant and, when present, measurement tenant.
create or replace function private.guard_progress_photo_tenant_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_org uuid;
  v_measure_client uuid;
begin
  new.organization_id:=private.resolve_legacy_client_organization_v1(
    new.client_id,new.organization_id
  );

  if new.measurement_id is not null then
    select m.organization_id,m.client_id
      into v_org,v_measure_client
    from public.measurements m
    where m.id=new.measurement_id;

    if v_org is null then
      raise exception 'progress photo measurement not found';
    end if;
    if v_org<>new.organization_id
       or v_measure_client<>new.client_id then
      raise exception 'progress photo measurement crosses organization/client boundary';
    end if;
  end if;

  if tg_op='UPDATE' and (
    new.organization_id is distinct from old.organization_id
    or new.client_id is distinct from old.client_id
  ) then
    raise exception 'progress photo tenant identity is immutable';
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_progress_photos_tenant_v1 on public.progress_photos;
create trigger trg_progress_photos_tenant_v1
before insert or update on public.progress_photos
for each row execute function private.guard_progress_photo_tenant_v1();

create or replace function private.client_habit_belongs_to_in_org(
  target_organization uuid,
  target_client_habit uuid,
  target_client uuid
)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select coalesce(exists(
    select 1
    from public.client_habits ch
    where ch.organization_id=target_organization
      and ch.id=target_client_habit
      and ch.client_id=target_client
  ),false)
$function$;

create or replace function private.client_habit_belongs_to(
  target_client_habit uuid,
  target_client uuid
)
returns boolean
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_organization uuid;
begin
  v_organization:=private.resolve_legacy_client_organization_v1(
    target_client,null
  );
  return private.client_habit_belongs_to_in_org(
    v_organization,target_client_habit,target_client
  );
end;
$function$;

-- Tenant-aware RLS.
drop policy if exists nutrition_targets_delete on public.nutrition_targets;
drop policy if exists nutrition_targets_insert on public.nutrition_targets;
drop policy if exists nutrition_targets_select on public.nutrition_targets;
drop policy if exists nutrition_targets_update on public.nutrition_targets;

create policy nutrition_targets_delete_v2
on public.nutrition_targets for delete
to authenticated
using (private.can_manage_client_in_org(organization_id,client_id));

create policy nutrition_targets_insert_v2
on public.nutrition_targets for insert
to authenticated
with check (private.can_manage_client_in_org(organization_id,client_id));

create policy nutrition_targets_select_v2
on public.nutrition_targets for select
to authenticated
using (private.can_view_client_in_org(organization_id,client_id));

create policy nutrition_targets_update_v2
on public.nutrition_targets for update
to authenticated
using (private.can_manage_client_in_org(organization_id,client_id))
with check (private.can_manage_client_in_org(organization_id,client_id));

drop policy if exists meal_logs_delete on public.meal_logs;
drop policy if exists meal_logs_insert on public.meal_logs;
drop policy if exists meal_logs_select on public.meal_logs;
drop policy if exists meal_logs_update on public.meal_logs;

create policy meal_logs_delete_v2
on public.meal_logs for delete
to authenticated
using (
  (
    client_id=(select auth.uid())
    and private.is_org_member(organization_id)
  )
  or private.can_manage_client_in_org(organization_id,client_id)
);

create policy meal_logs_insert_v2
on public.meal_logs for insert
to authenticated
with check (
  (
    client_id=(select auth.uid())
    and private.is_org_member(organization_id)
  )
  or private.can_manage_client_in_org(organization_id,client_id)
);

create policy meal_logs_select_v2
on public.meal_logs for select
to authenticated
using (private.can_view_client_in_org(organization_id,client_id));

create policy meal_logs_update_v2
on public.meal_logs for update
to authenticated
using (
  (
    client_id=(select auth.uid())
    and private.is_org_member(organization_id)
  )
  or private.can_manage_client_in_org(organization_id,client_id)
)
with check (
  (
    client_id=(select auth.uid())
    and private.is_org_member(organization_id)
  )
  or private.can_manage_client_in_org(organization_id,client_id)
);

drop policy if exists measurements_insert on public.measurements;
drop policy if exists measurements_select on public.measurements;
drop policy if exists measurements_update on public.measurements;

create policy measurements_insert_v2
on public.measurements for insert
to authenticated
with check (
  (
    client_id=(select auth.uid())
    and source='manual'::public.log_source
    and private.is_org_member(organization_id)
  )
  or private.can_manage_client_in_org(organization_id,client_id)
);

create policy measurements_select_v2
on public.measurements for select
to authenticated
using (private.can_view_client_in_org(organization_id,client_id));

create policy measurements_update_v2
on public.measurements for update
to authenticated
using (
  (
    client_id=(select auth.uid())
    and private.is_org_member(organization_id)
  )
  or private.can_manage_client_in_org(organization_id,client_id)
)
with check (
  (
    client_id=(select auth.uid())
    and source='manual'::public.log_source
    and private.is_org_member(organization_id)
  )
  or private.can_manage_client_in_org(organization_id,client_id)
);

drop policy if exists client_habits_delete on public.client_habits;
drop policy if exists client_habits_insert on public.client_habits;
drop policy if exists client_habits_select on public.client_habits;
drop policy if exists client_habits_update on public.client_habits;

create policy client_habits_delete_v2
on public.client_habits for delete
to authenticated
using (private.can_manage_client_in_org(organization_id,client_id));

create policy client_habits_insert_v2
on public.client_habits for insert
to authenticated
with check (private.can_manage_client_in_org(organization_id,client_id));

create policy client_habits_select_v2
on public.client_habits for select
to authenticated
using (private.can_view_client_in_org(organization_id,client_id));

create policy client_habits_update_v2
on public.client_habits for update
to authenticated
using (private.can_manage_client_in_org(organization_id,client_id))
with check (private.can_manage_client_in_org(organization_id,client_id));

drop policy if exists habit_logs_delete on public.habit_logs;
drop policy if exists habit_logs_insert on public.habit_logs;
drop policy if exists habit_logs_select on public.habit_logs;
drop policy if exists habit_logs_update on public.habit_logs;

create policy habit_logs_delete_v2
on public.habit_logs for delete
to authenticated
using (
  (
    client_id=(select auth.uid())
    and private.is_org_member(organization_id)
  )
  or private.can_manage_client_in_org(organization_id,client_id)
);

create policy habit_logs_insert_v2
on public.habit_logs for insert
to authenticated
with check (
  private.client_habit_belongs_to_in_org(
    organization_id,client_habit_id,client_id
  )
  and (
    (
      client_id=(select auth.uid())
      and source='manual'::public.log_source
      and private.is_org_member(organization_id)
    )
    or private.can_manage_client_in_org(organization_id,client_id)
  )
);

create policy habit_logs_select_v2
on public.habit_logs for select
to authenticated
using (private.can_view_client_in_org(organization_id,client_id));

create policy habit_logs_update_v2
on public.habit_logs for update
to authenticated
using (
  (
    client_id=(select auth.uid())
    and private.is_org_member(organization_id)
  )
  or private.can_manage_client_in_org(organization_id,client_id)
)
with check (
  private.client_habit_belongs_to_in_org(
    organization_id,client_habit_id,client_id
  )
  and (
    (
      client_id=(select auth.uid())
      and source='manual'::public.log_source
      and private.is_org_member(organization_id)
    )
    or private.can_manage_client_in_org(organization_id,client_id)
  )
);

drop policy if exists progress_photos_delete on public.progress_photos;
drop policy if exists progress_photos_insert on public.progress_photos;
drop policy if exists progress_photos_select on public.progress_photos;
drop policy if exists progress_photos_update on public.progress_photos;

create policy progress_photos_delete_v2
on public.progress_photos for delete
to authenticated
using (
  (
    client_id=(select auth.uid())
    and private.is_org_member(organization_id)
  )
  or private.is_org_admin(organization_id)
);

create policy progress_photos_insert_v2
on public.progress_photos for insert
to authenticated
with check (
  (
    client_id=(select auth.uid())
    and private.is_org_member(organization_id)
  )
  or private.can_manage_client_in_org(organization_id,client_id)
);

create policy progress_photos_select_v2
on public.progress_photos for select
to authenticated
using (
  (
    client_id=(select auth.uid())
    and private.is_org_member(organization_id)
  )
  or (
    visible_to_coach=true
    and private.can_manage_client_in_org(organization_id,client_id)
  )
  or private.is_org_admin(organization_id)
);

create policy progress_photos_update_v2
on public.progress_photos for update
to authenticated
using (
  (
    client_id=(select auth.uid())
    and private.is_org_member(organization_id)
  )
  or private.is_org_admin(organization_id)
)
with check (
  (
    client_id=(select auth.uid())
    and private.is_org_member(organization_id)
  )
  or private.is_org_admin(organization_id)
);

revoke truncate,trigger,references
on table public.nutrition_targets
from public,anon,authenticated;
revoke truncate,trigger,references
on table public.meal_logs
from public,anon,authenticated;
revoke truncate,trigger,references
on table public.measurements
from public,anon,authenticated;
revoke truncate,trigger,references
on table public.progress_photos
from public,anon,authenticated;
revoke truncate,trigger,references
on table public.client_habits
from public,anon,authenticated;
revoke truncate,trigger,references
on table public.habit_logs
from public,anon,authenticated;

create index if not exists idx_nutrition_targets_org_client_active
  on public.nutrition_targets(organization_id,client_id,active,start_date desc);

create index if not exists idx_meal_logs_org_client_logged
  on public.meal_logs(organization_id,client_id,logged_at desc);

create index if not exists idx_measurements_org_client_measured
  on public.measurements(organization_id,client_id,measured_at desc);

create index if not exists idx_progress_photos_org_client_taken
  on public.progress_photos(organization_id,client_id,taken_at desc);

create index if not exists idx_client_habits_org_client_active
  on public.client_habits(organization_id,client_id,active,start_date);

create index if not exists idx_habit_logs_org_client_date
  on public.habit_logs(organization_id,client_id,log_date desc);

comment on column public.nutrition_targets.organization_id is
  'F1.M1.S5 tenant boundary for nutrition targets.';
comment on column public.client_habits.organization_id is
  'F1.M1.S5 tenant boundary for client habit assignments.';
comment on column public.measurements.organization_id is
  'F1.M1.S5 tenant boundary for physical progress measurements.';
