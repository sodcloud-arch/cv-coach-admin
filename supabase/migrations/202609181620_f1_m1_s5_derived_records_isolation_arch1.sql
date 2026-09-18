-- ARCH-1.0 · F1.M1.S5 — derived records tenant isolation
-- Adds explicit Organization ownership to derived business records whose tenant
-- can be inherited deterministically from canonical Program / Session / Subscription roots.

alter table public.ai_program_generations
  add column if not exists organization_id uuid;
alter table public.adaptive_program_drafts
  add column if not exists organization_id uuid;
alter table public.subscription_billing_records
  add column if not exists organization_id uuid;
alter table public.training_adaptation_reviews
  add column if not exists organization_id uuid;
alter table public.weekly_program_reviews
  add column if not exists organization_id uuid;

-- Deterministic backfill.
update public.ai_program_generations g
set organization_id=p.organization_id
from public.programs p
where p.id=g.program_id
  and g.organization_id is null;

update public.adaptive_program_drafts d
set organization_id=p.organization_id
from public.programs p
where p.id=d.source_program_id
  and d.organization_id is null;

update public.subscription_billing_records b
set organization_id=s.organization_id
from public.client_subscriptions s
where s.id=b.subscription_id
  and b.organization_id is null;

update public.training_adaptation_reviews r
set organization_id=p.organization_id
from public.programs p
where p.id=r.program_id
  and r.organization_id is null;

update public.weekly_program_reviews r
set organization_id=p.organization_id
from public.programs p
where p.id=r.program_id
  and r.organization_id is null;

-- Validate existing rows before enforcing NOT NULL/FKs.
do $$
begin
  if exists(
    select 1
    from public.ai_program_generations g
    left join public.programs p on p.id=g.program_id
    where g.organization_id is null
       or p.id is null
       or g.organization_id<>p.organization_id
       or g.client_id<>p.client_id
       or not exists(
         select 1 from public.coach_profiles cp
         where cp.organization_id=g.organization_id
           and cp.user_id=g.coach_id
           and cp.status='active'::public.coach_profile_status
       )
  ) then
    raise exception 'F1.M1.S5: ai_program_generations tenant validation failed';
  end if;

  if exists(
    select 1
    from public.adaptive_program_drafts d
    left join public.programs source_p on source_p.id=d.source_program_id
    left join public.programs draft_p on draft_p.id=d.draft_program_id
    where d.organization_id is null
       or source_p.id is null
       or draft_p.id is null
       or d.organization_id<>source_p.organization_id
       or d.organization_id<>draft_p.organization_id
       or d.client_id<>source_p.client_id
       or d.client_id<>draft_p.client_id
  ) then
    raise exception 'F1.M1.S5: adaptive_program_drafts tenant validation failed';
  end if;

  if exists(
    select 1
    from public.subscription_billing_records b
    left join public.client_subscriptions s on s.id=b.subscription_id
    where b.organization_id is null
       or s.id is null
       or b.organization_id<>s.organization_id
       or b.client_id<>s.client_id
  ) then
    raise exception 'F1.M1.S5: subscription_billing_records tenant validation failed';
  end if;

  if exists(
    select 1
    from public.training_adaptation_reviews r
    left join public.programs p on p.id=r.program_id
    left join public.workout_sessions ws on ws.id=r.source_session_id
    where r.organization_id is null
       or p.id is null
       or ws.id is null
       or r.organization_id<>p.organization_id
       or r.organization_id<>ws.organization_id
       or r.client_id<>p.client_id
       or r.client_id<>ws.client_id
  ) then
    raise exception 'F1.M1.S5: training_adaptation_reviews tenant validation failed';
  end if;

  if exists(
    select 1
    from public.weekly_program_reviews r
    left join public.programs p on p.id=r.program_id
    left join public.weekly_checkins c on c.id=r.checkin_id
    where r.organization_id is null
       or p.id is null
       or c.id is null
       or r.organization_id<>p.organization_id
       or r.organization_id<>c.organization_id
       or r.client_id<>p.client_id
       or r.client_id<>c.client_id
       or not exists(
         select 1 from public.coach_profiles cp
         where cp.organization_id=r.organization_id
           and cp.user_id=r.coach_id
           and cp.status='active'::public.coach_profile_status
       )
  ) then
    raise exception 'F1.M1.S5: weekly_program_reviews tenant validation failed';
  end if;
