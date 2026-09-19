-- F1.M2.S6 — COACH tenant role + professional profile + assignment-scoped authority

create or replace function private.is_org_professional(
  target_organization uuid,
  target_user uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    private.member_has_org_role_v1(
      target_organization,target_user,'coach'::public.organization_member_role
    )
    and exists(
      select 1
      from public.coach_profiles cp
      where cp.organization_id=target_organization
        and cp.user_id=target_user
        and cp.status='active'::public.coach_profile_status
    ),
    false
  )
$function$;

create or replace function private.coach_has_all_clients_capability_v1(
  p_organization_id uuid,
  p_coach_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    private.is_org_professional(p_organization_id,p_coach_user_id)
    and exists(
      select 1
      from public.coach_profiles cp
      where cp.organization_id=p_organization_id
        and cp.user_id=p_coach_user_id
        and cp.status='active'::public.coach_profile_status
        and lower(coalesce(cp.capabilities->>'manage_all_clients','false'))='true'
    ),
    false
  )
$function$;

create or replace function private.coach_can_access_client_v1(
  p_organization_id uuid,
  p_coach_user_id uuid,
  p_client_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    private.is_org_professional(p_organization_id,p_coach_user_id)
    and (
      private.coach_has_all_clients_capability_v1(
        p_organization_id,p_coach_user_id
      )
      or exists(
        select 1
        from public.clients c
        join public.client_coach_assignments a
          on a.organization_id=c.organization_id
         and a.client_id=c.id
         and a.status='active'::public.client_coach_assignment_status
        join public.coach_profiles cp
          on cp.organization_id=a.organization_id
         and cp.id=a.coach_id
         and cp.user_id=p_coach_user_id
         and cp.status='active'::public.coach_profile_status
        where c.organization_id=p_organization_id
          and c.user_id=p_client_user_id
          and c.status<>'archived'::public.client_status
      )
    ),
    false
  )
$function$;

create or replace function private.can_manage_client_in_org(
  target_organization uuid,
  target_client_user uuid
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    private.is_org_admin(target_organization)
    or private.coach_can_access_client_v1(
      target_organization,auth.uid(),target_client_user
    ),
    false
  )
$function$;

create or replace function private.actor_can_manage_client_in_org_v1(
  p_actor_id uuid,
  p_organization_id uuid,
  p_client_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    private.is_org_owner_v1(p_organization_id,p_actor_id)
    or private.member_has_org_role_v1(
      p_organization_id,p_actor_id,'org_admin'::public.organization_member_role
    )
    or private.coach_can_access_client_v1(
      p_organization_id,p_actor_id,p_client_user_id
    ),
    false
  )
$function$;

create or replace function private.can_view_client_entity(target_client uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    auth.role()='service_role'
    or exists(
      select 1
      from public.clients c
      where c.id=target_client
        and (
          private.is_org_admin(c.organization_id)
          or (
            c.user_id=auth.uid()
            and private.is_org_member(c.organization_id)
          )
          or private.coach_can_access_client_v1(
            c.organization_id,auth.uid(),c.user_id
          )
        )
    ),
    false
  )
$function$;

create or replace function private.can_view_client_coach_assignment(
  target_organization uuid,
  target_client uuid,
  target_coach uuid
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    auth.role()='service_role'
    or private.is_org_admin(target_organization)
    or exists(
      select 1
      from public.coach_profiles cp
      where cp.id=target_coach
        and cp.organization_id=target_organization
        and cp.user_id=auth.uid()
        and private.is_org_professional(target_organization,auth.uid())
    )
    or exists(
      select 1
      from public.clients c
      where c.id=target_client
        and c.organization_id=target_organization
        and c.user_id=auth.uid()
        and private.is_org_member(target_organization)
    ),
    false
  )
$function$;

