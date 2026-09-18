-- ARCH-1.0 · F1.M1.S5 Wave H1 — Communications tenant isolation

alter table public.communication_preferences add column if not exists organization_id uuid;
alter table public.communication_drafts add column if not exists organization_id uuid;
alter table private.adherence_followup_events_v98 add column if not exists organization_id uuid;

-- Tables are empty at cutover; enforce tenant identity immediately.
alter table public.communication_preferences alter column organization_id set not null;
alter table public.communication_drafts alter column organization_id set not null;
alter table private.adherence_followup_events_v98 alter column organization_id set not null;

alter table public.communication_preferences drop constraint if exists communication_preferences_pkey;
alter table public.communication_preferences
  add constraint communication_preferences_pkey primary key(organization_id,client_id);

alter table public.communication_drafts drop constraint if exists communication_drafts_idempotency_key_key;
create unique index if not exists uq_communication_drafts_org_idempotency
  on public.communication_drafts(organization_id,idempotency_key);
create unique index if not exists ux_communication_drafts_org_id_client
  on public.communication_drafts(organization_id,id,client_id);

do $$
begin
  if not exists(select 1 from pg_constraint where conname='communication_preferences_organization_id_fkey') then
    alter table public.communication_preferences add constraint communication_preferences_organization_id_fkey
      foreign key(organization_id) references public.organizations(id) on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='communication_preferences_client_same_org') then
    alter table public.communication_preferences add constraint communication_preferences_client_same_org
      foreign key(organization_id,client_id) references public.clients(organization_id,user_id) on delete cascade;
  end if;
  if not exists(select 1 from pg_constraint where conname='communication_preferences_updated_by_member_same_org') then
    alter table public.communication_preferences add constraint communication_preferences_updated_by_member_same_org
      foreign key(organization_id,updated_by) references public.organization_members(organization_id,user_id) on delete restrict;
  end if;

  if not exists(select 1 from pg_constraint where conname='communication_drafts_organization_id_fkey') then
    alter table public.communication_drafts add constraint communication_drafts_organization_id_fkey
      foreign key(organization_id) references public.organizations(id) on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='communication_drafts_client_same_org') then
    alter table public.communication_drafts add constraint communication_drafts_client_same_org
      foreign key(organization_id,client_id) references public.clients(organization_id,user_id) on delete cascade;
  end if;
  if not exists(select 1 from pg_constraint where conname='communication_drafts_created_by_member_same_org') then
    alter table public.communication_drafts add constraint communication_drafts_created_by_member_same_org
      foreign key(organization_id,created_by) references public.organization_members(organization_id,user_id) on delete restrict;
  end if;

  if not exists(select 1 from pg_constraint where conname='adherence_followup_events_v98_organization_id_fkey') then
    alter table private.adherence_followup_events_v98 add constraint adherence_followup_events_v98_organization_id_fkey
      foreign key(organization_id) references public.organizations(id) on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='adherence_followup_events_v98_client_same_org') then
    alter table private.adherence_followup_events_v98 add constraint adherence_followup_events_v98_client_same_org
      foreign key(organization_id,client_id) references public.clients(organization_id,user_id) on delete cascade;
  end if;
  if not exists(select 1 from pg_constraint where conname='adherence_followup_events_v98_actor_member_same_org') then
    alter table private.adherence_followup_events_v98 add constraint adherence_followup_events_v98_actor_member_same_org
      foreign key(organization_id,actor_id) references public.organization_members(organization_id,user_id) on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='adherence_followup_events_v98_draft_same_org_client') then
    alter table private.adherence_followup_events_v98 add constraint adherence_followup_events_v98_draft_same_org_client
      foreign key(organization_id,draft_id,client_id) references public.communication_drafts(organization_id,id,client_id) on delete cascade;
  end if;
end $$;

create index if not exists ix_communication_preferences_org_client
  on public.communication_preferences(organization_id,client_id);
create index if not exists ix_communication_drafts_org_client_created
  on public.communication_drafts(organization_id,client_id,created_at desc);
create index if not exists ix_adherence_followup_org_actor_client
  on private.adherence_followup_events_v98(organization_id,actor_id,client_id,created_at desc);

drop policy if exists communication_preferences_delete on public.communication_preferences;
drop policy if exists communication_preferences_insert on public.communication_preferences;
drop policy if exists communication_preferences_select on public.communication_preferences;
drop policy if exists communication_preferences_update on public.communication_preferences;

