-- ARCH-1.0 · F1.M1.S5 Wave H2 — Coach Intelligence Pilot tenant scope
-- Bind legacy intelligence pilots and their cutover audit to canonical Organization context.

alter table public.coach_intelligence_pilots
  add column if not exists organization_id uuid;

update public.coach_intelligence_pilots p
set organization_id = private.resolve_legacy_professional_organization_v1(
  p.coach_id,
  p.client_id
)
where p.organization_id is null;

do $$
begin
  if exists (
    select 1 from public.coach_intelligence_pilots
    where organization_id is null
  ) then
    raise exception 'H2 pilot backfill left rows without organization';
  end if;
end
$$;

alter table public.coach_intelligence_pilots
  alter column organization_id set not null;

alter table public.coach_intelligence_pilots
  drop constraint if exists coach_intelligence_pilots_organization_id_fkey,
  add constraint coach_intelligence_pilots_organization_id_fkey
    foreign key (organization_id)
    references public.organizations(id)
    on delete restrict;

alter table public.coach_intelligence_pilots
  drop constraint if exists coach_intelligence_pilots_coach_same_org,
  add constraint coach_intelligence_pilots_coach_same_org
    foreign key (organization_id,coach_id)
    references public.coach_profiles(organization_id,user_id)
    on delete restrict;

alter table public.coach_intelligence_pilots
  drop constraint if exists coach_intelligence_pilots_client_same_org,
  add constraint coach_intelligence_pilots_client_same_org
    foreign key (organization_id,client_id)
    references public.clients(organization_id,user_id)
    on delete restrict;

drop index if exists public.coach_intelligence_pilots_external_uniq;
create unique index if not exists uq_coach_intelligence_pilots_org_external
  on public.coach_intelligence_pilots(
    organization_id,coach_id,source_system,source_external_id
  )
  where source_external_id is not null;

create unique index if not exists ux_coach_intelligence_pilots_org_id
  on public.coach_intelligence_pilots(organization_id,id);

create index if not exists idx_coach_intelligence_pilots_org_coach_status
  on public.coach_intelligence_pilots(
    organization_id,coach_id,status,updated_at desc
  );

create or replace function private.guard_coach_intelligence_pilot_tenant_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if new.organization_id is null then
    new.organization_id := private.resolve_legacy_professional_organization_v1(
      new.coach_id,new.client_id
    );
  end if;

  if tg_op='UPDATE' then
    if new.organization_id is distinct from old.organization_id
       or new.coach_id is distinct from old.coach_id then
      raise exception 'pilot organization and coach are immutable';
    end if;
  end if;

  if not exists (
    select 1
    from public.organizations o
    where o.id=new.organization_id
      and o.status in (
        'trial'::public.organization_status,
        'active'::public.organization_status
      )
  ) then
    raise exception 'pilot requires an operational organization';
  end if;

  if not private.is_org_professional(new.organization_id,new.coach_id) then
    raise exception 'pilot coach must be active in the same organization';
  end if;

  if new.client_id is not null and not exists (
    select 1
    from public.clients c
    where c.organization_id=new.organization_id
      and c.user_id=new.client_id
      and c.status<>'archived'::public.client_status
  ) then
    raise exception 'pilot client must be active in the same organization';
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_coach_intelligence_pilots_tenant_v1
  on public.coach_intelligence_pilots;
create trigger trg_coach_intelligence_pilots_tenant_v1
before insert or update on public.coach_intelligence_pilots
for each row execute function private.guard_coach_intelligence_pilot_tenant_v1();

alter table public.coach_intelligence_pilots enable row level security;

drop policy if exists coach_intelligence_pilots_insert on public.coach_intelligence_pilots;
drop policy if exists coach_intelligence_pilots_select on public.coach_intelligence_pilots;
drop policy if exists coach_intelligence_pilots_update on public.coach_intelligence_pilots;
drop policy if exists coach_intelligence_pilots_insert_v2 on public.coach_intelligence_pilots;
drop policy if exists coach_intelligence_pilots_select_v2 on public.coach_intelligence_pilots;
drop policy if exists coach_intelligence_pilots_update_v2 on public.coach_intelligence_pilots;

create policy coach_intelligence_pilots_select_v2
on public.coach_intelligence_pilots
for select to authenticated
using (
  private.is_org_admin(organization_id)
  or (
    coach_id=(select auth.uid())
    and private.is_org_professional(organization_id,coach_id)
  )
);

