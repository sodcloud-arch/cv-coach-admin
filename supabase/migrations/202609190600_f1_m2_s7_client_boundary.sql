-- F1.M2.S7 — CLIENT tenant role, self-resource boundary and published-program visibility

create or replace function private.is_client_in_org_v1(
  p_organization_id uuid,
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    exists(
      select 1
      from public.organization_members om
      join public.clients c
        on c.organization_id=om.organization_id
       and c.user_id=om.user_id
      where om.organization_id=p_organization_id
        and om.user_id=p_user_id
        and om.status='active'::public.organization_member_status
        and c.status<>'archived'::public.client_status
        and private.member_has_org_role_v1(
          p_organization_id,p_user_id,'client'::public.organization_member_role
        )
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
            and private.is_client_in_org_v1(c.organization_id,auth.uid())
          )
          or private.coach_can_access_client_v1(
            c.organization_id,auth.uid(),c.user_id
          )
        )
    ),
    false
  )
$function$;

create or replace function private.can_view_client_in_org(
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
    auth.role()='service_role'
    or private.is_org_admin(target_organization)
    or (
      target_client_user=auth.uid()
      and private.is_client_in_org_v1(target_organization,auth.uid())
    )
    or private.coach_can_access_client_v1(
      target_organization,auth.uid(),target_client_user
    ),
    false
  )
$function$;