create policy communication_preferences_select_v2 on public.communication_preferences for select to authenticated
using(private.can_manage_client_in_org(organization_id,client_id));
create policy communication_preferences_insert_v2 on public.communication_preferences for insert to authenticated
with check(private.can_manage_client_in_org(organization_id,client_id));
create policy communication_preferences_update_v2 on public.communication_preferences for update to authenticated
using(private.can_manage_client_in_org(organization_id,client_id))
with check(private.can_manage_client_in_org(organization_id,client_id));
create policy communication_preferences_delete_v2 on public.communication_preferences for delete to authenticated
using(private.is_org_admin(organization_id));

drop policy if exists communication_drafts_delete on public.communication_drafts;
drop policy if exists communication_drafts_insert on public.communication_drafts;
drop policy if exists communication_drafts_select on public.communication_drafts;
drop policy if exists communication_drafts_update on public.communication_drafts;

create policy communication_drafts_select_v2 on public.communication_drafts for select to authenticated
using(private.can_manage_client_in_org(organization_id,client_id));
create policy communication_drafts_insert_v2 on public.communication_drafts for insert to authenticated
with check(private.can_manage_client_in_org(organization_id,client_id) and created_by=auth.uid());
create policy communication_drafts_update_v2 on public.communication_drafts for update to authenticated
using(private.can_manage_client_in_org(organization_id,client_id))
with check(private.can_manage_client_in_org(organization_id,client_id));
create policy communication_drafts_delete_v2 on public.communication_drafts for delete to authenticated
using(private.is_org_admin(organization_id));

revoke truncate,trigger,references on table public.communication_preferences from public,anon,authenticated;
revoke truncate,trigger,references on table public.communication_drafts from public,anon,authenticated;

create or replace function private.set_whatsapp_communication_preference_in_org(
  p_organization_id uuid,
  p_actor_id uuid,
  p_client_id uuid,
  p_phone_e164 text,
  p_opt_in boolean,
  p_consent_source text,
  p_consent_note text default null,
  p_quiet_hours_start time default time '21:00',
  p_quiet_hours_end time default time '08:00'
)
returns public.communication_preferences
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_row public.communication_preferences;
  v_phone text:=nullif(btrim(coalesce(p_phone_e164,'')),'');
  v_source text:=nullif(btrim(coalesce(p_consent_source,'')),'');
begin
  if p_actor_id is null then raise exception 'actor is required'; end if;
  if not private.actor_can_manage_client_in_org_v1(p_actor_id,p_organization_id,p_client_id) then
    raise exception 'Not authorized to manage this client in organization';
  end if;
  if v_phone is not null and v_phone !~ '^\\+[1-9][0-9]{7,14}$' then
    raise exception 'WhatsApp phone must be valid E.164';
  end if;
  if p_opt_in and (v_phone is null or v_source is null) then
    raise exception 'Opt-in requires E.164 phone and consent source';
  end if;
  if char_length(coalesce(p_consent_note,''))>500 then
    raise exception 'Consent note too long';
  end if;

  insert into public.communication_preferences(
    organization_id,client_id,whatsapp_phone_e164,whatsapp_opt_in,
    whatsapp_opt_in_at,whatsapp_opt_out_at,consent_source,consent_note,
    quiet_hours_start,quiet_hours_end,timezone,updated_by
  )
  values(
    p_organization_id,p_client_id,v_phone,p_opt_in,
    case when p_opt_in then now() else null end,
    case when p_opt_in then null else now() end,
    v_source,nullif(btrim(coalesce(p_consent_note,'')),''),
    coalesce(p_quiet_hours_start,time '21:00'),
    coalesce(p_quiet_hours_end,time '08:00'),
    coalesce(
      (
        select cp.timezone from public.client_profiles cp
        where cp.organization_id=p_organization_id and cp.client_id=p_client_id
      ),
      'America/Santiago'
    ),
    p_actor_id
  )
  on conflict(organization_id,client_id) do update set
    whatsapp_phone_e164=excluded.whatsapp_phone_e164,
    whatsapp_opt_in=excluded.whatsapp_opt_in,
    whatsapp_opt_in_at=case
      when excluded.whatsapp_opt_in and not public.communication_preferences.whatsapp_opt_in then now()
      when excluded.whatsapp_opt_in then coalesce(public.communication_preferences.whatsapp_opt_in_at,now())
      else public.communication_preferences.whatsapp_opt_in_at
    end,
    whatsapp_opt_out_at=case when excluded.whatsapp_opt_in then null else now() end,
    consent_source=excluded.consent_source,
    consent_note=excluded.consent_note,
    quiet_hours_start=excluded.quiet_hours_start,
    quiet_hours_end=excluded.quiet_hours_end,
    timezone=excluded.timezone,
    updated_by=p_actor_id
  returning * into v_row;
  return v_row;