end $$;

alter table public.ai_program_generations alter column organization_id set not null;
alter table public.adaptive_program_drafts alter column organization_id set not null;
alter table public.subscription_billing_records alter column organization_id set not null;
alter table public.training_adaptation_reviews alter column organization_id set not null;
alter table public.weekly_program_reviews alter column organization_id set not null;

-- Composite parent identities required for same-tenant FKs.
create unique index if not exists ux_client_subscriptions_org_id_client
  on public.client_subscriptions(organization_id,id,client_id);
create unique index if not exists ux_weekly_checkins_org_id_client
  on public.weekly_checkins(organization_id,id,client_id);
create unique index if not exists ux_training_adaptation_reviews_org_id_client
  on public.training_adaptation_reviews(organization_id,id,client_id);

create unique index if not exists ux_ai_program_generations_org_id
  on public.ai_program_generations(organization_id,id);
create unique index if not exists ux_adaptive_program_drafts_org_id
  on public.adaptive_program_drafts(organization_id,id);
create unique index if not exists ux_subscription_billing_records_org_id
  on public.subscription_billing_records(organization_id,id);
create unique index if not exists ux_weekly_program_reviews_org_id
  on public.weekly_program_reviews(organization_id,id);

-- Physical same-tenant constraints.
do $$
begin
  if not exists(select 1 from pg_constraint where conname='ai_program_generations_organization_id_fkey') then
    alter table public.ai_program_generations
      add constraint ai_program_generations_organization_id_fkey
      foreign key (organization_id) references public.organizations(id) on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='ai_program_generations_program_same_org_client') then
    alter table public.ai_program_generations
      add constraint ai_program_generations_program_same_org_client
      foreign key (organization_id,program_id,client_id)
      references public.programs(organization_id,id,client_id) on delete cascade;
  end if;
  if not exists(select 1 from pg_constraint where conname='ai_program_generations_coach_same_org') then
    alter table public.ai_program_generations
      add constraint ai_program_generations_coach_same_org
      foreign key (organization_id,coach_id)
      references public.coach_profiles(organization_id,user_id) on delete restrict;
  end if;

  if not exists(select 1 from pg_constraint where conname='adaptive_program_drafts_organization_id_fkey') then
    alter table public.adaptive_program_drafts
      add constraint adaptive_program_drafts_organization_id_fkey
      foreign key (organization_id) references public.organizations(id) on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='adaptive_program_drafts_source_program_same_org_client') then
    alter table public.adaptive_program_drafts
      add constraint adaptive_program_drafts_source_program_same_org_client
      foreign key (organization_id,source_program_id,client_id)
      references public.programs(organization_id,id,client_id) on delete cascade;
  end if;
  if not exists(select 1 from pg_constraint where conname='adaptive_program_drafts_draft_program_same_org_client') then
    alter table public.adaptive_program_drafts
      add constraint adaptive_program_drafts_draft_program_same_org_client
      foreign key (organization_id,draft_program_id,client_id)
      references public.programs(organization_id,id,client_id) on delete cascade;
  end if;
  if not exists(select 1 from pg_constraint where conname='adaptive_program_drafts_review_same_org_client') then
    alter table public.adaptive_program_drafts
      add constraint adaptive_program_drafts_review_same_org_client
      foreign key (organization_id,adaptation_review_id,client_id)
      references public.training_adaptation_reviews(organization_id,id,client_id) on delete set null;
  end if;

  if not exists(select 1 from pg_constraint where conname='subscription_billing_records_organization_id_fkey') then
    alter table public.subscription_billing_records
      add constraint subscription_billing_records_organization_id_fkey
      foreign key (organization_id) references public.organizations(id) on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='subscription_billing_records_subscription_same_org_client') then
    alter table public.subscription_billing_records
      add constraint subscription_billing_records_subscription_same_org_client
      foreign key (organization_id,subscription_id,client_id)
      references public.client_subscriptions(organization_id,id,client_id) on delete cascade;
  end if;

  if not exists(select 1 from pg_constraint where conname='training_adaptation_reviews_organization_id_fkey') then
    alter table public.training_adaptation_reviews
      add constraint training_adaptation_reviews_organization_id_fkey
      foreign key (organization_id) references public.organizations(id) on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='training_adaptation_reviews_program_same_org_client') then
    alter table public.training_adaptation_reviews
      add constraint training_adaptation_reviews_program_same_org_client
      foreign key (organization_id,program_id,client_id)
      references public.programs(organization_id,id,client_id) on delete cascade;
  end if;
  if not exists(select 1 from pg_constraint where conname='training_adaptation_reviews_session_same_org_client') then
    alter table public.training_adaptation_reviews
      add constraint training_adaptation_reviews_session_same_org_client
      foreign key (organization_id,source_session_id,client_id)
      references public.workout_sessions(organization_id,id,client_id) on delete cascade;
  end if;

  if not exists(select 1 from pg_constraint where conname='weekly_program_reviews_organization_id_fkey') then
    alter table public.weekly_program_reviews
      add constraint weekly_program_reviews_organization_id_fkey
      foreign key (organization_id) references public.organizations(id) on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='weekly_program_reviews_program_same_org_client') then
    alter table public.weekly_program_reviews
      add constraint weekly_program_reviews_program_same_org_client
      foreign key (organization_id,program_id,client_id)
      references public.programs(organization_id,id,client_id) on delete cascade;
  end if;
  if not exists(select 1 from pg_constraint where conname='weekly_program_reviews_checkin_same_org_client') then
    alter table public.weekly_program_reviews
      add constraint weekly_program_reviews_checkin_same_org_client
      foreign key (organization_id,checkin_id,client_id)
      references public.weekly_checkins(organization_id,id,client_id) on delete cascade;
  end if;
  if not exists(select 1 from pg_constraint where conname='weekly_program_reviews_coach_same_org') then
    alter table public.weekly_program_reviews
      add constraint weekly_program_reviews_coach_same_org
      foreign key (organization_id,coach_id)
      references public.coach_profiles(organization_id,user_id) on delete restrict;
  end if;
