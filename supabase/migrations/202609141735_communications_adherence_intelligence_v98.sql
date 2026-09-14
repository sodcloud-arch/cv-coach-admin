-- CV Coach V98 — Communications & Adherence Intelligence
-- Search Before Create: reuses V97 Coach AI and the existing communication_drafts/preferences/preflight contracts.
-- No provider dispatch is performed here. Every external contact remains coach-approved and explicitly recorded.

create table if not exists private.adherence_followup_events_v98 (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid not null references public.profiles(id) on delete restrict,
  client_id uuid not null references public.profiles(id) on delete cascade,
  draft_id uuid not null unique references public.communication_drafts(id) on delete cascade,
  strategy_code text not null,
  trigger_days_since_workout integer,
  baseline_last_workout_at timestamptz,
  contacted_at timestamptz,
  contact_channel text not null default 'whatsapp_manual',
  outcome_status text not null default 'DRAFTED',
  returned_workout_session_id uuid references public.workout_sessions(id) on delete set null,
  returned_at timestamptz,
  days_to_return numeric,
  effectiveness_score integer,
  confidence numeric,
  last_reconciled_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint adherence_followup_v98_strategy_chk check (strategy_code in ('supportive_nudge','barrier_checkin','reactivation_reset')),
  constraint adherence_followup_v98_channel_chk check (contact_channel='whatsapp_manual'),
  constraint adherence_followup_v98_outcome_chk check (outcome_status in ('DRAFTED','CONTACTED','WAITING_EVIDENCE','RETURNED','NO_RETURN','ARCHIVED')),
  constraint adherence_followup_v98_effectiveness_chk check (effectiveness_score is null or effectiveness_score between -100 and 100),
  constraint adherence_followup_v98_confidence_chk check (confidence is null or confidence between 0 and 1),
  constraint adherence_followup_v98_days_chk check (trigger_days_since_workout is null or trigger_days_since_workout >= 0)
);

create index if not exists adherence_followup_events_v98_actor_idx
  on private.adherence_followup_events_v98(actor_id,created_at desc);
create index if not exists adherence_followup_events_v98_client_idx
  on private.adherence_followup_events_v98(client_id,created_at desc);
create index if not exists adherence_followup_events_v98_outcome_idx
  on private.adherence_followup_events_v98(actor_id,strategy_code,outcome_status,contacted_at desc);

revoke all on private.adherence_followup_events_v98 from public,anon,authenticated;
grant select,insert,update,delete on private.adherence_followup_events_v98 to service_role;

