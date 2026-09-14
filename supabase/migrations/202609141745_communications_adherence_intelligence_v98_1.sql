-- CV Coach V98.1 — communication timing hardening
-- Prevents manual contact attestation during client quiet hours and excludes future workout timestamps from outcome reconciliation.

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
  v_local_time time;
  v_in_quiet boolean := false;
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

  begin
    v_local_time := (p_sent_at at time zone coalesce(nullif(v_pref.timezone,''),'America/Santiago'))::time;
  exception when others then
    v_local_time := (p_sent_at at time zone 'America/Santiago')::time;
  end;

  if v_pref.quiet_hours_start = v_pref.quiet_hours_end then
    v_in_quiet := true;
  elsif v_pref.quiet_hours_start < v_pref.quiet_hours_end then
    v_in_quiet := v_local_time >= v_pref.quiet_hours_start and v_local_time < v_pref.quiet_hours_end;
  else
    v_in_quiet := v_local_time >= v_pref.quiet_hours_start or v_local_time < v_pref.quiet_hours_end;
  end if;

  if v_in_quiet then
    raise exception 'Client quiet hours are active at the recorded contact time';
  end if;

  update private.adherence_followup_events_v98
  set contacted_at=coalesce(contacted_at,p_sent_at),
      outcome_status=case when outcome_status='DRAFTED' then 'CONTACTED' else outcome_status end,
      metadata=metadata||jsonb_build_object(
        'manual_external_send_attested_by',p_actor_id,
        'manual_external_send',true,
        'quiet_hours_checked',true,
        'local_contact_time',v_local_time
      ),
      updated_at=now()
  where id=v_event.id
  returning * into v_event;

  return jsonb_build_object(
    'version','COMMUNICATIONS_ADHERENCE_INTELLIGENCE_V98_1',
    'event_id',v_event.id,
    'draft_id',v_event.draft_id,
    'client_id',v_event.client_id,
    'contacted_at',v_event.contacted_at,
    'outcome_status',v_event.outcome_status,
    'quiet_hours_checked',true,
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
        and coalesce(s.finished_at,s.started_at,s.created_at) <= least(now(),e.contacted_at+interval '7 days')
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
        metadata=e.metadata||jsonb_build_object('future_workout_timestamps_excluded',true),
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
    'version','COMMUNICATIONS_ADHERENCE_INTELLIGENCE_V98_1',
    'updated',v_updated,
    'returned',v_returned,
    'no_return',v_no_return,
    'waiting_evidence',v_waiting,
    'outcome_window_days',7,
    'future_workout_timestamps_excluded',true,
    'outcome_is_association_not_causality',true,
    'auto_message',false,
    'auto_program_edit',false
  );
end;
$function$;

revoke all on function public.mark_adherence_followup_contacted_v98(uuid,uuid,timestamptz) from public,anon;
revoke all on function public.refresh_adherence_followup_outcomes_v98(uuid) from public,anon;
grant execute on function public.mark_adherence_followup_contacted_v98(uuid,uuid,timestamptz) to authenticated,service_role;
grant execute on function public.refresh_adherence_followup_outcomes_v98(uuid) to authenticated,service_role;