end;
$function$;

create or replace function public.set_whatsapp_communication_preference(
  p_client_id uuid,
  p_phone_e164 text,
  p_opt_in boolean,
  p_consent_source text,
  p_consent_note text default null,
  p_quiet_hours_start time default time '21:00',
  p_quiet_hours_end time default time '08:00'
)
returns public.communication_preferences
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_org uuid;
begin
  v_org:=private.resolve_legacy_client_organization_v1(p_client_id,null);
  return private.set_whatsapp_communication_preference_in_org(
    v_org,auth.uid(),p_client_id,p_phone_e164,p_opt_in,p_consent_source,
    p_consent_note,p_quiet_hours_start,p_quiet_hours_end
  );
end;
$function$;

create or replace function private.prepare_communication_draft_in_org(
  p_organization_id uuid,
  p_client_id uuid,
  p_message_type text,
  p_body text,
  p_idempotency_key text,
  p_source text default 'admin',
  p_source_ref text default null
)
returns public.communication_drafts
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_pref public.communication_preferences;
  v_row public.communication_drafts;
  v_status text;
  v_reason text;
  v_body text:=btrim(coalesce(p_body,''));
  v_key text:=btrim(coalesce(p_idempotency_key,''));
  v_source text:=btrim(coalesce(p_source,'admin'));
  v_actor uuid:=auth.uid();
begin
  if v_actor is null or not private.actor_can_manage_client_in_org_v1(v_actor,p_organization_id,p_client_id) then
    raise exception 'Not authorized to manage this client in organization';
  end if;
  if p_message_type not in ('retention_followup','workout_reminder','onboarding','payment_reminder','general') then
    raise exception 'Invalid message type';
  end if;
  if char_length(v_body) not between 1 and 4000 then raise exception 'Message body must contain 1 to 4000 characters'; end if;
  if char_length(v_key) not between 8 and 240 then raise exception 'Invalid idempotency key'; end if;
  if char_length(v_source) not between 1 and 80 then raise exception 'Invalid source'; end if;

  select * into v_pref
  from public.communication_preferences
  where organization_id=p_organization_id and client_id=p_client_id;

  if v_pref.client_id is null then
    v_status:='blocked'; v_reason:='WhatsApp consent has not been recorded.';
  elsif not v_pref.whatsapp_opt_in then
    v_status:='blocked'; v_reason:='WhatsApp opt-in is not active.';
  elsif v_pref.whatsapp_phone_e164 is null or v_pref.whatsapp_phone_e164 !~ '^\\+[1-9][0-9]{7,14}$' then
    v_status:='blocked'; v_reason:='A valid E.164 WhatsApp phone is required.';
  else
    v_status:='ready'; v_reason:=null;
  end if;

  insert into public.communication_drafts(
    organization_id,client_id,channel,message_type,body,status,
    blocked_reason,source,source_ref,idempotency_key,created_by
  )
  values(
    p_organization_id,p_client_id,'whatsapp',p_message_type,v_body,v_status,
    v_reason,v_source,nullif(btrim(coalesce(p_source_ref,'')),''),
    v_key,v_actor
  )
  on conflict(organization_id,idempotency_key) do nothing
  returning * into v_row;

  if v_row.id is null then
    select * into v_row
    from public.communication_drafts
    where organization_id=p_organization_id and idempotency_key=v_key;
    if v_row.client_id is distinct from p_client_id then
      raise exception 'Idempotency key already belongs to another client in organization';
    end if;
  end if;
  return v_row;
end;
$function$;