create or replace function public.get_adherence_communication_center_v98(p_actor_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_base jsonb;
  v_items jsonb;
  v_strategy_catalog jsonb;
  v_provider public.communication_provider_config;
  v_summary jsonb;
begin
  -- V97 remains authoritative for authentication, scope, deterministic action routing and safety.
  v_base := public.get_coach_ai_command_center_v94(p_actor_id);

  select * into v_provider
  from public.communication_provider_config
  where brand_scope='CV_COACH';

  with base_items as (
    select x.item,
      (x.item->>'client_id')::uuid as client_id,
      nullif(x.item#>>'{training,days_since_workout}','')::int as days_since_workout,
      coalesce(x.item#>>'{training,risk_level}','GREEN') as risk_level,
      coalesce(x.item#>>'{lifecycle,stage}','') as lifecycle_stage
    from jsonb_array_elements(coalesce(v_base->'items','[]'::jsonb)) x(item)
  ), prepared as (
    select
      b.*,
      cp.whatsapp_opt_in,
      cp.whatsapp_phone_e164,
      cp.quiet_hours_start,
      cp.quiet_hours_end,
      cp.timezone,
      ls.last_workout_at,
      le.id as last_event_id,
      le.draft_id as last_draft_id,
      le.strategy_code as last_strategy_code,
      le.contacted_at as last_contacted_at,
      le.outcome_status as last_outcome_status,
      le.returned_at as last_returned_at,
      le.days_to_return as last_days_to_return,
      case
        when b.days_since_workout between 7 and 13 then 'supportive_nudge'
        when b.days_since_workout between 14 and 20 then 'barrier_checkin'
        when b.days_since_workout >= 21 then 'reactivation_reset'
        else null
      end as strategy_code
    from base_items b
    left join public.communication_preferences cp on cp.client_id=b.client_id
    left join lateral (
      select coalesce(ws.finished_at,ws.started_at,ws.created_at) as last_workout_at
      from public.workout_sessions ws
      where ws.client_id=b.client_id and ws.status in ('completed','partial')
      order by coalesce(ws.finished_at,ws.started_at,ws.created_at) desc
      limit 1
    ) ls on true
    left join lateral (
      select e.*
      from private.adherence_followup_events_v98 e
      where e.actor_id=p_actor_id and e.client_id=b.client_id
      order by e.created_at desc,e.id desc
      limit 1
    ) le on true
  ), scored as (
    select
      p.*,
      (
        p.days_since_workout is not null
        and p.days_since_workout >= 7
        and p.lifecycle_stage='operational'
        and upper(coalesce(p.risk_level,'GREEN')) <> 'RED'
        and coalesce(p.item->>'primary_domain','') <> 'SAFETY'
        and (p.last_contacted_at is null or p.last_contacted_at <= now()-interval '5 days')
      ) as followup_recommended,
      case
        when p.days_since_workout between 7 and 13 then 55
        when p.days_since_workout between 14 and 20 then 75
        when p.days_since_workout >= 21 then 90
        else 0
      end as adherence_contact_score
    from prepared p
  ), enriched as (
    select
      s.*,
      case
        when not s.followup_recommended then 'NOT_RECOMMENDED'
        when not coalesce(s.whatsapp_opt_in,false) then 'CONSENT_REQUIRED'
        when s.whatsapp_phone_e164 is null or s.whatsapp_phone_e164 !~ '^\\+[1-9][0-9]{7,14}$' then 'PHONE_REQUIRED'
        else 'DRAFT_READY'
      end as readiness,
      split_part(coalesce(nullif(s.item->>'client_name',''),'Cliente'),' ',1) as first_name,
      case s.strategy_code
        when 'supportive_nudge' then
          'Hola '||split_part(coalesce(nullif(s.item->>'client_name',''),'Cliente'),' ',1)||' 👋 Han pasado '||s.days_since_workout||' días desde tu última sesión. ¿Cómo te has sentido esta semana? Si hubo algo que te frenó, cuéntame y ajustamos el plan para que puedas retomarlo de forma realista. — Camilo'
        when 'barrier_checkin' then
          'Hola '||split_part(coalesce(nullif(s.item->>'client_name',''),'Cliente'),' ',1)||' 👋 Llevamos '||s.days_since_workout||' días sin una sesión registrada. Antes de simplemente empujarte a volver, quiero saber qué se interpuso: tiempo, energía, molestias, motivación u otra cosa. Respóndeme y ajustamos el plan para que vuelva a ser sostenible. — Camilo'
        when 'reactivation_reset' then
          'Hola '||split_part(coalesce(nullif(s.item->>'client_name',''),'Cliente'),' ',1)||' 👋 Ya han pasado '||s.days_since_workout||' días desde tu última sesión. En vez de intentar recuperar todo de golpe, podemos reiniciar con una versión más simple esta semana. Cuéntame cómo estás hoy y te ayudo a retomar con un objetivo pequeño y concreto. — Camilo'
        else null
      end as proposed_message
    from scored s
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'client_id',e.client_id,
    'client_name',e.item->>'client_name',
    'email',e.item->>'email',
    'primary_goal',e.item->>'primary_goal',
    'coach_ai_priority',e.item->>'priority',
    'coach_ai_domain',e.item->>'primary_domain',
    'coach_ai_action_code',e.item->>'recommended_action_code',
    'days_since_workout',e.days_since_workout,
    'last_workout_at',e.last_workout_at,
    'risk_level',e.risk_level,
    'lifecycle_stage',e.lifecycle_stage,
    'followup_recommended',e.followup_recommended,
    'adherence_contact_score',e.adherence_contact_score,
    'strategy_code',e.strategy_code,
    'readiness',e.readiness,
    'proposed_message',e.proposed_message,
    'communication',jsonb_build_object(
      'whatsapp_opt_in',coalesce(e.whatsapp_opt_in,false),
      'phone_ready',(e.whatsapp_phone_e164 is not null and e.whatsapp_phone_e164 ~ '^\\+[1-9][0-9]{7,14}$'),
      'timezone',coalesce(e.timezone,'America/Santiago'),
      'quiet_hours_start',e.quiet_hours_start,
      'quiet_hours_end',e.quiet_hours_end,
      'provider',coalesce(v_provider.provider,'peach'),
      'provider_status',coalesce(v_provider.status,'unassigned'),
      'provider_dispatch_enabled',coalesce(v_provider.dispatch_enabled,false),
      'auto_dispatch',false
    ),
    'last_followup',case when e.last_event_id is null then null else jsonb_build_object(
      'event_id',e.last_event_id,
      'draft_id',e.last_draft_id,
      'strategy_code',e.last_strategy_code,
      'contacted_at',e.last_contacted_at,
      'outcome_status',e.last_outcome_status,
      'returned_at',e.last_returned_at,
      'days_to_return',e.last_days_to_return
    ) end,
    'guardrails',jsonb_build_object(
      'coach_approval_required',true,
      'draft_creation_is_not_contact',true,
      'manual_contact_confirmation_required',true,
      'auto_send',false,
      'provider_dispatch_mutation',false,
      'red_safety_contact_suppressed',true,
      'outcome_is_association_not_causality',true
    )
  ) order by e.followup_recommended desc,e.adherence_contact_score desc,lower(coalesce(e.item->>'client_name',''))),'[]'::jsonb)
  into v_items
  from enriched e;

  with resolved as (
    select strategy_code,
      count(*)::int as sample_size,
      count(*) filter(where outcome_status='RETURNED')::int as returned,
      count(*) filter(where outcome_status='NO_RETURN')::int as no_return,
      round(avg(days_to_return) filter(where outcome_status='RETURNED')::numeric,2) as avg_days_to_return,
      round(avg(effectiveness_score) filter(where effectiveness_score is not null)::numeric,1) as avg_effectiveness,
      round(avg(confidence) filter(where confidence is not null)::numeric,3) as avg_confidence
    from private.adherence_followup_events_v98
    where actor_id=p_actor_id
      and contacted_at is not null
      and outcome_status in ('RETURNED','NO_RETURN')
    group by strategy_code
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'strategy_code',r.strategy_code,
    'sample_size',r.sample_size,
    'returned',r.returned,
    'no_return',r.no_return,
    'return_rate',round(r.returned::numeric/nullif(r.sample_size,0),3),
    'avg_days_to_return',r.avg_days_to_return,
    'avg_effectiveness',r.avg_effectiveness,
    'avg_confidence',r.avg_confidence,
    'learning_ready',r.sample_size>=3
  ) order by r.sample_size desc,r.strategy_code),'[]'::jsonb)
  into v_strategy_catalog
  from resolved r;

  with x as (select value j from jsonb_array_elements(v_items))
  select jsonb_build_object(
    'total_clients',count(*),
    'followup_recommended',count(*) filter(where coalesce((j->>'followup_recommended')::boolean,false)),
    'draft_ready',count(*) filter(where j->>'readiness'='DRAFT_READY'),
    'consent_required',count(*) filter(where j->>'readiness'='CONSENT_REQUIRED'),
    'phone_required',count(*) filter(where j->>'readiness'='PHONE_REQUIRED'),
    'provider_dispatch_enabled',coalesce(v_provider.dispatch_enabled,false),
    'resolved_followups',(select count(*) from private.adherence_followup_events_v98 e where e.actor_id=p_actor_id and e.outcome_status in ('RETURNED','NO_RETURN')),
    'waiting_outcomes',(select count(*) from private.adherence_followup_events_v98 e where e.actor_id=p_actor_id and e.outcome_status in ('CONTACTED','WAITING_EVIDENCE'))
  ) into v_summary from x;

  return jsonb_build_object(
    'version','COMMUNICATIONS_ADHERENCE_INTELLIGENCE_V98',
    'items',v_items,
    'summary',v_summary,
    'strategy_catalog',v_strategy_catalog,
    'provider',jsonb_build_object(
      'provider',coalesce(v_provider.provider,'peach'),
      'status',coalesce(v_provider.status,'unassigned'),
      'dispatch_enabled',coalesce(v_provider.dispatch_enabled,false)
    ),
    'guardrails',jsonb_build_object(
      'coach_approval_required',true,
      'auto_send',false,
      'draft_is_not_contact',true,
      'manual_contact_confirmation_required',true,
      'outcome_window_days',7,
      'strategy_learning_sample_gate',3,
      'outcome_is_association_not_causality',true,
      'safety_red_suppressed',true
    )
  );