create policy coach_intelligence_pilots_insert_v2
on public.coach_intelligence_pilots
for insert to authenticated
with check (
  private.is_org_admin(organization_id)
  or (
    coach_id=(select auth.uid())
    and private.is_org_professional(organization_id,coach_id)
  )
);

create policy coach_intelligence_pilots_update_v2
on public.coach_intelligence_pilots
for update to authenticated
using (
  private.is_org_admin(organization_id)
  or (
    coach_id=(select auth.uid())
    and private.is_org_professional(organization_id,coach_id)
  )
)
with check (
  private.is_org_admin(organization_id)
  or (
    coach_id=(select auth.uid())
    and private.is_org_professional(organization_id,coach_id)
  )
);

revoke truncate,references,trigger
on table public.coach_intelligence_pilots
from anon,authenticated;

-- Tenant-scope the immutable cutover audit root.
alter table public.cv12_cutover_audit_v90
  add column if not exists organization_id uuid;

update public.cv12_cutover_audit_v90 a
set organization_id=p.organization_id
from public.coach_intelligence_pilots p
where p.id=a.pilot_id
  and a.organization_id is null;

do $$
begin
  if exists (
    select 1 from public.cv12_cutover_audit_v90
    where organization_id is null
  ) then
    raise exception 'H2 cutover audit backfill left rows without organization';
  end if;
end
$$;

alter table public.cv12_cutover_audit_v90
  alter column organization_id set not null;

alter table public.cv12_cutover_audit_v90
  drop constraint if exists cv12_cutover_audit_v90_organization_id_fkey,
  add constraint cv12_cutover_audit_v90_organization_id_fkey
    foreign key (organization_id)
    references public.organizations(id)
    on delete restrict;

alter table public.cv12_cutover_audit_v90
  drop constraint if exists cv12_cutover_audit_v90_pilot_same_org,
  add constraint cv12_cutover_audit_v90_pilot_same_org
    foreign key (organization_id,pilot_id)
    references public.coach_intelligence_pilots(organization_id,id)
    on delete cascade;

alter table public.cv12_cutover_audit_v90
  drop constraint if exists cv12_cutover_audit_v90_client_same_org,
  add constraint cv12_cutover_audit_v90_client_same_org
    foreign key (organization_id,client_id)
    references public.clients(organization_id,user_id)
    on delete restrict;

create index if not exists idx_cv12_cutover_audit_v90_org_pilot_created
  on public.cv12_cutover_audit_v90(
    organization_id,pilot_id,created_at desc
  );

create or replace function private.guard_cv12_cutover_audit_tenant_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_organization uuid;
begin
  select p.organization_id into v_organization
  from public.coach_intelligence_pilots p
  where p.id=new.pilot_id;

  if v_organization is null then
    raise exception 'audit requires an existing pilot';
  end if;

  new.organization_id:=coalesce(new.organization_id,v_organization);

  if new.organization_id<>v_organization then
    raise exception 'audit organization must match pilot organization';
  end if;

  if new.client_id is not null and not exists (
    select 1
    from public.clients c
    where c.organization_id=new.organization_id
      and c.user_id=new.client_id
      and c.status<>'archived'::public.client_status
  ) then
    raise exception 'audit client must belong to pilot organization';
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_cv12_cutover_audit_tenant_v1
  on public.cv12_cutover_audit_v90;
create trigger trg_cv12_cutover_audit_tenant_v1
before insert or update on public.cv12_cutover_audit_v90
for each row execute function private.guard_cv12_cutover_audit_tenant_v1();

alter table public.cv12_cutover_audit_v90 enable row level security;
revoke all on table public.cv12_cutover_audit_v90 from anon,authenticated;