end $$;

-- Compatibility guards derive tenant from the canonical parent.
create or replace function private.guard_ai_program_generation_tenant_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_org uuid;
  v_client uuid;
begin
  select p.organization_id,p.client_id into v_org,v_client
  from public.programs p where p.id=new.program_id;

  if v_org is null then raise exception 'AI generation requires a valid Program'; end if;
  if new.client_id<>v_client then raise exception 'AI generation client must match Program client'; end if;
  if not exists(
    select 1 from public.coach_profiles cp
    where cp.organization_id=v_org
      and cp.user_id=new.coach_id
      and cp.status='active'::public.coach_profile_status
  ) then
    raise exception 'AI generation coach must be active in Program organization';
  end if;

  if new.organization_id is null then new.organization_id:=v_org;
  elsif new.organization_id<>v_org then raise exception 'AI generation cannot cross organization boundary';
  end if;

  if tg_op='UPDATE' and new.organization_id is distinct from old.organization_id then
    raise exception 'AI generation organization is immutable';
  end if;
  return new;
end;
$function$;

create or replace function private.guard_training_adaptation_review_tenant_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_program_org uuid;
  v_program_client uuid;
  v_session_org uuid;
  v_session_client uuid;
begin
  select p.organization_id,p.client_id into v_program_org,v_program_client
  from public.programs p where p.id=new.program_id;
  select ws.organization_id,ws.client_id into v_session_org,v_session_client
  from public.workout_sessions ws where ws.id=new.source_session_id;

  if v_program_org is null or v_session_org is null then
    raise exception 'training adaptation review requires valid Program and Session';
  end if;
  if v_program_org<>v_session_org
     or new.client_id<>v_program_client
     or new.client_id<>v_session_client then
    raise exception 'training adaptation review cannot cross organization/client boundary';
  end if;

  if new.organization_id is null then new.organization_id:=v_program_org;
  elsif new.organization_id<>v_program_org then
    raise exception 'training adaptation review cannot cross organization boundary';
  end if;

  if tg_op='UPDATE' and new.organization_id is distinct from old.organization_id then
    raise exception 'training adaptation review organization is immutable';
  end if;
  return new;