end;
$function$;

create or replace function public.prepare_adherence_followup_v98(
  p_actor_id uuid,
  p_client_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_center jsonb;
  v_item jsonb;
  v_body text;
  v_strategy text;
  v_type text;
  v_key text;
  v_draft public.communication_drafts;
  v_event private.adherence_followup_events_v98;
  v_last_workout timestamptz;
  v_preflight jsonb;
begin
  if auth.uid() is null or p_actor_id is null or auth.uid()<>p_actor_id then
    raise exception 'Authenticated actor mismatch';
  end if;

  v_center := public.get_adherence_communication_center_v98(p_actor_id);
  select x into v_item
  from jsonb_array_elements(coalesce(v_center->'items','[]'::jsonb)) x
  where x->>'client_id'=p_client_id::text
  limit 1;

  if v_item is null then raise exception 'Client not available in V98 scope'; end if;
  if not coalesce((v_item->>'followup_recommended')::boolean,false) then
    raise exception 'Adherence follow-up is not currently recommended';
  end if;
  if coalesce(v_item->>'readiness','')<>'DRAFT_READY' then
    raise exception 'Communication draft is blocked: %',coalesce(v_item->>'readiness','UNKNOWN');
  end if;

  v_body := v_item->>'proposed_message';
  v_strategy := v_item->>'strategy_code';
  v_type := case when coalesce(nullif(v_item->>'days_since_workout','')::int,0)>=14 then 'retention_followup' else 'workout_reminder' end;
  v_key := 'v98:'||p_actor_id::text||':'||p_client_id::text||':'||v_strategy||':'||to_char(now() at time zone 'UTC','YYYYMMDD');

  v_draft := public.prepare_communication_draft(
    p_client_id,v_type,v_body,v_key,'v98_adherence',v_strategy
  );

  select coalesce(ws.finished_at,ws.started_at,ws.created_at) into v_last_workout
  from public.workout_sessions ws
  where ws.client_id=p_client_id and ws.status in ('completed','partial')
  order by coalesce(ws.finished_at,ws.started_at,ws.created_at) desc
  limit 1;

  insert into private.adherence_followup_events_v98(
    actor_id,client_id,draft_id,strategy_code,trigger_days_since_workout,baseline_last_workout_at,metadata
  ) values (
    p_actor_id,p_client_id,v_draft.id,v_strategy,nullif(v_item->>'days_since_workout','')::int,v_last_workout,
    jsonb_build_object('coach_ai_priority',v_item->>'coach_ai_priority','coach_ai_domain',v_item->>'coach_ai_domain','source','V98')
  )
  on conflict (draft_id) do update set updated_at=now()
  returning * into v_event;

  v_preflight := public.communication_delivery_preflight(v_draft.id);

  return jsonb_build_object(
    'version','COMMUNICATIONS_ADHERENCE_INTELLIGENCE_V98',
    'event_id',v_event.id,
    'draft',to_jsonb(v_draft),
    'preflight',v_preflight,
    'strategy_code',v_strategy,
    'message_body',v_body,
    'auto_sent',false,
    'next_action','Coach reviews/copies the draft, sends it manually if appropriate, then explicitly records the contact.',
    'guardrails',jsonb_build_object(
      'draft_creation_is_not_contact',true,
      'coach_approval_required',true,
      'auto_send',false,
      'manual_contact_confirmation_required',true
    )
  );
end;
$function$;

create or replace function public.mark_adherence_followup_contacted_v98(
  p_actor_id uuid,
  p_draft_id uuid,
  p_sent_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_event private.adherence_followup_events_v98;
  v_draft public.communication_drafts;
  v_pref public.communication_preferences;
begin
  if auth.uid() is null or p_actor_id is null or auth.uid()<>p_actor_id then
    raise exception 'Authenticated actor mismatch';
  end if;

  select * into v_event
  from private.adherence_followup_events_v98
  where actor_id=p_actor_id and draft_id=p_draft_id;
  if v_event.id is null then raise exception 'V98 follow-up event not found'; end if;
  if not private.can_manage_client(v_event.client_id) then raise exception 'Not authorized to manage this client'; end if;

  select * into v_draft from public.communication_drafts where id=p_draft_id;
  if v_draft.id is null or v_draft.status<>'ready' then raise exception 'Draft must be ready before contact can be recorded'; end if;

  select * into v_pref from public.communication_preferences where client_id=v_event.client_id;
  if v_pref.client_id is null or not coalesce(v_pref.whatsapp_opt_in,false) then raise exception 'Active WhatsApp consent is required'; end if;
  if v_pref.whatsapp_phone_e164 is null or v_pref.whatsapp_phone_e164 !~ '^\\+[1-9][0-9]{7,14}$' then raise exception 'Valid E.164 WhatsApp phone is required'; end if;
  if p_sent_at > now()+interval '2 minutes' then raise exception 'Contact time cannot be in the future'; end if;
  if p_sent_at < v_draft.created_at-interval '5 minutes' then raise exception 'Contact time cannot predate the draft'; end if;

  update private.adherence_followup_events_v98
  set contacted_at=coalesce(contacted_at,p_sent_at),
      outcome_status=case when outcome_status='DRAFTED' then 'CONTACTED' else outcome_status end,
      metadata=metadata||jsonb_build_object('manual_external_send_attested_by',p_actor_id,'manual_external_send',true),
      updated_at=now()
  where id=v_event.id
  returning * into v_event;

  return jsonb_build_object(
    'version','COMMUNICATIONS_ADHERENCE_INTELLIGENCE_V98',
    'event_id',v_event.id,
    'draft_id',v_event.draft_id,
    'client_id',v_event.client_id,
    'contacted_at',v_event.contacted_at,
    'outcome_status',v_event.outcome_status,
    'auto_sent',false,
    'recorded_manual_external_contact',true,
    'outcome_window_days',7,
    'note','This records the coach-attested contact. It does not send a message.'
  );
end;
$function$;

create or replace function public.refresh_adherence_followup_outcomes_v98(p_actor_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_base jsonb;
  v_updated int := 0;
  v_returned int := 0;
  v_no_return int := 0;
  v_waiting int := 0;
begin
  -- Reuse V97 auth/scope contract.
  v_base := public.get_coach_ai_command_center_v94(p_actor_id);

  with candidates as (
    select e.id,e.contacted_at,
      ws.id as returned_session_id,
      coalesce(ws.finished_at,ws.started_at,ws.created_at) as returned_at
    from private.adherence_followup_events_v98 e
    left join lateral (
      select s.id,s.finished_at,s.started_at,s.created_at
      from public.workout_sessions s
      where s.client_id=e.client_id
        and s.status in ('completed','partial')
        and coalesce(s.finished_at,s.started_at,s.created_at) > e.contacted_at
        and coalesce(s.finished_at,s.started_at,s.created_at) <= e.contacted_at+interval '7 days'
      order by coalesce(s.finished_at,s.started_at,s.created_at) asc
      limit 1
    ) ws on true
    where e.actor_id=p_actor_id
      and e.contacted_at is not null
      and e.outcome_status in ('CONTACTED','WAITING_EVIDENCE')
  ), updates as (
    update private.adherence_followup_events_v98 e
    set returned_workout_session_id=c.returned_session_id,
        returned_at=c.returned_at,
        days_to_return=case when c.returned_at is not null then round((extract(epoch from (c.returned_at-c.contacted_at))/86400.0)::numeric,2) else null end,
        outcome_status=case
          when c.returned_at is not null then 'RETURNED'
          when now() >= c.contacted_at+interval '7 days' then 'NO_RETURN'
          else 'WAITING_EVIDENCE'
        end,
        effectiveness_score=case
          when c.returned_at is not null and c.returned_at<=c.contacted_at+interval '2 days' then 100
          when c.returned_at is not null and c.returned_at<=c.contacted_at+interval '4 days' then 80
          when c.returned_at is not null then 60
          when now() >= c.contacted_at+interval '7 days' then -60
          else 0
        end,
        confidence=case
          when c.returned_at is not null then 0.75
          when now() >= c.contacted_at+interval '7 days' then 0.75
          else 0.40
        end,
        last_reconciled_at=now(),
        updated_at=now()
    from candidates c
    where e.id=c.id
    returning e.outcome_status
  )
  select count(*),
    count(*) filter(where outcome_status='RETURNED'),
    count(*) filter(where outcome_status='NO_RETURN'),
    count(*) filter(where outcome_status='WAITING_EVIDENCE')
  into v_updated,v_returned,v_no_return,v_waiting
  from updates;

  return jsonb_build_object(
    'version','COMMUNICATIONS_ADHERENCE_INTELLIGENCE_V98',
    'updated',v_updated,
    'returned',v_returned,
    'no_return',v_no_return,
    'waiting_evidence',v_waiting,
    'outcome_window_days',7,
    'outcome_is_association_not_causality',true,
    'auto_message',false,
    'auto_program_edit',false
  );
end;
$function$;

revoke all on function public.get_adherence_communication_center_v98(uuid) from public,anon;
revoke all on function public.prepare_adherence_followup_v98(uuid,uuid) from public,anon;
revoke all on function public.mark_adherence_followup_contacted_v98(uuid,uuid,timestamptz) from public,anon;
revoke all on function public.refresh_adherence_followup_outcomes_v98(uuid) from public,anon;

grant execute on function public.get_adherence_communication_center_v98(uuid) to authenticated,service_role;
grant execute on function public.prepare_adherence_followup_v98(uuid,uuid) to authenticated,service_role;
grant execute on function public.mark_adherence_followup_contacted_v98(uuid,uuid,timestamptz) to authenticated,service_role;
grant execute on function public.refresh_adherence_followup_outcomes_v98(uuid) to authenticated,service_role;

comment on function public.get_adherence_communication_center_v98(uuid) is
  'V98 read-only communications/adherence intelligence over V97 and existing communication contracts. Recommends follow-up drafts, never sends messages.';
comment on function public.prepare_adherence_followup_v98(uuid,uuid) is
  'V98 prepares an idempotent existing communication_draft for a recommended adherence follow-up. Draft creation is not contact and never dispatches.';
comment on function public.mark_adherence_followup_contacted_v98(uuid,uuid,timestamptz) is
  'V98 records a coach-attested manual external WhatsApp contact after explicit coach action. Never sends a message.';
comment on function public.refresh_adherence_followup_outcomes_v98(uuid) is
  'V98 reconciles whether a client returned to a completed/partial workout within seven days after an explicitly recorded contact. Association, not causality.';