create or replace function public.create_coach_profile(
  p_organization_id uuid,
  p_user_id uuid,
  p_display_name text default null::text,
  p_primary_discipline public.professional_discipline default 'training'::public.professional_discipline,
  p_additional_disciplines public.professional_discipline[] default '{}'::public.professional_discipline[],
  p_bio text default null::text,
  p_capacity_clients integer default null::integer,
  p_media jsonb default '{}'::jsonb,
  p_capabilities jsonb default '{}'::jsonb,
  p_practice_scope jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid:=auth.uid();
  v_coach_profile_id uuid;
  v_display_name text;
  v_discipline public.professional_discipline;
  v_member public.organization_members%rowtype;
  v_safe_capabilities jsonb;
begin
  if auth.role()<>'service_role'
     and (v_actor is null or not private.is_org_admin(p_organization_id)) then
    raise exception 'ORG_ADMIN or backend required to create a coach profile';
  end if;

  if not exists(
    select 1 from public.organizations o
    where o.id=p_organization_id
      and o.status in (
        'trial'::public.organization_status,
        'active'::public.organization_status
      )
  ) then
    raise exception 'organization is not operational';
  end if;

  if not exists(
    select 1 from public.profiles p
    where p.id=p_user_id
      and p.status='active'::public.profile_status
  ) then
    raise exception 'professional must be an active platform user';
  end if;

  select * into v_member
  from public.organization_members om
  where om.organization_id=p_organization_id
    and om.user_id=p_user_id;

  if not found then
    if auth.role()<>'service_role' then
      raise exception 'COACH role must be granted before profile creation';
    end if;

    insert into public.organization_members(
      organization_id,user_id,role,status,joined_at
    )
    values(
      p_organization_id,p_user_id,
      'coach'::public.organization_member_role,
      'active'::public.organization_member_status,
      now()
    )
    returning * into v_member;
  elsif v_member.status<>'active'::public.organization_member_status then
    raise exception 'professional organization membership is not active';
  end if;

  if not private.member_has_org_role_v1(
    p_organization_id,p_user_id,'coach'::public.organization_member_role
  ) then
    if auth.role()<>'service_role' then
      raise exception 'COACH role must be granted before profile creation';
    end if;

    insert into public.organization_member_roles(
      member_id,organization_id,user_id,role,status,
      grant_reason,granted_by,granted_at,metadata
    )
    values(
      v_member.id,p_organization_id,p_user_id,
      'coach'::public.organization_member_role,
      'active'::public.organization_member_role_assignment_status,
      'Backend coach-profile provisioning',
      null,now(),
      jsonb_build_object('source','create_coach_profile')
    )
    on conflict (member_id,role)
      where status='active'::public.organization_member_role_assignment_status
    do nothing;

    perform private.recompute_organization_member_primary_role_v1(v_member.id);
  end if;

  select coalesce(
    nullif(btrim(coalesce(p_display_name,'')),''),
    nullif(btrim(concat_ws(' ',p.first_name,p.last_name)),''),
    'Professional'
  )
  into v_display_name
  from public.profiles p
  where p.id=p_user_id;

  -- Scope-expanding capabilities are granted only through the dedicated audited RPC.
  v_safe_capabilities:=coalesce(p_capabilities,'{}'::jsonb)-'manage_all_clients';

  insert into public.coach_profiles(
    organization_id,user_id,display_name,status,bio,capacity_clients,
    media,capabilities,practice_scope
  )
  values(
    p_organization_id,p_user_id,v_display_name,
    'active'::public.coach_profile_status,
    nullif(btrim(coalesce(p_bio,'')),''),
    p_capacity_clients,
    coalesce(p_media,'{}'::jsonb),
    v_safe_capabilities,
    coalesce(p_practice_scope,'{}'::jsonb)
  )
  returning id into v_coach_profile_id;

  insert into public.coach_profile_disciplines(
    coach_profile_id,discipline,is_primary
  )
  values(v_coach_profile_id,p_primary_discipline,true);

  foreach v_discipline in array coalesce(
    p_additional_disciplines,
    '{}'::public.professional_discipline[]
  )
  loop
    if v_discipline<>p_primary_discipline then
      insert into public.coach_profile_disciplines(
        coach_profile_id,discipline,is_primary
      )
      values(v_coach_profile_id,v_discipline,false)
      on conflict (coach_profile_id,discipline) do nothing;
    end if;
  end loop;

  insert into public.organization_permission_audit(
    organization_id,member_id,target_user_id,actor_user_id,
    action,role,reason,payload
  )
  values(
    p_organization_id,v_member.id,p_user_id,v_actor,
    'coach_profile_created','coach'::public.organization_member_role,
    'Coach professional profile created',
    jsonb_build_object('coach_profile_id',v_coach_profile_id)
  );

  return v_coach_profile_id;
end;
$function$;

create or replace function public.set_coach_scope_capability_v1(
  p_organization_id uuid,
  p_coach_user_id uuid,
  p_manage_all_clients boolean,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid:=auth.uid();
  v_reason text:=btrim(coalesce(p_reason,''));
  v_profile public.coach_profiles%rowtype;
begin
  if v_actor is null or not private.is_org_admin(p_organization_id) then
    raise exception 'ORG_ADMIN or ORG_OWNER required';
  end if;

  if char_length(v_reason)<4 or char_length(v_reason)>1000 then
    raise exception 'capability change reason must be 4..1000 characters';
  end if;

  if not private.member_has_org_role_v1(
    p_organization_id,p_coach_user_id,'coach'::public.organization_member_role
  ) then
    raise exception 'Active COACH tenant role required';
  end if;

  select * into v_profile
  from public.coach_profiles cp
  where cp.organization_id=p_organization_id
    and cp.user_id=p_coach_user_id
    and cp.status='active'::public.coach_profile_status
  for update;

  if not found then
    raise exception 'Active coach profile required';
  end if;

  update public.coach_profiles
  set capabilities=jsonb_set(
        coalesce(capabilities,'{}'::jsonb),
        '{manage_all_clients}',
        to_jsonb(p_manage_all_clients),
        true
      ),
      updated_at=now()
  where id=v_profile.id;

  insert into public.organization_permission_audit(
    organization_id,target_user_id,actor_user_id,action,role,reason,payload
  )
  values(
    p_organization_id,p_coach_user_id,v_actor,
    'coach_scope_capability_changed',
    'coach'::public.organization_member_role,
    v_reason,
    jsonb_build_object(
      'coach_profile_id',v_profile.id,
      'manage_all_clients',p_manage_all_clients
    )
  );

  return jsonb_build_object(
    'organization_id',p_organization_id,
    'coach_user_id',p_coach_user_id,
    'manage_all_clients',p_manage_all_clients,
    'audited',true,
    'version','F1.M2.S6_COACH_SCOPE_V1'
  );
end;
$function$;

create or replace function public.set_coach_profile_status_v1(
  p_organization_id uuid,
  p_coach_user_id uuid,
  p_status public.coach_profile_status,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid:=auth.uid();
  v_reason text:=btrim(coalesce(p_reason,''));
  v_profile public.coach_profiles%rowtype;
begin
  if v_actor is null or not private.is_org_admin(p_organization_id) then
    raise exception 'ORG_ADMIN or ORG_OWNER required';
  end if;

  if char_length(v_reason)<4 or char_length(v_reason)>1000 then
    raise exception 'coach status change reason must be 4..1000 characters';
  end if;

  select * into v_profile
  from public.coach_profiles cp
  where cp.organization_id=p_organization_id
    and cp.user_id=p_coach_user_id
  for update;

  if not found then
    raise exception 'Coach profile not found';
  end if;

  update public.coach_profiles
  set status=p_status,
      archived_at=case
        when p_status='archived'::public.coach_profile_status then now()
        else null
      end,
      updated_at=now()
  where id=v_profile.id;

  insert into public.organization_permission_audit(
    organization_id,target_user_id,actor_user_id,action,role,reason,payload
  )
  values(
    p_organization_id,p_coach_user_id,v_actor,
    'coach_profile_status_changed',
    'coach'::public.organization_member_role,
    v_reason,
    jsonb_build_object(
      'coach_profile_id',v_profile.id,
      'old_status',v_profile.status,
      'new_status',p_status
    )
  );

  return jsonb_build_object(
    'coach_profile_id',v_profile.id,
    'status',p_status,
    'audited',true,
    'version','F1.M2.S6_COACH_PROFILE_STATUS_V1'
  );
end;
$function$;

create or replace function public.assign_client_coach(
  p_organization_id uuid,
  p_client_id uuid,
  p_coach_id uuid,
  p_assignment_role public.client_coach_assignment_role default 'secondary'::public.client_coach_assignment_role,
  p_assigned_by uuid default null::uuid
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid:=auth.uid();
  v_effective_actor uuid;
  v_existing public.client_coach_assignments%rowtype;
  v_assignment_id uuid;
  v_coach_user_id uuid;
  v_client_user_id uuid;
begin
  if auth.role()='service_role' then
    v_effective_actor:=p_assigned_by;
  else
    if v_actor is null or not private.is_org_admin(p_organization_id) then
      raise exception 'ORG_ADMIN or backend required for coach assignment';
    end if;
    if p_assigned_by is not null and p_assigned_by<>v_actor then
      raise exception 'assigned_by cannot impersonate another actor';
    end if;
    v_effective_actor:=v_actor;
  end if;

  select c.user_id into v_client_user_id
  from public.clients c
  where c.id=p_client_id
    and c.organization_id=p_organization_id
    and c.status<>'archived'::public.client_status;
  if not found then
    raise exception 'client is not assignable in this organization';
  end if;

  select cp.user_id into v_coach_user_id
  from public.coach_profiles cp
  where cp.id=p_coach_id
    and cp.organization_id=p_organization_id
    and cp.status='active'::public.coach_profile_status;
  if not found or not private.member_has_org_role_v1(
    p_organization_id,v_coach_user_id,'coach'::public.organization_member_role
  ) then
    raise exception 'active COACH role and coach profile required';
  end if;

  select * into v_existing
  from public.client_coach_assignments a
  where a.organization_id=p_organization_id
    and a.client_id=p_client_id
    and a.coach_id=p_coach_id
    and a.status='active'::public.client_coach_assignment_status
  for update;

  if found and v_existing.assignment_role=p_assignment_role then
    return v_existing.id;
  elsif found then
    update public.client_coach_assignments
    set status='ended'::public.client_coach_assignment_status,
        unassigned_at=now(),
        unassigned_by=v_effective_actor
    where id=v_existing.id;

    insert into public.organization_permission_audit(
      organization_id,target_user_id,actor_user_id,action,role,reason,payload
    )
    values(
      p_organization_id,v_coach_user_id,v_effective_actor,
      'coach_assignment_ended',
      'coach'::public.organization_member_role,
      'Assignment role changed',
      jsonb_build_object(
        'assignment_id',v_existing.id,
        'client_id',p_client_id,
        'client_user_id',v_client_user_id
      )
    );
  end if;

  if p_assignment_role='primary'::public.client_coach_assignment_role then
    update public.client_coach_assignments
    set status='ended'::public.client_coach_assignment_status,
        unassigned_at=now(),
        unassigned_by=v_effective_actor
    where organization_id=p_organization_id
      and client_id=p_client_id
      and assignment_role='primary'::public.client_coach_assignment_role
      and status='active'::public.client_coach_assignment_status;
  end if;

  insert into public.client_coach_assignments(
    organization_id,client_id,coach_id,assignment_role,status,
    assigned_at,assigned_by
  )
  values(
    p_organization_id,p_client_id,p_coach_id,p_assignment_role,
    'active'::public.client_coach_assignment_status,
    now(),v_effective_actor
  )
  returning id into v_assignment_id;

  insert into public.organization_permission_audit(
    organization_id,target_user_id,actor_user_id,action,role,reason,payload
  )
  values(
    p_organization_id,v_coach_user_id,v_effective_actor,
    'coach_assignment_started',
    'coach'::public.organization_member_role,
    'Client assigned to coach',
    jsonb_build_object(
      'assignment_id',v_assignment_id,
      'client_id',p_client_id,
      'client_user_id',v_client_user_id,
      'assignment_role',p_assignment_role
    )
  );

  return v_assignment_id;
end;
$function$;

create or replace function public.end_client_coach_assignment(
  p_assignment_id uuid,
  p_unassigned_by uuid default null::uuid
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid:=auth.uid();
  v_effective_actor uuid;
  v_assignment public.client_coach_assignments%rowtype;
  v_coach_user_id uuid;
  v_client_user_id uuid;
begin
  select * into v_assignment
  from public.client_coach_assignments a
  where a.id=p_assignment_id
  for update;

  if not found then
    raise exception 'assignment not found';
  end if;

  if auth.role()='service_role' then
    v_effective_actor:=p_unassigned_by;
  else
    if v_actor is null or not private.is_org_admin(v_assignment.organization_id) then
      raise exception 'ORG_ADMIN or backend required for coach unassignment';
    end if;
    if p_unassigned_by is not null and p_unassigned_by<>v_actor then
      raise exception 'unassigned_by cannot impersonate another actor';
    end if;
    v_effective_actor:=v_actor;
  end if;

  if v_assignment.status='ended'::public.client_coach_assignment_status then
    return v_assignment.id;
  end if;

  select cp.user_id into v_coach_user_id
  from public.coach_profiles cp
  where cp.id=v_assignment.coach_id;

  select c.user_id into v_client_user_id
  from public.clients c
  where c.id=v_assignment.client_id;

  update public.client_coach_assignments
  set status='ended'::public.client_coach_assignment_status,
      unassigned_at=now(),
      unassigned_by=v_effective_actor
  where id=p_assignment_id;

  insert into public.organization_permission_audit(
    organization_id,target_user_id,actor_user_id,action,role,reason,payload
  )
  values(
    v_assignment.organization_id,v_coach_user_id,v_effective_actor,
    'coach_assignment_ended',
    'coach'::public.organization_member_role,
    'Client unassigned from coach',
    jsonb_build_object(
      'assignment_id',v_assignment.id,
      'client_id',v_assignment.client_id,
      'client_user_id',v_client_user_id
    )
  );

  return p_assignment_id;
end;
$function$;

revoke all on function public.set_coach_scope_capability_v1(uuid,uuid,boolean,text)
  from public,anon;
revoke all on function public.set_coach_profile_status_v1(
  uuid,uuid,public.coach_profile_status,text
) from public,anon;

grant execute on function public.set_coach_scope_capability_v1(uuid,uuid,boolean,text)
  to authenticated,service_role;
grant execute on function public.set_coach_profile_status_v1(
  uuid,uuid,public.coach_profile_status,text
) to authenticated,service_role;

comment on function private.coach_can_access_client_v1(uuid,uuid,uuid) is
'F1.M2.S6 COACH authority requires tenant COACH role + active coach_profile + active assignment or audited manage_all_clients capability.';
comment on function public.set_coach_scope_capability_v1(uuid,uuid,boolean,text) is
'F1.M2.S6 audited scope expansion/reduction. Coaches cannot self-elevate.';
