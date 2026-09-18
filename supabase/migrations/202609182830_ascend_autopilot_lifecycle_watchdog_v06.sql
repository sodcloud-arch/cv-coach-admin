-- ASCEND NEXUS · Autopilot lifecycle watchdog v0.6
-- Repairs orphaned claimed Reasoning Requests and carries continuation instructions across cycles.

create or replace function public.ascend_reconcile_chat_session(
  p_session_id uuid,
  p_worker text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_session public.ascend_chat_sessions%rowtype;
  v_request public.ascend_reasoning_requests%rowtype;
  v_message_exists boolean:=false;
  v_status text;
begin
  select * into v_session
  from public.ascend_chat_sessions
  where id=p_session_id
  for update;

  if not found then
    raise exception 'ASCEND chat session not found';
  end if;

  if v_session.status<>'active' or not v_session.autopilot_enabled then
    return jsonb_build_object(
      'kind','SESSION_INACTIVE',
      'session_id',v_session.id,
      'status',v_session.status,
      'autopilot_enabled',v_session.autopilot_enabled,
      'version','0.6'
    );
  end if;

  if v_session.current_reasoning_request_id is not null then
    select * into v_request
    from public.ascend_reasoning_requests
    where id=v_session.current_reasoning_request_id
    for update;

    if not found
       or v_request.status in ('resolved','dismissed','blocked') then
      update public.ascend_chat_sessions
      set current_reasoning_request_id=null,
          last_event_at=now(),
          updated_at=now()
      where id=v_session.id;

      return jsonb_build_object(
        'kind','STALE_SESSION_POINTER_CLEARED',
        'session_id',v_session.id,
        'version','0.6'
      );
    end if;

    if v_request.status='claimed' then
      if v_request.chat_session_id is null then
        update public.ascend_reasoning_requests
        set chat_session_id=v_session.id,
            updated_at=now()
        where id=v_request.id;
      elsif v_request.chat_session_id<>v_session.id then
        update public.ascend_chat_sessions
        set current_reasoning_request_id=null,
            last_event_at=now(),
            updated_at=now()
        where id=v_session.id;

        return jsonb_build_object(
          'kind','FOREIGN_CLAIM_POINTER_CLEARED',
          'session_id',v_session.id,
          'request_id',v_request.id,
          'version','0.6'
        );
      end if;

      if v_request.claimed_by is distinct from p_worker then
        update public.ascend_reasoning_requests
        set claimed_by=p_worker,
            last_error=case
              when last_error is null then
                'Reasoning claim ownership normalized by ASCEND lifecycle watchdog.'
              else last_error||E'\nReasoning claim ownership normalized by ASCEND lifecycle watchdog.'
            end,
            updated_at=now()
        where id=v_request.id;
      end if;

      return jsonb_build_object(
        'kind','ACTIVE_CLAIM_OK',
        'session_id',v_session.id,
        'request_id',v_request.id,
        'worker',p_worker,
        'version','0.6'
      );
    end if;

    update public.ascend_chat_sessions
    set current_reasoning_request_id=null,
        last_event_at=now(),
        updated_at=now()
    where id=v_session.id;

    return jsonb_build_object(
      'kind','NONCLAIM_POINTER_CLEARED',
      'session_id',v_session.id,
      'request_id',v_request.id,
      'request_status',v_request.status,
      'version','0.6'
    );
  end if;

  select r.* into v_request
  from public.ascend_reasoning_requests r
  where r.chat_session_id=v_session.id
    and r.status='claimed'
  order by r.claimed_at desc nulls last,r.updated_at desc
  limit 1
  for update skip locked;

  if not found then
    return jsonb_build_object(
      'kind','SESSION_CLEAN',
      'session_id',v_session.id,
      'version','0.6'
    );
  end if;

  select exists(
    select 1
    from public.ascend_chat_messages m
    where m.session_id=v_session.id
      and m.reasoning_request_id=v_request.id
      and m.direction='assistant_to_ascend'
      and (
        v_request.claimed_at is null
        or m.created_at>=v_request.claimed_at
      )
  ) into v_message_exists;

  if v_message_exists then
    v_status:=case
      when v_request.attempts>=v_request.max_attempts then 'blocked'
      else 'retry'
    end;

    update public.ascend_reasoning_requests
    set status=v_status,
        available_at=case when v_status='retry' then now() else available_at end,
        claimed_at=null,
        claimed_by=null,
        last_error=case
          when last_error is null then
            'Orphaned reasoning claim recovered after assistant response; resolution handshake did not complete.'
          else last_error||E'\nOrphaned reasoning claim recovered after assistant response; resolution handshake did not complete.'
        end,
        updated_at=now()
    where id=v_request.id;

    return jsonb_build_object(
      'kind','ORPHAN_RESPONSE_RECOVERED',
      'session_id',v_session.id,
      'request_id',v_request.id,
      'request_status',v_status,
      'version','0.6'
    );
  end if;

  update public.ascend_reasoning_requests
  set claimed_by=p_worker,
      claimed_at=coalesce(claimed_at,now()),
      last_error=case
        when claimed_by is distinct from p_worker then
          coalesce(last_error||E'\n','')||
          'Reasoning claim re-linked to active chat session by ASCEND lifecycle watchdog.'
        else last_error
      end,
      updated_at=now()
  where id=v_request.id;

  update public.ascend_chat_sessions
  set current_reasoning_request_id=v_request.id,
      last_event_at=now(),
      updated_at=now()
  where id=v_session.id;

  return jsonb_build_object(
    'kind','ORPHAN_CLAIM_RELINKED',
    'session_id',v_session.id,
    'request_id',v_request.id,
    'worker',p_worker,
    'version','0.6'
  );
end;
$function$;

create or replace function public.ascend_refresh_reasoning_requests(p_limit integer default 100)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_inserted integer:=0;
  v_recovered integer:=0;
  v_blocked integer:=0;
  v_pending integer:=0;
begin
  update public.ascend_reasoning_requests r
  set
    status=case when r.attempts>=r.max_attempts then 'blocked' else 'retry' end,
    available_at=case when r.attempts>=r.max_attempts then r.available_at else now() end,
    claimed_at=null,
    claimed_by=null,
    last_error=coalesce(
      r.last_error,
      'Orphaned reasoning claim recovered by ASCEND watchdog.'
    ),
    updated_at=now()
  where r.status='claimed'
    and r.claimed_at<now()-interval '3 minutes'
    and not exists(
      select 1
      from public.ascend_chat_sessions s
      where s.current_reasoning_request_id=r.id
        and s.status='active'
        and s.autopilot_enabled=true
    );

  get diagnostics v_recovered=row_count;

  insert into public.ascend_reasoning_requests(
    project_id,mission_id,analysis_id,status,priority,
    problem_type,pattern_key,rationale,context_snapshot,max_attempts
  )
  select
    a.project_id,
    a.mission_id,
    a.id,
    'pending',
    least(
      100,
      greatest(
        1,
        case e.severity
          when 'critical' then 100
          when 'error' then 90
          when 'warning' then 70
          else 50
        end
        +coalesce(m.priority,50)/10
      )
    )::integer,
    a.problem_type,
    a.pattern_key,
    a.rationale,
    jsonb_build_object(
      'analysis',jsonb_build_object(
        'classification',a.classification,
        'problem_type',a.problem_type,
        'pattern_key',a.pattern_key,
        'confidence',a.confidence,
        'signals',a.signals,
        'rationale',a.rationale
      ),
      'event',jsonb_build_object(
        'event_id',e.id,
        'event_type',e.event_type,
        'source',e.source,
        'severity',e.severity,
        'payload',e.payload,
        'occurred_at',e.occurred_at
      ),
      'mission',case when m.id is null then null else jsonb_build_object(
        'mission_code',m.mission_code,
        'title',m.title,
        'status',m.status,
        'priority',m.priority,
        'objective',m.objective,
        'next_action',m.next_action,
        'branch_name',m.branch_name,
        'pr_number',m.pr_number
      ) end
    ),
    5
  from public.ascend_event_analysis a
  join public.ascend_events e on e.id=a.event_id
  join public.ascend_projects p on p.id=a.project_id
  left join public.ascend_missions m on m.id=a.mission_id
  where a.requires_reasoning=true
    and p.status='active'
    and not exists(
      select 1
      from public.ascend_reasoning_requests r
      where r.analysis_id=a.id
    )
  order by e.occurred_at
  limit greatest(1,least(coalesce(p_limit,100),500))
  on conflict(analysis_id) do nothing;

  get diagnostics v_inserted=row_count;

  select count(*) into v_pending
  from public.ascend_reasoning_requests
  where status in ('pending','retry')
    and available_at<=now();

  select count(*) into v_blocked
  from public.ascend_reasoning_requests
  where status='blocked';

  return jsonb_build_object(
    'inserted',v_inserted,
    'stale_recovered',v_recovered,
    'available',v_pending,
    'blocked',v_blocked,
    'version','0.6',
    'at',now()
  );
end;
$function$;

create or replace function public.ascend_claim_reasoning_request_for_project(
  p_worker text,
  p_project_id uuid default null::uuid
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_request public.ascend_reasoning_requests%rowtype;
  v_project_key text;
  v_mission_code text;
  v_context jsonb;
begin
  perform public.ascend_refresh_reasoning_requests(100);

  select r.*
  into v_request
  from public.ascend_reasoning_requests r
  where r.status in ('pending','retry')
    and r.available_at<=now()
    and r.attempts<r.max_attempts
    and (p_project_id is null or r.project_id=p_project_id)
  order by r.priority desc,r.created_at
  limit 1
  for update skip locked;

  if not found then
    return jsonb_build_object(
      'kind','IDLE',
      'worker',p_worker,
      'version','0.6'
    );
  end if;

  update public.ascend_reasoning_requests
  set
    status='claimed',
    attempts=attempts+1,
    claimed_at=now(),
    claimed_by=p_worker,
    updated_at=now()
  where id=v_request.id
  returning * into v_request;

  select p.project_key,m.mission_code
  into v_project_key,v_mission_code
  from public.ascend_projects p
  left join public.ascend_missions m on m.id=v_request.mission_id
  where p.id=v_request.project_id;

  v_context:=public.ascend_project_context(v_project_key);

  return jsonb_build_object(
    'kind','REASONING_REQUEST',
    'worker',p_worker,
    'request_id',v_request.id,
    'project_id',v_request.project_id,
    'project_key',v_project_key,
    'mission_id',v_request.mission_id,
    'mission_code',v_mission_code,
    'priority',v_request.priority,
    'attempt',v_request.attempts,
    'max_attempts',v_request.max_attempts,
    'problem_type',v_request.problem_type,
    'pattern_key',v_request.pattern_key,
    'rationale',v_request.rationale,
    'request_context',v_request.context_snapshot,
    'project_context',v_context,
    'continuation_instruction',v_request.last_error,
    'previous_summary',v_request.resolution_summary,
    'version','0.6'
  );
end;
$function$;

revoke all on function public.ascend_reconcile_chat_session(uuid,text) from public,anon,authenticated;
grant execute on function public.ascend_reconcile_chat_session(uuid,text) to service_role;

comment on function public.ascend_reconcile_chat_session(uuid,text) is
  'ASCEND v0.6 lifecycle watchdog: repairs session/request drift, re-links live claims, and recovers orphaned claims after assistant responses.';
