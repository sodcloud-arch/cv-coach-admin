-- ARCH-1.0 · F1.M1.S5 Wave C1 — Event Outbox tenant isolation
-- Makes the operational event bus tenant-aware without changing producer signatures.

alter table public.event_outbox
  add column if not exists organization_id uuid;

create or replace function private.resolve_event_organization_v1(
  p_aggregate_type text,
  p_aggregate_id uuid,
  p_client_id uuid
)
returns uuid
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_type text:=lower(btrim(coalesce(p_aggregate_type,'')));
  v_organization uuid;
  v_parent_client uuid;
begin
  if v_type='workout_session' then
    if p_aggregate_id is null then
      raise exception 'workout_session event requires aggregate_id';
    end if;

    select ws.organization_id,ws.client_id
      into v_organization,v_parent_client
    from public.workout_sessions ws
    where ws.id=p_aggregate_id;

    if v_organization is null then
      raise exception 'event workout_session aggregate not found';
    end if;
    if p_client_id is null or p_client_id<>v_parent_client then
      raise exception 'event client must match workout_session client';
    end if;
    return v_organization;
  end if;

  if v_type='weekly_checkin' then
    if p_aggregate_id is null then
      raise exception 'weekly_checkin event requires aggregate_id';
    end if;

    select wc.organization_id,wc.client_id
      into v_organization,v_parent_client
    from public.weekly_checkins wc
    where wc.id=p_aggregate_id;

    if v_organization is null then
      raise exception 'event weekly_checkin aggregate not found';
    end if;
    if p_client_id is null or p_client_id<>v_parent_client then
      raise exception 'event client must match weekly_checkin client';
    end if;
    return v_organization;
  end if;

  -- Compatibility path for future legacy client-scoped event types.
  -- It intentionally refuses ambiguous users active in multiple Organizations.
  if p_client_id is not null then
    return private.resolve_legacy_client_organization_v1(p_client_id,null);
  end if;

  raise exception 'event tenant cannot be resolved for aggregate type %',v_type;
end;
$function$;

-- Existing rows are deterministic: current producers are Workout Session and Weekly Check-in.
update public.event_outbox e
set organization_id=private.resolve_event_organization_v1(
  e.aggregate_type,e.aggregate_id,e.client_id
)
where e.organization_id is null;

do $$
begin
  if exists(
    select 1
    from public.event_outbox e
    where e.organization_id is null
       or e.organization_id<>private.resolve_event_organization_v1(
         e.aggregate_type,e.aggregate_id,e.client_id
       )
  ) then
    raise exception 'F1.M1.S5: event_outbox tenant backfill validation failed';
  end if;
end $$;

alter table public.event_outbox
  alter column organization_id set not null;

create unique index if not exists ux_event_outbox_org_id
  on public.event_outbox(organization_id,id);

create unique index if not exists ux_event_outbox_org_id_client
  on public.event_outbox(organization_id,id,client_id);

do $$
begin
  if not exists(
    select 1 from pg_constraint
    where conname='event_outbox_organization_id_fkey'
  ) then
    alter table public.event_outbox
      add constraint event_outbox_organization_id_fkey
      foreign key (organization_id)
      references public.organizations(id)
      on delete restrict;
  end if;
end $$;

-- Idempotency is a tenant contract, not a platform-global user contract.
alter table public.event_outbox
  drop constraint if exists event_outbox_idempotency_key_key;

drop index if exists public.event_outbox_idempotency_key_key;

create unique index if not exists uq_event_outbox_org_idempotency
  on public.event_outbox(organization_id,idempotency_key);

create index if not exists ix_event_outbox_org_client_created
  on public.event_outbox(organization_id,client_id,created_at desc);

create or replace function private.guard_event_outbox_tenant_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_organization uuid;
begin
  v_organization:=private.resolve_event_organization_v1(
    new.aggregate_type,new.aggregate_id,new.client_id
  );

  if new.organization_id is null then
    new.organization_id:=v_organization;
  elsif new.organization_id<>v_organization then
    raise exception 'event_outbox cannot cross organization boundary';
  end if;

  if tg_op='UPDATE' and (
    new.organization_id is distinct from old.organization_id
    or new.aggregate_type is distinct from old.aggregate_type
    or new.aggregate_id is distinct from old.aggregate_id
    or new.client_id is distinct from old.client_id
  ) then
    raise exception 'event_outbox tenant identity is immutable';
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_event_outbox_tenant_v1
  on public.event_outbox;

create trigger trg_event_outbox_tenant_v1
before insert or update on public.event_outbox
for each row execute function private.guard_event_outbox_tenant_v1();

create or replace function private.enqueue_event(
  p_event_key text,
  p_aggregate_type text,
  p_aggregate_id uuid,
  p_client_id uuid,
  p_payload jsonb,
  p_idempotency_key text,
  p_occurred_at timestamp with time zone default now()
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_id uuid;
  v_organization uuid;
begin
  if nullif(trim(p_event_key),'') is null then
    raise exception 'event_key is required';
  end if;
  if nullif(trim(p_aggregate_type),'') is null then
    raise exception 'aggregate_type is required';
  end if;
  if nullif(trim(p_idempotency_key),'') is null then
    raise exception 'idempotency_key is required';
  end if;

  v_organization:=private.resolve_event_organization_v1(
    p_aggregate_type,p_aggregate_id,p_client_id
  );

  insert into public.event_outbox(
    organization_id,event_key,aggregate_type,aggregate_id,client_id,
    payload,idempotency_key,occurred_at
  )
  values(
    v_organization,
    upper(trim(p_event_key)),
    lower(trim(p_aggregate_type)),
    p_aggregate_id,
    p_client_id,
    coalesce(p_payload,'{}'::jsonb),
    trim(p_idempotency_key),
    coalesce(p_occurred_at,now())
  )
  on conflict(organization_id,idempotency_key) do update
    set idempotency_key=excluded.idempotency_key
  returning id into v_id;

  return v_id;
end;
$function$;

comment on column public.event_outbox.organization_id is
  'F1.M1.S5 tenant boundary derived from the canonical aggregate.';
comment on function private.enqueue_event(
  text,text,uuid,uuid,jsonb,text,timestamp with time zone
) is
  'F1.M1.S5 tenant-aware event producer. Signature preserved; Organization is derived from aggregate and idempotency is scoped per tenant.';