create or replace function private.can_view_program(target_program uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(exists(
    select 1
    from public.programs p
    where p.id=target_program
      and (
        private.can_manage_client_in_org(p.organization_id,p.client_id)
        or (
          p.client_id=auth.uid()
          and private.is_client_in_org_v1(p.organization_id,auth.uid())
          and p.published_at is not null
          and p.status in (
            'active'::public.program_status,
            'completed'::public.program_status
          )
        )
      )
  ),false)
$function$;

create or replace function private.can_view_program_day(target_day uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(exists(
    select 1
    from public.program_days d
    where d.id=target_day
      and private.can_view_program(d.program_id)
  ),false)
$function$;

create or replace function private.can_edit_workout_session(target_session uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(exists(
    select 1
    from public.workout_sessions ws
    where ws.id=target_session
      and (
        (
          ws.client_id=auth.uid()
          and private.is_client_in_org_v1(ws.organization_id,auth.uid())
        )
        or private.can_manage_client_in_org(ws.organization_id,ws.client_id)
      )
  ),false)
$function$;

create or replace function private.can_edit_session_exercise(target_session_exercise uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(exists(
    select 1
    from public.session_exercises se
    join public.workout_sessions ws
      on ws.organization_id=se.organization_id
     and ws.id=se.workout_session_id
    where se.id=target_session_exercise
      and (
        (
          ws.client_id=auth.uid()
          and private.is_client_in_org_v1(ws.organization_id,auth.uid())
        )
        or private.can_manage_client_in_org(ws.organization_id,ws.client_id)
      )
  ),false)
$function$;

-- Main program policy now delegates to the publication-aware helper.
drop policy if exists programs_select_v2 on public.programs;
create policy programs_select_v3
on public.programs
for select
to authenticated
using (private.can_view_program(id));

-- Client profile: direct onboarding writes remain limited to pre-approval,
-- and now require the explicit CLIENT tenant role.
drop policy if exists client_profiles_insert_self_v2 on public.client_profiles;
create policy client_profiles_insert_self_v3
on public.client_profiles
for insert
to authenticated
with check (
  client_id=auth.uid()
  and onboarding_status<>'approved'::public.onboarding_status
  and private.is_client_in_org_v1(organization_id,auth.uid())
);

drop policy if exists client_profiles_update_self_v2 on public.client_profiles;
create policy client_profiles_update_self_v3
on public.client_profiles
for update
to authenticated
using (
  client_id=auth.uid()
  and onboarding_status<>'approved'::public.onboarding_status
  and private.is_client_in_org_v1(organization_id,auth.uid())
)
with check (
  client_id=auth.uid()
  and onboarding_status<>'approved'::public.onboarding_status
  and private.is_client_in_org_v1(organization_id,auth.uid())
);

-- Safe post-onboarding self-profile mutation. Workflow/approval fields cannot be changed.
create or replace function public.update_client_self_profile_v1(
  p_organization_id uuid,
  p_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid:=auth.uid();
  v_patch jsonb:=coalesce(p_patch,'{}'::jsonb);
  v_profile public.client_profiles%rowtype;
  v_unknown text[];
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;

  if not private.is_client_in_org_v1(p_organization_id,v_uid) then
    raise exception 'Active CLIENT identity required in Organization';
  end if;

  if jsonb_typeof(v_patch)<>'object' then
    raise exception 'profile patch must be a JSON object';
  end if;

  select array_agg(k order by k)
  into v_unknown
  from jsonb_object_keys(v_patch) k
  where k not in (
    'birth_date','gender','height_cm',
    'current_weight_kg','timezone'
  );

  if coalesce(cardinality(v_unknown),0)>0 then
    raise exception 'unsupported self-profile fields: %',array_to_string(v_unknown,',');
  end if;

  select * into v_profile
  from public.client_profiles cp
  where cp.organization_id=p_organization_id
    and cp.client_id=v_uid
  for update;

  if not found then
    raise exception 'Client profile not found';
  end if;

  update public.client_profiles
  set
    birth_date=case
      when v_patch ? 'birth_date' then nullif(v_patch->>'birth_date','')::date
      else v_profile.birth_date
    end,
    gender=case
      when v_patch ? 'gender' then nullif(btrim(v_patch->>'gender'),'')
      else v_profile.gender
    end,
    height_cm=case
      when v_patch ? 'height_cm' then nullif(v_patch->>'height_cm','')::numeric
      else v_profile.height_cm
    end,
    current_weight_kg=case
      when v_patch ? 'current_weight_kg' then nullif(v_patch->>'current_weight_kg','')::numeric
      else v_profile.current_weight_kg
    end,
    timezone=case
      when v_patch ? 'timezone' then nullif(btrim(v_patch->>'timezone'),'')
      else v_profile.timezone
    end,
    updated_at=now()
  where organization_id=p_organization_id
    and client_id=v_uid
  returning * into v_profile;

  if v_profile.timezone is null or char_length(v_profile.timezone)>100 then
    raise exception 'invalid timezone';
  end if;

  return jsonb_build_object(
    'organization_id',v_profile.organization_id,
    'client_id',v_profile.client_id,
    'birth_date',v_profile.birth_date,
    'gender',v_profile.gender,
    'height_cm',v_profile.height_cm,
    'current_weight_kg',v_profile.current_weight_kg,
    'timezone',v_profile.timezone,
    'onboarding_status',v_profile.onboarding_status,
    'version','F1.M2.S7_CLIENT_SELF_PROFILE_V1'
  );
end;
$function$;

revoke all on function public.update_client_self_profile_v1(uuid,jsonb)
  from public,anon;
grant execute on function public.update_client_self_profile_v1(uuid,jsonb)
  to authenticated,service_role;

-- Replace generic member checks in direct self-service policies with CLIENT identity.

drop policy if exists client_training_preferences_select_v2
  on public.client_training_preferences;
create policy client_training_preferences_select_v3
on public.client_training_preferences
for select
to authenticated
using (
  (
    client_id=auth.uid()
    and private.is_client_in_org_v1(organization_id,auth.uid())
  )
  or private.can_manage_client_in_org(organization_id,client_id)
);

drop policy if exists client_training_schedule_preferences_select_v2
  on public.client_training_schedule_preferences;
create policy client_training_schedule_preferences_select_v3
on public.client_training_schedule_preferences
for select
to authenticated
using (
  (
    client_id=auth.uid()
    and private.is_client_in_org_v1(organization_id,auth.uid())
  )
  or private.can_manage_client_in_org(organization_id,client_id)
);

drop policy if exists coach_clients_select_v2 on public.coach_clients;
create policy coach_clients_select_v3
on public.coach_clients
for select
to authenticated
using (
  (
    client_id=auth.uid()
    and private.is_client_in_org_v1(organization_id,auth.uid())
  )
  or (
    coach_id=auth.uid()
    and private.actor_can_manage_client_in_org_v1(
      coach_id,organization_id,client_id
    )
  )
  or private.is_org_admin(organization_id)
);

drop policy if exists habit_logs_delete_v2 on public.habit_logs;
create policy habit_logs_delete_v3
on public.habit_logs
for delete
to authenticated
using (
  (
    client_id=auth.uid()
    and private.is_client_in_org_v1(organization_id,auth.uid())
  )
  or private.can_manage_client_in_org(organization_id,client_id)
);

drop policy if exists habit_logs_insert_v2 on public.habit_logs;
create policy habit_logs_insert_v3
on public.habit_logs
for insert
to authenticated
with check (
  private.client_habit_belongs_to_in_org(
    organization_id,client_habit_id,client_id
  )
  and (
    (
      client_id=auth.uid()
      and source='manual'::public.log_source
      and private.is_client_in_org_v1(organization_id,auth.uid())
    )
    or private.can_manage_client_in_org(organization_id,client_id)
  )
);

drop policy if exists habit_logs_update_v2 on public.habit_logs;
create policy habit_logs_update_v3
on public.habit_logs
for update
to authenticated
using (
  (
    client_id=auth.uid()
    and private.is_client_in_org_v1(organization_id,auth.uid())
  )
  or private.can_manage_client_in_org(organization_id,client_id)
)
with check (
  private.client_habit_belongs_to_in_org(
    organization_id,client_habit_id,client_id
  )
  and (
    (
      client_id=auth.uid()
      and source='manual'::public.log_source
      and private.is_client_in_org_v1(organization_id,auth.uid())
    )
    or private.can_manage_client_in_org(organization_id,client_id)
  )
);

drop policy if exists meal_logs_delete_v2 on public.meal_logs;
create policy meal_logs_delete_v3
on public.meal_logs
for delete
to authenticated
using (
  (
    client_id=auth.uid()
    and private.is_client_in_org_v1(organization_id,auth.uid())
  )
  or private.can_manage_client_in_org(organization_id,client_id)
);

drop policy if exists meal_logs_insert_v2 on public.meal_logs;
create policy meal_logs_insert_v3
on public.meal_logs
for insert
to authenticated
with check (
  (
    client_id=auth.uid()
    and private.is_client_in_org_v1(organization_id,auth.uid())
  )
  or private.can_manage_client_in_org(organization_id,client_id)
);

drop policy if exists meal_logs_update_v2 on public.meal_logs;
create policy meal_logs_update_v3
on public.meal_logs
for update
to authenticated
using (
  (
    client_id=auth.uid()
    and private.is_client_in_org_v1(organization_id,auth.uid())
  )
  or private.can_manage_client_in_org(organization_id,client_id)
)
with check (
  (
    client_id=auth.uid()
    and private.is_client_in_org_v1(organization_id,auth.uid())
  )
  or private.can_manage_client_in_org(organization_id,client_id)
);

drop policy if exists measurements_insert_v2 on public.measurements;
create policy measurements_insert_v3
on public.measurements
for insert
to authenticated
with check (
  (
    client_id=auth.uid()
    and source='manual'::public.log_source
    and private.is_client_in_org_v1(organization_id,auth.uid())
  )
  or private.can_manage_client_in_org(organization_id,client_id)
);

drop policy if exists measurements_update_v2 on public.measurements;
create policy measurements_update_v3
on public.measurements
for update
to authenticated
using (
  (
    client_id=auth.uid()
    and private.is_client_in_org_v1(organization_id,auth.uid())
  )
  or private.can_manage_client_in_org(organization_id,client_id)
)
with check (
  (
    client_id=auth.uid()
    and source='manual'::public.log_source
    and private.is_client_in_org_v1(organization_id,auth.uid())
  )
  or private.can_manage_client_in_org(organization_id,client_id)
);

drop policy if exists nutrition_daily_delete_v2
  on public.nutrition_daily_logs;
create policy nutrition_daily_delete_v3
on public.nutrition_daily_logs
for delete
to authenticated
using (
  (
    client_id=auth.uid()
    and private.is_client_in_org_v1(organization_id,auth.uid())
  )
  or private.can_manage_client_in_org(organization_id,client_id)
);

drop policy if exists nutrition_daily_insert_v2
  on public.nutrition_daily_logs;
create policy nutrition_daily_insert_v3
on public.nutrition_daily_logs
for insert
to authenticated
with check (
  (
    client_id=auth.uid()
    and source='manual'::public.log_source
    and private.is_client_in_org_v1(organization_id,auth.uid())
  )
  or private.can_manage_client_in_org(organization_id,client_id)
);

drop policy if exists nutrition_daily_update_v2
  on public.nutrition_daily_logs;
create policy nutrition_daily_update_v3
on public.nutrition_daily_logs
for update
to authenticated
using (
  (
    client_id=auth.uid()
    and private.is_client_in_org_v1(organization_id,auth.uid())
  )
  or private.can_manage_client_in_org(organization_id,client_id)
)
with check (
  (
    client_id=auth.uid()
    and source='manual'::public.log_source
    and private.is_client_in_org_v1(organization_id,auth.uid())
  )
  or private.can_manage_client_in_org(organization_id,client_id)
);

drop policy if exists onboarding_delete_self_v2
  on public.onboarding_responses;
create policy onboarding_delete_self_v3
on public.onboarding_responses
for delete
to authenticated
using (
  client_id=auth.uid()
  and private.is_client_in_org_v1(organization_id,auth.uid())
);

drop policy if exists onboarding_insert_self_v2
  on public.onboarding_responses;
create policy onboarding_insert_self_v3
on public.onboarding_responses
for insert
to authenticated
with check (
  client_id=auth.uid()
  and private.is_client_in_org_v1(organization_id,auth.uid())
);

drop policy if exists onboarding_update_self_v2
  on public.onboarding_responses;
create policy onboarding_update_self_v3
on public.onboarding_responses
for update
to authenticated
using (
  client_id=auth.uid()
  and private.is_client_in_org_v1(organization_id,auth.uid())
)
with check (
  client_id=auth.uid()
  and private.is_client_in_org_v1(organization_id,auth.uid())
);

drop policy if exists progress_photos_delete_v2 on public.progress_photos;
create policy progress_photos_delete_v3
on public.progress_photos
for delete
to authenticated
using (
  (
    client_id=auth.uid()
    and private.is_client_in_org_v1(organization_id,auth.uid())
  )
  or private.is_org_admin(organization_id)
);

drop policy if exists progress_photos_insert_v2 on public.progress_photos;
create policy progress_photos_insert_v3
on public.progress_photos
for insert
to authenticated
with check (
  (
    client_id=auth.uid()
    and private.is_client_in_org_v1(organization_id,auth.uid())
  )
  or private.can_manage_client_in_org(organization_id,client_id)
);

drop policy if exists progress_photos_select_v2 on public.progress_photos;
create policy progress_photos_select_v3
on public.progress_photos
for select
to authenticated
using (
  (
    client_id=auth.uid()
    and private.is_client_in_org_v1(organization_id,auth.uid())
  )
  or (
    visible_to_coach=true
    and private.can_manage_client_in_org(organization_id,client_id)
  )
  or private.is_org_admin(organization_id)
);

drop policy if exists progress_photos_update_v2 on public.progress_photos;
create policy progress_photos_update_v3
on public.progress_photos
for update
to authenticated
using (
  (
    client_id=auth.uid()
    and private.is_client_in_org_v1(organization_id,auth.uid())
  )
  or private.is_org_admin(organization_id)
)
with check (
  (
    client_id=auth.uid()
    and private.is_client_in_org_v1(organization_id,auth.uid())
  )
  or private.is_org_admin(organization_id)
);

drop policy if exists workout_sessions_insert_v2 on public.workout_sessions;
create policy workout_sessions_insert_v3
on public.workout_sessions
for insert
to authenticated
with check (
  (
    (
      client_id=auth.uid()
      and private.is_client_in_org_v1(organization_id,auth.uid())
    )
    or private.can_manage_client_in_org(organization_id,client_id)
  )
  and private.program_day_belongs_to_client(program_day_id,client_id)
);

drop policy if exists workout_sessions_update_v2 on public.workout_sessions;
create policy workout_sessions_update_v3
on public.workout_sessions
for update
to authenticated
using (
  (
    client_id=auth.uid()
    and private.is_client_in_org_v1(organization_id,auth.uid())
    and status<>'completed'::public.workout_session_status
  )
  or private.can_manage_client_in_org(organization_id,client_id)
)
with check (
  private.program_day_belongs_to_client(program_day_id,client_id)
  and (
    (
      client_id=auth.uid()
      and private.is_client_in_org_v1(organization_id,auth.uid())
      and status<>'completed'::public.workout_session_status
    )
    or private.can_manage_client_in_org(organization_id,client_id)
  )
);

-- ActiveOrganizationContext stays backward compatible with a primary role while
-- exposing the authoritative role set introduced by F1.M2.S5.
create or replace function public.resolve_active_organization_context_v1(
  p_selected_organization_id uuid default null::uuid,
  p_suggested_slug text default null::text
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_uid uuid:=auth.uid();
  v_profile public.profiles%rowtype;
  v_count integer:=0;
  v_options jsonb:='[]'::jsonb;
  v_resolution text;
  v_active jsonb:=null;
  v_slug text:=nullif(lower(btrim(coalesce(p_suggested_slug,''))),'');
  v_suggested_match uuid;
  v_selected_valid boolean:=false;

  v_active_org_id uuid;
  v_active_slug text;
  v_active_display_name text;
  v_active_org_status public.organization_status;
  v_active_role public.organization_member_role;
  v_active_roles public.organization_member_role[];
  v_active_locale text;
  v_active_timezone text;
  v_active_currency text;
  v_active_branding jsonb;
  v_active_flags jsonb;
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;

  select * into v_profile
  from public.profiles
  where id=v_uid
    and status='active'::public.profile_status;

  if not found then
    raise exception 'Active global profile required';
  end if;

  with eligible as (
    select
      om.organization_id,
      private.current_org_role_v1(om.organization_id,v_uid) as role,
      private.current_org_roles_v1(om.organization_id,v_uid) as roles,
      om.joined_at,
      o.slug,
      o.display_name,
      o.status,
      o.locale,
      o.timezone,
      o.currency,
      o.branding_config,
      o.feature_flags
    from public.organization_members om
    join public.organizations o on o.id=om.organization_id
    where om.user_id=v_uid
      and om.status='active'::public.organization_member_status
      and o.status in (
        'trial'::public.organization_status,
        'active'::public.organization_status
      )
  )
  select
    count(*)::integer,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'organization_id',organization_id,
          'slug',slug,
          'display_name',display_name,
          'organization_status',status,
          'role',role,
          'roles',to_jsonb(roles),
          'joined_at',joined_at,
          'locale',locale,
          'timezone',timezone,
          'currency',currency,
          'branding_config',branding_config,
          'feature_flags',feature_flags
        )
        order by lower(display_name),organization_id
      ),
      '[]'::jsonb
    )
  into v_count,v_options
  from eligible;

  if v_slug is not null then
    select om.organization_id into v_suggested_match
    from public.organization_members om
    join public.organizations o on o.id=om.organization_id
    where om.user_id=v_uid
      and om.status='active'::public.organization_member_status
      and o.status in (
        'trial'::public.organization_status,
        'active'::public.organization_status
      )
      and lower(o.slug)=v_slug
    limit 1;
  end if;

  if p_selected_organization_id is not null then
    select
      o.id,o.slug,o.display_name,o.status,
      private.current_org_role_v1(o.id,v_uid),
      private.current_org_roles_v1(o.id,v_uid),
      o.locale,o.timezone,o.currency,o.branding_config,o.feature_flags
    into
      v_active_org_id,v_active_slug,v_active_display_name,v_active_org_status,
      v_active_role,v_active_roles,
      v_active_locale,v_active_timezone,v_active_currency,
      v_active_branding,v_active_flags
    from public.organization_members om
    join public.organizations o on o.id=om.organization_id
    where om.user_id=v_uid
      and om.organization_id=p_selected_organization_id
      and om.status='active'::public.organization_member_status
      and o.status in (
        'trial'::public.organization_status,
        'active'::public.organization_status
      )
    limit 1;

    v_selected_valid:=found;
  end if;

  if v_count=0 then
    v_resolution:='no_membership';
    v_active_org_id:=null;
  elsif v_count=1 then
    select
      o.id,o.slug,o.display_name,o.status,
      private.current_org_role_v1(o.id,v_uid),
      private.current_org_roles_v1(o.id,v_uid),
      o.locale,o.timezone,o.currency,o.branding_config,o.feature_flags
    into
      v_active_org_id,v_active_slug,v_active_display_name,v_active_org_status,
      v_active_role,v_active_roles,
      v_active_locale,v_active_timezone,v_active_currency,
      v_active_branding,v_active_flags
    from public.organization_members om
    join public.organizations o on o.id=om.organization_id
    where om.user_id=v_uid
      and om.status='active'::public.organization_member_status
      and o.status in (
        'trial'::public.organization_status,
        'active'::public.organization_status
      )
    limit 1;

    v_resolution:='auto_selected';
  elsif v_selected_valid then
    v_resolution:='selected';
  else
    v_resolution:='selection_required';
    v_active_org_id:=null;
  end if;

  if v_active_org_id is not null then
    v_active:=jsonb_build_object(
      'organization_id',v_active_org_id,
      'slug',v_active_slug,
      'display_name',v_active_display_name,
      'organization_status',v_active_org_status,
      'role',v_active_role,
      'roles',to_jsonb(coalesce(
        v_active_roles,array[]::public.organization_member_role[]
      )),
      'locale',v_active_locale,
      'timezone',v_active_timezone,
      'currency',v_active_currency,
      'branding_config',v_active_branding,
      'feature_flags',v_active_flags
    );
  end if;

  return jsonb_build_object(
    'ok',true,
    'actor',jsonb_build_object(
      'user_id',v_uid,
      'global_role',v_profile.role,
      'profile_status',v_profile.status
    ),
    'resolution',v_resolution,
    'membership_count',v_count,
    'memberships',v_options,
    'active_organization',v_active,
    'selected_organization_id',p_selected_organization_id,
    'selected_organization_valid',v_selected_valid,
    'suggested_slug',v_slug,
    'suggested_match_organization_id',v_suggested_match,
    'suggested_slug_authoritative',false,
    'next_action',case
      when v_resolution='no_membership' then 'await_invitation_or_onboarding'
      when v_resolution='selection_required' then 'select_organization'
      else 'enter_tenant'
    end,
    'version','F1.M2.S7_ACTIVE_ORG_ROLES_V1'
  );
end;
$function$;

comment on function private.is_client_in_org_v1(uuid,uuid) is
'F1.M2.S7 CLIENT authority requires active membership + CLIENT role + canonical non-archived client identity in the same Organization.';
comment on function public.update_client_self_profile_v1(uuid,jsonb) is
'F1.M2.S7 safe self-profile mutation; onboarding workflow and authorization fields are not client-editable.';