end;
$function$;

create or replace function private.guard_adaptive_program_draft_tenant_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_source_org uuid;
  v_source_client uuid;
  v_draft_org uuid;
  v_draft_client uuid;
  v_review_org uuid;
  v_review_client uuid;
begin
  select p.organization_id,p.client_id into v_source_org,v_source_client
  from public.programs p where p.id=new.source_program_id;
  select p.organization_id,p.client_id into v_draft_org,v_draft_client
  from public.programs p where p.id=new.draft_program_id;

  if v_source_org is null or v_draft_org is null then
    raise exception 'adaptive draft requires valid source and draft Programs';
  end if;
  if v_source_org<>v_draft_org
     or new.client_id<>v_source_client
     or new.client_id<>v_draft_client then
    raise exception 'adaptive draft cannot cross organization/client boundary';
  end if;

  if new.adaptation_review_id is not null then
    select r.organization_id,r.client_id into v_review_org,v_review_client
    from public.training_adaptation_reviews r where r.id=new.adaptation_review_id;
    if v_review_org is null
       or v_review_org<>v_source_org
       or v_review_client<>new.client_id then
      raise exception 'adaptive draft review cannot cross organization/client boundary';
    end if;
  end if;

  if new.organization_id is null then new.organization_id:=v_source_org;
  elsif new.organization_id<>v_source_org then
    raise exception 'adaptive draft cannot cross organization boundary';
  end if;

  if tg_op='UPDATE' and new.organization_id is distinct from old.organization_id then
    raise exception 'adaptive draft organization is immutable';
  end if;
  return new;
end;
$function$;

create or replace function private.guard_subscription_billing_tenant_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_org uuid;
  v_client uuid;
begin
  select s.organization_id,s.client_id into v_org,v_client
  from public.client_subscriptions s where s.id=new.subscription_id;

  if v_org is null then raise exception 'billing record requires a valid Subscription'; end if;
  if new.client_id<>v_client then raise exception 'billing record client must match Subscription client'; end if;

  if new.organization_id is null then new.organization_id:=v_org;
  elsif new.organization_id<>v_org then raise exception 'billing record cannot cross organization boundary';
  end if;

  if tg_op='UPDATE' and new.organization_id is distinct from old.organization_id then
    raise exception 'billing record organization is immutable';
  end if;
  return new;
end;
$function$;

create or replace function private.guard_weekly_program_review_tenant_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_program_org uuid;
  v_program_client uuid;
  v_checkin_org uuid;
  v_checkin_client uuid;
begin
  select p.organization_id,p.client_id into v_program_org,v_program_client
  from public.programs p where p.id=new.program_id;
  select c.organization_id,c.client_id into v_checkin_org,v_checkin_client
  from public.weekly_checkins c where c.id=new.checkin_id;

  if v_program_org is null or v_checkin_org is null then
    raise exception 'weekly review requires valid Program and Check-in';
  end if;
  if v_program_org<>v_checkin_org
     or new.client_id<>v_program_client
     or new.client_id<>v_checkin_client then
    raise exception 'weekly review cannot cross organization/client boundary';
  end if;
  if not exists(
    select 1 from public.coach_profiles cp
    where cp.organization_id=v_program_org
      and cp.user_id=new.coach_id
      and cp.status='active'::public.coach_profile_status
  ) then
    raise exception 'weekly review coach must be active in Program organization';
  end if;

  if new.organization_id is null then new.organization_id:=v_program_org;
  elsif new.organization_id<>v_program_org then
    raise exception 'weekly review cannot cross organization boundary';
  end if;

  if tg_op='UPDATE' and new.organization_id is distinct from old.organization_id then
    raise exception 'weekly review organization is immutable';
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_ai_program_generations_tenant_v1 on public.ai_program_generations;
create trigger trg_ai_program_generations_tenant_v1
before insert or update on public.ai_program_generations
for each row execute function private.guard_ai_program_generation_tenant_v1();

