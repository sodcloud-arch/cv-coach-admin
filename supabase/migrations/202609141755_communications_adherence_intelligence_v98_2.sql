-- CV Coach V98.2 — meaningful adherence clock + E.164 regex correction
-- Adherence ignores abandoned sessions and measures inactivity from completed/partial sessions only.

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
  v_base := public.get_coach_ai_command_center_v94(p_actor_id);
  select * into v_provider from public.communication_provider_config where brand_scope='CV_COACH';

  with base_items as (
    select x.item,
      (x.item->>'client_id')::uuid as client_id,
      nullif(x.item#>>'{training,days_since_workout}','')::int as coach_ai_days_since_workout,
      coalesce(x.item#>>'{training,risk_level}','GREEN') as risk_level,
      coalesce(x.item#>>'{lifecycle,stage}','') as lifecycle_stage
    from jsonb_array_elements(coalesce(v_base->'items','[]'::jsonb)) x(item)
  ), prepared0 as (
    select b.*,cp.whatsapp_opt_in,cp.whatsapp_phone_e164,cp.quiet_hours_start,cp.quiet_hours_end,cp.timezone,
      ls.last_workout_at,
      case when ls.last_workout_at is null then null else greatest(0,floor(extract(epoch from (now()-ls.last_workout_at))/86400.0)::int) end as days_since_workout,
      le.id as last_event_id,le.draft_id as last_draft_id,le.strategy_code as last_strategy_code,le.contacted_at as last_contacted_at,le.outcome_status as last_outcome_status,le.returned_at as last_returned_at,le.days_to_return as last_days_to_return
    from base_items b
    left join public.communication_preferences cp on cp.client_id=b.client_id
    left join lateral (
      select coalesce(ws.finished_at,ws.started_at,ws.created_at) as last_workout_at
      from public.workout_sessions ws
      where ws.client_id=b.client_id and ws.status in ('completed','partial')
        and coalesce(ws.finished_at,ws.started_at,ws.created_at) <= now()
      order by coalesce(ws.finished_at,ws.started_at,ws.created_at) desc
      limit 1
    ) ls on true
    left join lateral (
      select e.* from private.adherence_followup_events_v98 e
      where e.actor_id=p_actor_id and e.client_id=b.client_id
      order by e.created_at desc,e.id desc limit 1
    ) le on true
  ), prepared as (
    select p.*,
      case when p.days_since_workout between 7 and 13 then 'supportive_nudge'
           when p.days_since_workout between 14 and 20 then 'barrier_checkin'
           when p.days_since_workout >= 21 then 'reactivation_reset'
           else null end as strategy_code
    from prepared0 p
  ), scored as (
    select p.*,
      (p.days_since_workout is not null and p.days_since_workout >= 7
       and p.lifecycle_stage='operational'
       and upper(coalesce(p.risk_level,'GREEN')) <> 'RED'
       and coalesce(p.item->>'primary_domain','') <> 'SAFETY'
       and (p.last_contacted_at is null or p.last_contacted_at <= now()-interval '5 days')) as followup_recommended,
      case when p.days_since_workout between 7 and 13 then 55
           when p.days_since_workout between 14 and 20 then 75
           when p.days_since_workout >= 21 then 90 else 0 end as adherence_contact_score
    from prepared p
  ), enriched as (
    select s.*,
      case when not s.followup_recommended then 'NOT_RECOMMENDED'
           when not coalesce(s.whatsapp_opt_in,false) then 'CONSENT_REQUIRED'
           when s.whatsapp_phone_e164 is null or s.whatsapp_phone_e164 !~ '^\+[1-9][0-9]{7,14}$' then 'PHONE_REQUIRED'
           else 'DRAFT_READY' end as readiness,
      case s.strategy_code
        when 'supportive_nudge' then 'Hola '||split_part(coalesce(nullif(s.item->>'client_name',''),'Cliente'),' ',1)||' 👋 Han pasado '||s.days_since_workout||' días desde tu última sesión. ¿Cómo te has sentido esta semana? Si hubo algo que te frenó, cuéntame y ajustamos el plan para que puedas retomarlo de forma realista. — Camilo'
        when 'barrier_checkin' then 'Hola '||split_part(coalesce(nullif(s.item->>'client_name',''),'Cliente'),' ',1)||' 👋 Llevamos '||s.days_since_workout||' días sin una sesión registrada. Antes de simplemente empujarte a volver, quiero saber qué se interpuso: tiempo, energía, molestias, motivación u otra cosa. Respóndeme y ajustamos el plan para que vuelva a ser sostenible. — Camilo'
        when 'reactivation_reset' then 'Hola '||split_part(coalesce(nullif(s.item->>'client_name',''),'Cliente'),' ',1)||' 👋 Ya han pasado '||s.days_since_workout||' días desde tu última sesión. En vez de intentar recuperar todo de golpe, podemos reiniciar con una versión más simple esta semana. Cuéntame cómo estás hoy y te ayudo a retomar con un objetivo pequeño y concreto. — Camilo'
        else null end as proposed_message
    from scored s
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'client_id',e.client_id,'client_name',e.item->>'client_name','email',e.item->>'email','primary_goal',e.item->>'primary_goal',
    'coach_ai_priority',e.item->>'priority','coach_ai_domain',e.item->>'primary_domain','coach_ai_action_code',e.item->>'recommended_action_code',
    'coach_ai_days_since_workout',e.coach_ai_days_since_workout,'days_since_workout',e.days_since_workout,'last_workout_at',e.last_workout_at,
    'adherence_clock','completed_or_partial_only','risk_level',e.risk_level,'lifecycle_stage',e.lifecycle_stage,
    'followup_recommended',e.followup_recommended,'adherence_contact_score',e.adherence_contact_score,'strategy_code',e.strategy_code,'readiness',e.readiness,'proposed_message',e.proposed_message,
    'communication',jsonb_build_object('whatsapp_opt_in',coalesce(e.whatsapp_opt_in,false),'phone_ready',(e.whatsapp_phone_e164 is not null and e.whatsapp_phone_e164 ~ '^\+[1-9][0-9]{7,14}$'),'timezone',coalesce(e.timezone,'America/Santiago'),'quiet_hours_start',e.quiet_hours_start,'quiet_hours_end',e.quiet_hours_end,'provider',coalesce(v_provider.provider,'peach'),'provider_status',coalesce(v_provider.status,'unassigned'),'provider_dispatch_enabled',coalesce(v_provider.dispatch_enabled,false),'auto_dispatch',false),
    'last_followup',case when e.last_event_id is null then null else jsonb_build_object('event_id',e.last_event_id,'draft_id',e.last_draft_id,'strategy_code',e.last_strategy_code,'contacted_at',e.last_contacted_at,'outcome_status',e.last_outcome_status,'returned_at',e.last_returned_at,'days_to_return',e.last_days_to_return) end,
    'guardrails',jsonb_build_object('coach_approval_required',true,'draft_creation_is_not_contact',true,'manual_contact_confirmation_required',true,'auto_send',false,'provider_dispatch_mutation',false,'red_safety_contact_suppressed',true,'abandoned_sessions_do_not_reset_adherence_clock',true,'outcome_is_association_not_causality',true)
  ) order by e.followup_recommended desc,e.adherence_contact_score desc,lower(coalesce(e.item->>'client_name',''))),'[]'::jsonb)
  into v_items from enriched e;

  with resolved as (
    select strategy_code,count(*)::int as sample_size,count(*) filter(where outcome_status='RETURNED')::int as returned,count(*) filter(where outcome_status='NO_RETURN')::int as no_return,
      round(avg(days_to_return) filter(where outcome_status='RETURNED')::numeric,2) as avg_days_to_return,
      round(avg(effectiveness_score) filter(where effectiveness_score is not null)::numeric,1) as avg_effectiveness,
      round(avg(confidence) filter(where confidence is not null)::numeric,3) as avg_confidence
    from private.adherence_followup_events_v98
    where actor_id=p_actor_id and contacted_at is not null and outcome_status in ('RETURNED','NO_RETURN') group by strategy_code
  )
  select coalesce(jsonb_agg(jsonb_build_object('strategy_code',r.strategy_code,'sample_size',r.sample_size,'returned',r.returned,'no_return',r.no_return,'return_rate',round(r.returned::numeric/nullif(r.sample_size,0),3),'avg_days_to_return',r.avg_days_to_return,'avg_effectiveness',r.avg_effectiveness,'avg_confidence',r.avg_confidence,'learning_ready',r.sample_size>=3) order by r.sample_size desc,r.strategy_code),'[]'::jsonb)
  into v_strategy_catalog from resolved r;

  with x as (select value j from jsonb_array_elements(v_items))
  select jsonb_build_object('total_clients',count(*),'followup_recommended',count(*) filter(where coalesce((j->>'followup_recommended')::boolean,false)),'draft_ready',count(*) filter(where j->>'readiness'='DRAFT_READY'),'consent_required',count(*) filter(where j->>'readiness'='CONSENT_REQUIRED'),'phone_required',count(*) filter(where j->>'readiness'='PHONE_REQUIRED'),'provider_dispatch_enabled',coalesce(v_provider.dispatch_enabled,false),'resolved_followups',(select count(*) from private.adherence_followup_events_v98 e where e.actor_id=p_actor_id and e.outcome_status in ('RETURNED','NO_RETURN')),'waiting_outcomes',(select count(*) from private.adherence_followup_events_v98 e where e.actor_id=p_actor_id and e.outcome_status in ('CONTACTED','WAITING_EVIDENCE')))
  into v_summary from x;

  return jsonb_build_object('version','COMMUNICATIONS_ADHERENCE_INTELLIGENCE_V98_2','items',v_items,'summary',v_summary,'strategy_catalog',v_strategy_catalog,'provider',jsonb_build_object('provider',coalesce(v_provider.provider,'peach'),'status',coalesce(v_provider.status,'unassigned'),'dispatch_enabled',coalesce(v_provider.dispatch_enabled,false)),'guardrails',jsonb_build_object('coach_approval_required',true,'auto_send',false,'draft_is_not_contact',true,'manual_contact_confirmation_required',true,'outcome_window_days',7,'strategy_learning_sample_gate',3,'meaningful_workout_statuses',jsonb_build_array('completed','partial'),'abandoned_sessions_reset_clock',false,'outcome_is_association_not_causality',true,'safety_red_suppressed',true));
end;
$function$;

create or replace function public.mark_adherence_followup_contacted_v98(p_actor_id uuid,p_draft_id uuid,p_sent_at timestamptz default now())
returns jsonb language plpgsql security definer set search_path='' as $function$
declare v_event private.adherence_followup_events_v98; v_draft public.communication_drafts; v_pref public.communication_preferences; v_local_time time; v_in_quiet boolean:=false;
begin
  if auth.uid() is null or p_actor_id is null or auth.uid()<>p_actor_id then raise exception 'Authenticated actor mismatch'; end if;
  select * into v_event from private.adherence_followup_events_v98 where actor_id=p_actor_id and draft_id=p_draft_id;
  if v_event.id is null then raise exception 'V98 follow-up event not found'; end if;
  if not private.can_manage_client(v_event.client_id) then raise exception 'Not authorized to manage this client'; end if;
  select * into v_draft from public.communication_drafts where id=p_draft_id;
  if v_draft.id is null or v_draft.status<>'ready' then raise exception 'Draft must be ready before contact can be recorded'; end if;
  select * into v_pref from public.communication_preferences where client_id=v_event.client_id;
  if v_pref.client_id is null or not coalesce(v_pref.whatsapp_opt_in,false) then raise exception 'Active WhatsApp consent is required'; end if;
  if v_pref.whatsapp_phone_e164 is null or v_pref.whatsapp_phone_e164 !~ '^\+[1-9][0-9]{7,14}$' then raise exception 'Valid E.164 WhatsApp phone is required'; end if;
  if p_sent_at > now()+interval '2 minutes' then raise exception 'Contact time cannot be in the future'; end if;
  if p_sent_at < v_draft.created_at-interval '5 minutes' then raise exception 'Contact time cannot predate the draft'; end if;
  begin v_local_time := (p_sent_at at time zone coalesce(nullif(v_pref.timezone,''),'America/Santiago'))::time; exception when others then v_local_time := (p_sent_at at time zone 'America/Santiago')::time; end;
  if v_pref.quiet_hours_start=v_pref.quiet_hours_end then v_in_quiet:=true; elsif v_pref.quiet_hours_start<v_pref.quiet_hours_end then v_in_quiet:=v_local_time>=v_pref.quiet_hours_start and v_local_time<v_pref.quiet_hours_end; else v_in_quiet:=v_local_time>=v_pref.quiet_hours_start or v_local_time<v_pref.quiet_hours_end; end if;
  if v_in_quiet then raise exception 'Client quiet hours are active at the recorded contact time'; end if;
  update private.adherence_followup_events_v98 set contacted_at=coalesce(contacted_at,p_sent_at),outcome_status=case when outcome_status='DRAFTED' then 'CONTACTED' else outcome_status end,metadata=metadata||jsonb_build_object('manual_external_send_attested_by',p_actor_id,'manual_external_send',true,'quiet_hours_checked',true,'local_contact_time',v_local_time),updated_at=now() where id=v_event.id returning * into v_event;
  return jsonb_build_object('version','COMMUNICATIONS_ADHERENCE_INTELLIGENCE_V98_2','event_id',v_event.id,'draft_id',v_event.draft_id,'client_id',v_event.client_id,'contacted_at',v_event.contacted_at,'outcome_status',v_event.outcome_status,'quiet_hours_checked',true,'auto_sent',false,'recorded_manual_external_contact',true,'outcome_window_days',7,'note','This records the coach-attested contact. It does not send a message.');
end;
$function$;

revoke all on function public.get_adherence_communication_center_v98(uuid) from public,anon;
revoke all on function public.mark_adherence_followup_contacted_v98(uuid,uuid,timestamptz) from public,anon;
grant execute on function public.get_adherence_communication_center_v98(uuid) to authenticated,service_role;
grant execute on function public.mark_adherence_followup_contacted_v98(uuid,uuid,timestamptz) to authenticated,service_role;