-- Browser plan read: authenticated and tenant-authorized only.
create or replace function public.get_cv12_native_cutover_plan_v87(p_pilot_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  p public.coach_intelligence_pilots%rowtype;
  v_uid uuid:=auth.uid();
  v_role public.app_role;
  v_sessions integer;
  v_logs integer;
  v_unmapped integer;
  v_measurements integer;
  v_blockers jsonb := '[]'::jsonb;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;

  select role into v_role
  from public.profiles
  where id=v_uid and status='active'::public.profile_status;

  if v_role is null
     or v_role not in ('admin'::public.app_role,'coach'::public.app_role) then
    raise exception 'Coach/admin required';
  end if;

  select * into p
  from public.coach_intelligence_pilots
  where id=p_pilot_id;

  if p.id is null then raise exception 'Pilot not found'; end if;

  if not (
    private.is_org_admin(p.organization_id)
    or (
      p.coach_id=v_uid
      and private.is_org_professional(p.organization_id,v_uid)
    )
  ) then
    raise exception 'Pilot not available in this organization';
  end if;

  select count(*) into v_sessions
  from public.legacy_cv12_sessions_v87
  where pilot_id=p_pilot_id;

  select count(*) into v_logs
  from public.legacy_cv12_exercise_logs_v87
  where pilot_id=p_pilot_id;

  select count(*) into v_unmapped
  from public.legacy_cv12_exercise_logs_v87
  where pilot_id=p_pilot_id and mapping_status<>'linked';

  select count(*) into v_measurements
  from public.legacy_cv12_measurements_v87
  where pilot_id=p_pilot_id;

  if p.client_id is null then
    v_blockers:=v_blockers||jsonb_build_array('native_auth_identity_required');
  end if;
  if v_sessions=0 then
    v_blockers:=v_blockers||jsonb_build_array('legacy_history_not_synced');
  end if;

  return jsonb_build_object(
    'engine_version','CV12_NATIVE_CUTOVER_V87',
    'organization_id',p.organization_id,
    'pilot_id',p.id,
    'subject_label',p.subject_label,
    'source_system',p.source_system,
    'client_id',p.client_id,
    'sessions',v_sessions,
    'exercise_logs',v_logs,
    'unmapped_exercise_logs',v_unmapped,
    'measurements',v_measurements,
    'ai_ready',p.status in ('ready_observed','active_observed','linked'),
    'migration_ready',(p.client_id is not null and v_sessions>0),
    'blockers',v_blockers,
    'next_action',case
      when p.client_id is null then
        'Create or identify the real native auth user, then link this pilot. Never create a synthetic identity.'
      when v_sessions=0 then 'Sync legacy history before cutover.'
      else 'Native cutover can proceed with legacy history preserved.'
    end,
    'guardrails',jsonb_build_object(
      'preserve_legacy_rows',true,
      'auto_publish',false,
      'auto_program_edit',false
    )
  );
end;
$function$;

revoke all on function public.get_cv12_native_cutover_plan_v87(uuid) from public,anon;
grant execute on function public.get_cv12_native_cutover_plan_v87(uuid)
to authenticated,service_role;

-- Linking must use the pilot Organization as authority.
create or replace function public.link_cv12_pilot_native_v87(
  p_pilot_id uuid,
  p_client_id uuid,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_role public.app_role;
  v_name text;
  v_pilot public.coach_intelligence_pilots%rowtype;
begin
  if auth.uid() is null or auth.uid()<>p_actor_id then
    raise exception 'Actor authentication mismatch';
  end if;

  select role into v_role
  from public.profiles
  where id=p_actor_id and status='active'::public.profile_status;

  if v_role is null
     or v_role not in ('admin'::public.app_role,'coach'::public.app_role) then
    raise exception 'Coach/admin required';
  end if;

  select * into v_pilot
  from public.coach_intelligence_pilots
  where id=p_pilot_id
  for update;

  if not found then raise exception 'Pilot not found'; end if;

  if not (
    private.is_org_admin(v_pilot.organization_id)
    or (
      v_pilot.coach_id=p_actor_id
      and private.is_org_professional(v_pilot.organization_id,p_actor_id)
    )
  ) then
    raise exception 'Pilot not available in this organization';
  end if;

  if not (
    private.is_org_admin(v_pilot.organization_id)
    or private.actor_can_manage_client_in_org_v1(
      p_actor_id,v_pilot.organization_id,p_client_id
    )
  ) then
    raise exception 'Actor cannot manage client in pilot organization';
  end if;

  select concat_ws(' ',p.first_name,p.last_name) into v_name
  from public.profiles p
  join public.clients c
    on c.organization_id=v_pilot.organization_id
   and c.user_id=p.id
   and c.status<>'archived'::public.client_status
  where p.id=p_client_id
    and p.role='client'::public.app_role
    and p.status='active'::public.profile_status;

  if v_name is null then
    raise exception 'Native active client in pilot organization required';
  end if;

  update public.coach_intelligence_pilots
  set client_id=p_client_id,
      linked_at=now(),
      status='linked',
      updated_at=now()
  where id=p_pilot_id
    and organization_id=v_pilot.organization_id;

  return jsonb_build_object(
    'ok',true,
    'organization_id',v_pilot.organization_id,
    'pilot_id',p_pilot_id,
    'client_id',p_client_id,
    'client_name',v_name,
    'legacy_history_preserved',true,
    'auto_publish',false
  );
end;
$function$;

-- Unlinking preserves the tenant and requires current pilot access.
create or replace function public.unlink_cv12_pilot_native_v88(
  p_pilot_id uuid,
  p_expected_client_id uuid,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_role public.app_role;
  v_refresh jsonb;
  v_pilot public.coach_intelligence_pilots%rowtype;
begin
  if auth.uid() is null or auth.uid()<>p_actor_id then
    raise exception 'Actor authentication mismatch';
  end if;

  select role into v_role
  from public.profiles
  where id=p_actor_id and status='active'::public.profile_status;

  if v_role is null
     or v_role not in ('admin'::public.app_role,'coach'::public.app_role) then
    raise exception 'Coach/admin required';
  end if;

  select * into v_pilot
  from public.coach_intelligence_pilots
  where id=p_pilot_id
    and client_id=p_expected_client_id
    and source_system='cv12_legacy'
  for update;

  if not found then
    raise exception 'Pilot/client link not found or changed';
  end if;

  if not (
    private.is_org_admin(v_pilot.organization_id)
    or (
      v_pilot.coach_id=p_actor_id
      and private.is_org_professional(v_pilot.organization_id,p_actor_id)
    )
  ) then
    raise exception 'Pilot not available in this organization';
  end if;

  update public.coach_intelligence_pilots
  set client_id=null,
      linked_at=null,
      updated_at=now()
  where id=p_pilot_id
    and organization_id=v_pilot.organization_id
    and client_id=p_expected_client_id;

  v_refresh := public.refresh_cv12_pilot_baseline_v87(p_pilot_id);

  return jsonb_build_object(
    'ok',true,
    'engine_version','CV12_NATIVE_READ_BRIDGE_V88',
    'organization_id',v_pilot.organization_id,
    'pilot_id',p_pilot_id,
    'unlinked_client_id',p_expected_client_id,
    'legacy_history_preserved',true,
    'native_data_deleted',false,
    'baseline',v_refresh,
    'auto_publish',false,
    'auto_program_edit',false
  );
end;
$function$;

-- V90 cutover derives every authorization and write from the Pilot Organization.
create or replace function public.execute_cv12_native_cutover_v90(
  p_pilot_id uuid,
  p_client_id uuid,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor_role public.app_role;
  v_client_name text;
  v_client_email text;
  v_pilot public.coach_intelligence_pilots%rowtype;
  v_pre jsonb;
  v_post jsonb;
  v_refresh jsonb;
  v_action text;
  v_audit_id uuid;
begin
  if auth.uid() is null or auth.uid()<>p_actor_id then
    raise exception 'Actor authentication mismatch';
  end if;

  select role into v_actor_role
  from public.profiles
  where id=p_actor_id and status='active'::public.profile_status;

  if v_actor_role is null
     or v_actor_role not in ('admin'::public.app_role,'coach'::public.app_role) then
    raise exception 'Coach/admin required';
  end if;

  select * into v_pilot
  from public.coach_intelligence_pilots
  where id=p_pilot_id
    and source_system='cv12_legacy'
    and mode='observed_only'
  for update;

  if not found then
    raise exception 'V90 requires an observed_only cv12_legacy pilot';
  end if;

  if not (
    private.is_org_admin(v_pilot.organization_id)
    or (
      v_pilot.coach_id=p_actor_id
      and private.is_org_professional(v_pilot.organization_id,p_actor_id)
    )
  ) then
    raise exception 'Pilot not available in this organization';
  end if;

  if not (
    private.is_org_admin(v_pilot.organization_id)
    or private.actor_can_manage_client_in_org_v1(
      p_actor_id,v_pilot.organization_id,p_client_id
    )
  ) then
    raise exception 'Actor cannot manage client in pilot organization';
  end if;

  select concat_ws(' ',p.first_name,p.last_name),u.email
  into v_client_name,v_client_email
  from public.profiles p
  join auth.users u on u.id=p.id
  join public.clients c
    on c.organization_id=v_pilot.organization_id
   and c.user_id=p.id
   and c.status<>'archived'::public.client_status
  where p.id=p_client_id
    and p.role='client'::public.app_role
    and p.status='active'::public.profile_status
    and u.email is not null
  limit 1;

  if v_client_name is null or v_client_email is null then
    raise exception 'Real native active client identity in pilot organization required';
  end if;

  if not exists (
    select 1
    from public.client_profiles cp
    where cp.organization_id=v_pilot.organization_id
      and cp.client_id=p_client_id
  ) then
    raise exception 'Native client profile in pilot organization required';
  end if;

  v_pre := public.get_cv12_cutover_readiness_v89(p_pilot_id);

  if coalesce(
    (v_pre->'readiness'->>'technical_ready_for_native_identity')::boolean,
    false
  ) is distinct from true then
    raise exception 'CV12 pilot is not technically ready for native identity';
  end if;

  if v_pilot.client_id is null then
    update public.coach_intelligence_pilots
    set client_id=p_client_id,
        linked_at=now(),
        status='linked',
        updated_at=now()
    where id=p_pilot_id
      and organization_id=v_pilot.organization_id
      and client_id is null;

    if not found then
      raise exception 'Pilot identity changed during cutover';
    end if;

    v_action:='linked';
  elsif v_pilot.client_id=p_client_id then
    if v_pilot.linked_at is null then
      update public.coach_intelligence_pilots
      set linked_at=now(),updated_at=now()
      where id=p_pilot_id
        and organization_id=v_pilot.organization_id
        and client_id=p_client_id;
    end if;
    v_action:='noop_existing_link';
  else
    raise exception 'Pilot already linked to another native client';
  end if;

  v_refresh:=public.refresh_cv12_pilot_baseline_v87(p_pilot_id);
  v_post:=public.get_cv12_cutover_readiness_v89(p_pilot_id);

  if coalesce(
    (v_post->'readiness'->>'ready_for_real_cutover')::boolean,
    false
  ) is distinct from true then
    raise exception 'V90 post-cutover readiness verification failed';
  end if;

  insert into public.cv12_cutover_audit_v90(
    organization_id,pilot_id,client_id,actor_id,action,
    idempotency_key,readiness,updated_at
  )
  values(
    v_pilot.organization_id,p_pilot_id,p_client_id,p_actor_id,v_action,
    'cv12_native_cutover:'||p_pilot_id::text||':'||p_client_id::text,
    v_post,now()
  )
  on conflict (idempotency_key)
  do update set
    organization_id=excluded.organization_id,
    readiness=excluded.readiness,
    updated_at=now()
  returning id into v_audit_id;

  return jsonb_build_object(
    'ok',true,
    'engine_version','CV12_NATIVE_CUTOVER_ORCHESTRATOR_V90',
    'organization_id',v_pilot.organization_id,
    'action',v_action,
    'pilot_id',p_pilot_id,
    'client_id',p_client_id,
    'native_identity_verified',true,
    'native_client_name',v_client_name,
    'audit_id',v_audit_id,
    'readiness',v_post,
    'baseline',v_refresh,
    'event_emission_deferred',true,
    'event_reason','No registered consumer owns a CV12 cutover event yet.',
    'guardrails',jsonb_build_object(
      'auto_publish',false,
      'auto_program_edit',false,
      'native_sessions_created',false,
      'native_programs_created',false,
      'legacy_source_preserved',true,
      'synthetic_identity_forbidden',true
    )
  );
end;
$function$;

-- Cutover control is restricted to active tenant professionals/admins.
create or replace function public.get_cv12_cutover_control_v91(
  p_pilot_id uuid default null::uuid
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid:=auth.uid();
  v_role public.app_role;
  v_items jsonb:='[]'::jsonb;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;

  select role into v_role
  from public.profiles
  where id=v_uid and status='active'::public.profile_status;

  if v_role is null
     or v_role not in ('admin'::public.app_role,'coach'::public.app_role) then
    raise exception 'Coach/admin required';
  end if;

  select coalesce(jsonb_agg(item order by subject_label),'[]'::jsonb)
  into v_items
  from (
    select
      p.subject_label,
      jsonb_build_object(
        'organization_id',p.organization_id,
        'pilot_id',p.id,
        'subject_label',p.subject_label,
        'coach_id',p.coach_id,
        'client_id',p.client_id,
        'source_system',p.source_system,
        'mode',p.mode,
        'status',p.status,
        'started_at',p.started_at,
        'linked_at',p.linked_at,
        'updated_at',p.updated_at,
        'readiness',public.get_cv12_cutover_readiness_v89(p.id),
        'next_action',case
          when coalesce((public.get_cv12_cutover_readiness_v89(p.id)->'readiness'->>'technical_ready_for_native_identity')::boolean,false)=false then 'repair_legacy_sync'
          when coalesce((public.get_cv12_cutover_readiness_v89(p.id)->'native_identity'->>'identity_required')::boolean,false)=true then 'provide_real_client_email'
          when coalesce((public.get_cv12_cutover_readiness_v89(p.id)->'readiness'->>'ready_for_real_cutover')::boolean,false)=true
               and coalesce((public.get_cv12_cutover_readiness_v89(p.id)->'readiness'->>'longitudinal_ai_ready')::boolean,false)=false then 'collect_more_training_evidence'
          when coalesce((public.get_cv12_cutover_readiness_v89(p.id)->'readiness'->>'ready_for_real_cutover')::boolean,false)=true then 'cutover_complete'
          else 'review'
        end
      ) as item
    from public.coach_intelligence_pilots p
    where p.source_system='cv12_legacy'
      and p.mode='observed_only'
      and (p_pilot_id is null or p.id=p_pilot_id)
      and (
        private.is_org_admin(p.organization_id)
        or (
          p.coach_id=v_uid
          and private.is_org_professional(p.organization_id,v_uid)
        )
      )
  ) q;

  return jsonb_build_object(
    'ok',true,
    'engine_version','CV12_CUTOVER_CONTROL_API_V91',
    'actor_role',v_role,
    'items',v_items,
    'count',jsonb_array_length(v_items),
    'execution_rpc','execute_cv12_native_cutover_v90',
    'rollback_rpc','rollback_cv12_native_cutover_v90'
  );
end;
$function$;

-- Audit read follows the pilot Organization.
create or replace function public.get_cv12_cutover_audit_v92(
  p_pilot_id uuid default null::uuid
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid:=auth.uid();
  v_role public.app_role;
  v_items jsonb:='[]'::jsonb;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;

  select p.role into v_role
  from public.profiles p
  where p.id=v_uid and p.status='active'::public.profile_status;

  if v_role is null
     or v_role not in ('admin'::public.app_role,'coach'::public.app_role) then
    raise exception 'Coach/admin required';
  end if;

  if p_pilot_id is not null and not exists (
    select 1
    from public.coach_intelligence_pilots cp
    where cp.id=p_pilot_id
      and (
        private.is_org_admin(cp.organization_id)
        or (
          cp.coach_id=v_uid
          and private.is_org_professional(cp.organization_id,v_uid)
        )
      )
  ) then
    raise exception 'Pilot not available in this organization';
  end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb)
  into v_items
  from (
    select
      a.id,
      a.organization_id,
      a.pilot_id,
      a.client_id,
      a.actor_id,
      a.action,
      a.idempotency_key,
      a.readiness,
      a.created_at,
      a.updated_at
    from public.cv12_cutover_audit_v90 a
    join public.coach_intelligence_pilots cp
      on cp.organization_id=a.organization_id
     and cp.id=a.pilot_id
    where (p_pilot_id is null or a.pilot_id=p_pilot_id)
      and (
        private.is_org_admin(cp.organization_id)
        or (
          cp.coach_id=v_uid
          and private.is_org_professional(cp.organization_id,v_uid)
        )
      )
    order by a.created_at desc
    limit 100
  ) x;

  return jsonb_build_object(
    'ok',true,
    'engine_version','CV12_CUTOVER_ADMIN_V92',
    'pilot_id',p_pilot_id,
    'count',jsonb_array_length(v_items),
    'items',v_items,
    'guardrails',jsonb_build_object(
      'read_only',true,
      'mutations_via_v90_only',true,
      'auto_publish',false,
      'auto_program_edit',false
    )
  );
end;
$function$;

-- These helpers are internal/service-only; browser mutation is never required.
revoke all on function public.refresh_cv12_pilot_baseline_v87(uuid)
from public,anon,authenticated;
grant execute on function public.refresh_cv12_pilot_baseline_v87(uuid)
to service_role;

comment on column public.coach_intelligence_pilots.organization_id is
  'F1.M1.S5 H2 canonical tenant identity for Coach Intelligence pilots.';
comment on column public.cv12_cutover_audit_v90.organization_id is
  'F1.M1.S5 H2 tenant identity inherited from the owning intelligence pilot.';