drop trigger if exists trg_training_adaptation_reviews_tenant_v1 on public.training_adaptation_reviews;
create trigger trg_training_adaptation_reviews_tenant_v1
before insert or update on public.training_adaptation_reviews
for each row execute function private.guard_training_adaptation_review_tenant_v1();

drop trigger if exists trg_adaptive_program_drafts_tenant_v1 on public.adaptive_program_drafts;
create trigger trg_adaptive_program_drafts_tenant_v1
before insert or update on public.adaptive_program_drafts
for each row execute function private.guard_adaptive_program_draft_tenant_v1();

drop trigger if exists trg_subscription_billing_records_tenant_v1 on public.subscription_billing_records;
create trigger trg_subscription_billing_records_tenant_v1
before insert or update on public.subscription_billing_records
for each row execute function private.guard_subscription_billing_tenant_v1();

drop trigger if exists trg_weekly_program_reviews_tenant_v1 on public.weekly_program_reviews;
create trigger trg_weekly_program_reviews_tenant_v1
before insert or update on public.weekly_program_reviews
for each row execute function private.guard_weekly_program_review_tenant_v1();

-- Replace legacy global-user RLS with tenant-aware access.
drop policy if exists ai_program_generations_select_manage on public.ai_program_generations;
create policy ai_program_generations_select_manage_v2
on public.ai_program_generations for select
to authenticated
using (private.can_manage_client_in_org(organization_id,client_id));

drop policy if exists billing_records_select on public.subscription_billing_records;
create policy billing_records_select_v2
on public.subscription_billing_records for select
to authenticated
using (private.can_view_client_in_org(organization_id,client_id));

drop policy if exists training_adaptation_reviews_staff_read on public.training_adaptation_reviews;
create policy training_adaptation_reviews_staff_read_v2
on public.training_adaptation_reviews for select
to authenticated
using (private.can_manage_client_in_org(organization_id,client_id));

drop policy if exists weekly_program_reviews_select on public.weekly_program_reviews;
create policy weekly_program_reviews_select_v2
on public.weekly_program_reviews for select
to authenticated
using (private.can_manage_client_in_org(organization_id,client_id));

-- Remove browser DDL-adjacent privileges inherited from legacy migrations.
revoke truncate,trigger,references on table public.ai_program_generations from public,anon,authenticated;
revoke truncate,trigger,references on table public.adaptive_program_drafts from public,anon,authenticated;
revoke truncate,trigger,references on table public.subscription_billing_records from public,anon,authenticated;
revoke truncate,trigger,references on table public.training_adaptation_reviews from public,anon,authenticated;
revoke truncate,trigger,references on table public.weekly_program_reviews from public,anon,authenticated;

create index if not exists idx_ai_program_generations_org_client
  on public.ai_program_generations(organization_id,client_id,created_at desc);
create index if not exists idx_adaptive_program_drafts_org_client
  on public.adaptive_program_drafts(organization_id,client_id,created_at desc);
create index if not exists idx_subscription_billing_records_org_client_due
  on public.subscription_billing_records(organization_id,client_id,due_at);
create index if not exists idx_training_adaptation_reviews_org_client
  on public.training_adaptation_reviews(organization_id,client_id,created_at desc);
create index if not exists idx_weekly_program_reviews_org_client_week
  on public.weekly_program_reviews(organization_id,client_id,week_start desc);