create or replace function public.prepare_communication_draft(
  p_client_id uuid,
  p_message_type text,
  p_body text,
  p_idempotency_key text,
  p_source text default 'admin',
  p_source_ref text default null
)
returns public.communication_drafts
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_org uuid;
begin
  v_org:=private.resolve_legacy_client_organization_v1(p_client_id,null);
  return private.prepare_communication_draft_in_org(
    v_org,p_client_id,p_message_type,p_body,p_idempotency_key,p_source,p_source_ref
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.communication_delivery_preflight(p_draft_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_draft public.communication_drafts;
  v_pref public.communication_preferences;
  v_config public.communication_provider_config;
  v_local_time time;
  v_in_quiet boolean := false;
  v_reasons text[] := array[]::text[];
  v_eligible boolean := true;
begin
  select * into v_draft from public.communication_drafts where id=p_draft_id;
  if v_draft.id is null then raise exception 'Draft not found'; end if;
  if not private.can_manage_client_in_org(v_draft.organization_id,v_draft.client_id) then raise exception 'Not authorized to view this draft'; end if;

  select * into v_pref from public.communication_preferences where organization_id=v_draft.organization_id and client_id=v_draft.client_id;
  select * into v_config from public.communication_provider_config where brand_scope='CV_COACH';

  if v_draft.status <> 'ready' then
    v_eligible:=false; v_reasons:=array_append(v_reasons,'DRAFT_NOT_READY');
  end if;
  if v_pref.client_id is null or not coalesce(v_pref.whatsapp_opt_in,false) then
    v_eligible:=false; v_reasons:=array_append(v_reasons,'WHATSAPP_OPT_IN_REQUIRED');
  end if;
  if v_pref.whatsapp_phone_e164 is null or v_pref.whatsapp_phone_e164 !~ '^\+[1-9][0-9]{7,14}$' then
    v_eligible:=false; v_reasons:=array_append(v_reasons,'VALID_E164_REQUIRED');
  end if;

  if v_pref.client_id is not null then
    begin
      v_local_time := (now() at time zone coalesce(nullif(v_pref.timezone,''),'America/Santiago'))::time;
    exception when others then
      v_local_time := (now() at time zone 'America/Santiago')::time;
      v_reasons:=array_append(v_reasons,'INVALID_TIMEZONE_FALLBACK_CHILE');
    end;
    if v_pref.quiet_hours_start = v_pref.quiet_hours_end then
      v_in_quiet := true;
    elsif v_pref.quiet_hours_start < v_pref.quiet_hours_end then
      v_in_quiet := v_local_time >= v_pref.quiet_hours_start and v_local_time < v_pref.quiet_hours_end;
    else
      v_in_quiet := v_local_time >= v_pref.quiet_hours_start or v_local_time < v_pref.quiet_hours_end;
    end if;
    if v_in_quiet then
      v_eligible:=false; v_reasons:=array_append(v_reasons,'QUIET_HOURS_ACTIVE');
    end if;
  end if;

  if v_config.brand_scope is null or v_config.status <> 'active' then
    v_eligible:=false; v_reasons:=array_append(v_reasons,'CV_COACH_PROVIDER_NOT_ASSIGNED');
  end if;
  if v_config.business_phone_wa_id is null or v_config.whatsapp_business_account_id is null then
    v_eligible:=false; v_reasons:=array_append(v_reasons,'DEDICATED_PROVIDER_IDENTITY_REQUIRED');
  end if;
  if not coalesce(v_config.dispatch_enabled,false) then
    v_eligible:=false; v_reasons:=array_append(v_reasons,'PROVIDER_DISPATCH_DISABLED');
  end if;

  return jsonb_build_object(
    'draft_id',v_draft.id,
    'organization_id',v_draft.organization_id,
    'client_id',v_draft.client_id,
    'draft_status',v_draft.status,
    'provider',coalesce(v_config.provider,'peach'),
    'provider_status',coalesce(v_config.status,'unassigned'),
    'dispatch_enabled',coalesce(v_config.dispatch_enabled,false),
    'whatsapp_opt_in',coalesce(v_pref.whatsapp_opt_in,false),
    'phone_ready',(v_pref.whatsapp_phone_e164 is not null and v_pref.whatsapp_phone_e164 ~ '^\+[1-9][0-9]{7,14}$'),
    'quiet_hours_active',v_in_quiet,
    'timezone',coalesce(v_pref.timezone,'America/Santiago'),
    'eligible_for_provider_dispatch',v_eligible,
    'reasons',to_jsonb(v_reasons),
    'provider_window_check_required',true,
    'approved_template_or_open_24h_session_required',true,
    'note','Preflight only. This function never sends a WhatsApp message.'
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_adherence_communication_center_v98(p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_organization uuid; v_base jsonb; v_items jsonb; v_strategy_catalog jsonb; v_provider public.communication_provider_config; v_summary jsonb;
begin
v_organization:=private.resolve_legacy_professional_organization_v1(p_actor_id,null);
if not private.cv_is_coach_admin_in_org_v62(v_organization,p_actor_id) then
  raise exception 'Not authorized in organization';
end if;
v_base:=public.get_coach_ai_command_center_v94(p_actor_id); select * into v_provider from public.communication_provider_config where brand_scope='CV_COACH';
with base_items as (select x.item,(x.item->>'client_id')::uuid client_id,nullif(x.item#>>'{training,days_since_workout}','')::int coach_ai_days_since_workout,coalesce(x.item#>>'{training,risk_level}','GREEN') risk_level,coalesce(x.item#>>'{lifecycle,stage}','') lifecycle_stage from jsonb_array_elements(coalesce(v_base->'items','[]'::jsonb)) x(item)
  where exists(
    select 1 from public.clients c
    where c.organization_id=v_organization
      and c.user_id=(x.item->>'client_id')::uuid
      and c.status<>'archived'::public.client_status
  )),
prepared0 as (select b.*,cp.whatsapp_opt_in,cp.whatsapp_phone_e164,cp.quiet_hours_start,cp.quiet_hours_end,cp.timezone,ls.last_workout_at,case when ls.last_workout_at is null then null else greatest(0,floor(extract(epoch from (now()-ls.last_workout_at))/86400.0)::int) end days_since_workout,le.id last_event_id,le.draft_id last_draft_id,le.strategy_code last_strategy_code,le.contacted_at last_contacted_at,le.outcome_status last_outcome_status,le.returned_at last_returned_at,le.days_to_return last_days_to_return from base_items b left join public.communication_preferences cp on cp.organization_id=v_organization and cp.client_id=b.client_id left join lateral (select coalesce(ws.finished_at,ws.started_at,ws.created_at) last_workout_at from public.workout_sessions ws where ws.organization_id=v_organization and ws.client_id=b.client_id and ws.status in ('completed','partial') and coalesce(ws.finished_at,ws.started_at,ws.created_at)<=now() order by coalesce(ws.finished_at,ws.started_at,ws.created_at) desc limit 1) ls on true left join lateral (select e.* from private.adherence_followup_events_v98 e where e.organization_id=v_organization and e.actor_id=p_actor_id and e.client_id=b.client_id order by e.created_at desc,e.id desc limit 1) le on true),
prepared as (select p.*,case when p.days_since_workout between 7 and 13 then 'supportive_nudge' when p.days_since_workout between 14 and 20 then 'barrier_checkin' when p.days_since_workout>=21 then 'reactivation_reset' else null end strategy_code from prepared0 p),
scored as (select p.*,(p.days_since_workout is not null and p.days_since_workout>=7 and p.lifecycle_stage='operational' and upper(coalesce(p.risk_level,'GREEN'))<>'RED' and coalesce(p.item->>'primary_domain','')<>'SAFETY' and (p.last_contacted_at is null or p.last_contacted_at<=now()-interval '5 days')) followup_recommended,case when p.days_since_workout between 7 and 13 then 55 when p.days_since_workout between 14 and 20 then 75 when p.days_since_workout>=21 then 90 else 0 end adherence_contact_score from prepared p),
enriched as (select s.*,case when not s.followup_recommended then 'NOT_RECOMMENDED' when not coalesce(s.whatsapp_opt_in,false) then 'CONSENT_REQUIRED' when s.whatsapp_phone_e164 is null or s.whatsapp_phone_e164 !~ '^\+[1-9][0-9]{7,14}$' then 'PHONE_REQUIRED' else 'DRAFT_READY' end readiness,case s.strategy_code when 'supportive_nudge' then 'Hola '||split_part(coalesce(nullif(s.item->>'client_name',''),'Cliente'),' ',1)||' 👋 Han pasado '||s.days_since_workout||' días desde tu última sesión. ¿Cómo te has sentido esta semana? Si hubo algo que te frenó, cuéntame y ajustamos el plan para que puedas retomarlo de forma realista. — Camilo' when 'barrier_checkin' then 'Hola '||split_part(coalesce(nullif(s.item->>'client_name',''),'Cliente'),' ',1)||' 👋 Llevamos '||s.days_since_workout||' días sin una sesión registrada. Antes de simplemente empujarte a volver, quiero saber qué se interpuso: tiempo, energía, molestias, motivación u otra cosa. Respóndeme y ajustamos el plan para que vuelva a ser sostenible. — Camilo' when 'reactivation_reset' then 'Hola '||split_part(coalesce(nullif(s.item->>'client_name',''),'Cliente'),' ',1)||' 👋 Ya han pasado '||s.days_since_workout||' días desde tu última sesión. En vez de intentar recuperar todo de golpe, podemos reiniciar con una versión más simple esta semana. Cuéntame cómo estás hoy y te ayudo a retomar con un objetivo pequeño y concreto. — Camilo' else null end proposed_message from scored s)
select coalesce(jsonb_agg(jsonb_build_object('client_id',e.client_id,'client_name',e.item->>'client_name','email',e.item->>'email','primary_goal',e.item->>'primary_goal','coach_ai_priority',e.item->>'priority','coach_ai_domain',e.item->>'primary_domain','coach_ai_action_code',e.item->>'recommended_action_code','coach_ai_days_since_workout',e.coach_ai_days_since_workout,'days_since_workout',e.days_since_workout,'last_workout_at',e.last_workout_at,'adherence_clock','completed_or_partial_only','risk_level',e.risk_level,'lifecycle_stage',e.lifecycle_stage,'followup_recommended',e.followup_recommended,'adherence_contact_score',e.adherence_contact_score,'strategy_code',e.strategy_code,'readiness',e.readiness,'proposed_message',e.proposed_message,'communication',jsonb_build_object('whatsapp_opt_in',coalesce(e.whatsapp_opt_in,false),'phone_ready',(e.whatsapp_phone_e164 is not null and e.whatsapp_phone_e164 ~ '^\+[1-9][0-9]{7,14}$'),'timezone',coalesce(e.timezone,'America/Santiago'),'quiet_hours_start',e.quiet_hours_start,'quiet_hours_end',e.quiet_hours_end,'provider',coalesce(v_provider.provider,'peach'),'provider_status',coalesce(v_provider.status,'unassigned'),'provider_dispatch_enabled',coalesce(v_provider.dispatch_enabled,false),'auto_dispatch',false),'last_followup',case when e.last_event_id is null then null else jsonb_build_object('event_id',e.last_event_id,'draft_id',e.last_draft_id,'strategy_code',e.last_strategy_code,'contacted_at',e.last_contacted_at,'outcome_status',e.last_outcome_status,'returned_at',e.last_returned_at,'days_to_return',e.last_days_to_return) end,'guardrails',jsonb_build_object('coach_approval_required',true,'draft_creation_is_not_contact',true,'manual_contact_confirmation_required',true,'auto_send',false,'provider_dispatch_mutation',false,'red_safety_contact_suppressed',true,'abandoned_sessions_do_not_reset_adherence_clock',true,'outcome_is_association_not_causality',true)) order by e.followup_recommended desc,e.adherence_contact_score desc,lower(coalesce(e.item->>'client_name',''))),'[]'::jsonb) into v_items from enriched e;
with resolved as (select strategy_code,count(*)::int sample_size,count(*) filter(where outcome_status='RETURNED')::int returned,count(*) filter(where outcome_status='NO_RETURN')::int no_return,round(avg(days_to_return) filter(where outcome_status='RETURNED')::numeric,2) avg_days_to_return,round(avg(effectiveness_score) filter(where effectiveness_score is not null)::numeric,1) avg_effectiveness,round(avg(confidence) filter(where confidence is not null)::numeric,3) avg_confidence from private.adherence_followup_events_v98 where organization_id=v_organization and actor_id=p_actor_id and contacted_at is not null and outcome_status in ('RETURNED','NO_RETURN') group by strategy_code) select coalesce(jsonb_agg(jsonb_build_object('strategy_code',r.strategy_code,'sample_size',r.sample_size,'returned',r.returned,'no_return',r.no_return,'return_rate',round(r.returned::numeric/nullif(r.sample_size,0),3),'avg_days_to_return',r.avg_days_to_return,'avg_effectiveness',r.avg_effectiveness,'avg_confidence',r.avg_confidence,'learning_ready',r.sample_size>=3) order by r.sample_size desc,r.strategy_code),'[]'::jsonb) into v_strategy_catalog from resolved r;
with x as (select value j from jsonb_array_elements(v_items)) select jsonb_build_object('total_clients',count(*),'followup_recommended',count(*) filter(where coalesce((j->>'followup_recommended')::boolean,false)),'draft_ready',count(*) filter(where j->>'readiness'='DRAFT_READY'),'consent_required',count(*) filter(where j->>'readiness'='CONSENT_REQUIRED'),'phone_required',count(*) filter(where j->>'readiness'='PHONE_REQUIRED'),'provider_dispatch_enabled',coalesce(v_provider.dispatch_enabled,false),'resolved_followups',(select count(*) from private.adherence_followup_events_v98 e where e.organization_id=v_organization and e.actor_id=p_actor_id and e.outcome_status in ('RETURNED','NO_RETURN')),'waiting_outcomes',(select count(*) from private.adherence_followup_events_v98 e where e.organization_id=v_organization and e.actor_id=p_actor_id and e.outcome_status in ('CONTACTED','WAITING_EVIDENCE'))) into v_summary from x;
return jsonb_build_object('version','COMMUNICATIONS_ADHERENCE_INTELLIGENCE_V98_2','organization_id',v_organization,'items',v_items,'summary',v_summary,'strategy_catalog',v_strategy_catalog,'provider',jsonb_build_object('provider',coalesce(v_provider.provider,'peach'),'status',coalesce(v_provider.status,'unassigned'),'dispatch_enabled',coalesce(v_provider.dispatch_enabled,false)),'guardrails',jsonb_build_object('coach_approval_required',true,'auto_send',false,'draft_is_not_contact',true,'manual_contact_confirmation_required',true,'outcome_window_days',7,'strategy_learning_sample_gate',3,'meaningful_workout_statuses',jsonb_build_array('completed','partial'),'abandoned_sessions_reset_clock',false,'outcome_is_association_not_causality',true,'safety_red_suppressed',true));
end;$function$;

CREATE OR REPLACE FUNCTION public.prepare_adherence_followup_v98(p_actor_id uuid, p_client_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_organization uuid; v_center jsonb; v_item jsonb; v_body text; v_strategy text; v_type text; v_key text; v_draft public.communication_drafts; v_event private.adherence_followup_events_v98; v_last_workout timestamptz; v_preflight jsonb;
begin
  if auth.uid() is null or p_actor_id is null or auth.uid()<>p_actor_id then raise exception 'Authenticated actor mismatch'; end if;
  v_organization:=private.resolve_legacy_professional_organization_v1(p_actor_id,p_client_id);
  if not private.actor_can_manage_client_in_org_v1(p_actor_id,v_organization,p_client_id) then raise exception 'Not authorized in organization'; end if;
  v_center := public.get_adherence_communication_center_v98(p_actor_id);
  select x into v_item from jsonb_array_elements(coalesce(v_center->'items','[]'::jsonb)) x where x->>'client_id'=p_client_id::text limit 1;
  if v_item is null then raise exception 'Client not available in V98 scope'; end if;
  if not coalesce((v_item->>'followup_recommended')::boolean,false) then raise exception 'Adherence follow-up is not currently recommended'; end if;
  if coalesce(v_item->>'readiness','')<>'DRAFT_READY' then raise exception 'Communication draft is blocked: %',coalesce(v_item->>'readiness','UNKNOWN'); end if;
  v_body:=v_item->>'proposed_message'; v_strategy:=v_item->>'strategy_code'; v_type:=case when coalesce(nullif(v_item->>'days_since_workout','')::int,0)>=14 then 'retention_followup' else 'workout_reminder' end;
  v_key:='v98:'||v_organization::text||':'||p_actor_id::text||':'||p_client_id::text||':'||v_strategy||':'||to_char(now() at time zone 'UTC','YYYYMMDD');
  v_draft:=private.prepare_communication_draft_in_org(v_organization,p_client_id,v_type,v_body,v_key,'v98_adherence',v_strategy);
  select coalesce(ws.finished_at,ws.started_at,ws.created_at) into v_last_workout from public.workout_sessions ws where ws.organization_id=v_organization and ws.client_id=p_client_id and ws.status in ('completed','partial') order by coalesce(ws.finished_at,ws.started_at,ws.created_at) desc limit 1;
  insert into private.adherence_followup_events_v98(organization_id,actor_id,client_id,draft_id,strategy_code,trigger_days_since_workout,baseline_last_workout_at,metadata) values (v_organization,p_actor_id,p_client_id,v_draft.id,v_strategy,nullif(v_item->>'days_since_workout','')::int,v_last_workout,jsonb_build_object('coach_ai_priority',v_item->>'coach_ai_priority','coach_ai_domain',v_item->>'coach_ai_domain','source','V98')) on conflict (draft_id) do update set updated_at=now() returning * into v_event;
  v_preflight:=public.communication_delivery_preflight(v_draft.id);
  return jsonb_build_object('version','COMMUNICATIONS_ADHERENCE_INTELLIGENCE_V98','organization_id',v_organization,'event_id',v_event.id,'draft',to_jsonb(v_draft),'preflight',v_preflight,'strategy_code',v_strategy,'message_body',v_body,'auto_sent',false,'next_action','Coach reviews/copies the draft, sends it manually if appropriate, then explicitly records the contact.','guardrails',jsonb_build_object('draft_creation_is_not_contact',true,'coach_approval_required',true,'auto_send',false,'manual_contact_confirmation_required',true));
end;
$function$;

CREATE OR REPLACE FUNCTION public.mark_adherence_followup_contacted_v98(p_actor_id uuid, p_draft_id uuid, p_sent_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_event private.adherence_followup_events_v98; v_draft public.communication_drafts; v_pref public.communication_preferences; v_local_time time; v_in_quiet boolean:=false;
begin
if auth.uid() is null or p_actor_id is null or auth.uid()<>p_actor_id then raise exception 'Authenticated actor mismatch'; end if; select * into v_event from private.adherence_followup_events_v98 where actor_id=p_actor_id and draft_id=p_draft_id; if v_event.id is null then raise exception 'V98 follow-up event not found'; end if; if not private.actor_can_manage_client_in_org_v1(p_actor_id,v_event.organization_id,v_event.client_id) then raise exception 'Not authorized to manage this client in organization'; end if; select * into v_draft from public.communication_drafts where id=p_draft_id and organization_id=v_event.organization_id; if v_draft.id is null or v_draft.status<>'ready' then raise exception 'Draft must be ready before contact can be recorded'; end if; select * into v_pref from public.communication_preferences where organization_id=v_event.organization_id and client_id=v_event.client_id; if v_pref.client_id is null or not coalesce(v_pref.whatsapp_opt_in,false) then raise exception 'Active WhatsApp consent is required'; end if; if v_pref.whatsapp_phone_e164 is null or v_pref.whatsapp_phone_e164 !~ '^\+[1-9][0-9]{7,14}$' then raise exception 'Valid E.164 WhatsApp phone is required'; end if; if p_sent_at>now()+interval '2 minutes' then raise exception 'Contact time cannot be in the future'; end if; if p_sent_at<v_draft.created_at-interval '5 minutes' then raise exception 'Contact time cannot predate the draft'; end if; begin v_local_time:=(p_sent_at at time zone coalesce(nullif(v_pref.timezone,''),'America/Santiago'))::time; exception when others then v_local_time:=(p_sent_at at time zone 'America/Santiago')::time; end; if v_pref.quiet_hours_start=v_pref.quiet_hours_end then v_in_quiet:=true; elsif v_pref.quiet_hours_start<v_pref.quiet_hours_end then v_in_quiet:=v_local_time>=v_pref.quiet_hours_start and v_local_time<v_pref.quiet_hours_end; else v_in_quiet:=v_local_time>=v_pref.quiet_hours_start or v_local_time<v_pref.quiet_hours_end; end if; if v_in_quiet then raise exception 'Client quiet hours are active at the recorded contact time'; end if; update private.adherence_followup_events_v98 set contacted_at=coalesce(contacted_at,p_sent_at),outcome_status=case when outcome_status='DRAFTED' then 'CONTACTED' else outcome_status end,metadata=metadata||jsonb_build_object('manual_external_send_attested_by',p_actor_id,'manual_external_send',true,'quiet_hours_checked',true,'local_contact_time',v_local_time),updated_at=now() where id=v_event.id returning * into v_event; return jsonb_build_object('version','COMMUNICATIONS_ADHERENCE_INTELLIGENCE_V98_2','organization_id',v_event.organization_id,'event_id',v_event.id,'draft_id',v_event.draft_id,'client_id',v_event.client_id,'contacted_at',v_event.contacted_at,'outcome_status',v_event.outcome_status,'quiet_hours_checked',true,'auto_sent',false,'recorded_manual_external_contact',true,'outcome_window_days',7,'note','This records the coach-attested contact. It does not send a message.'); end;$function$;

comment on column public.communication_preferences.organization_id is
  'F1.M1.S5 H1 tenant boundary for client communication consent/preferences.';
comment on column public.communication_drafts.organization_id is
  'F1.M1.S5 H1 tenant boundary for communication drafts; templates remain global catalogs.';
