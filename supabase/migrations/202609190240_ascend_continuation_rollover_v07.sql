-- ASCEND NEXUS · Continuation Request Rollover v0.7
-- CONTINUE must close the current reasoning request and create a fresh request
-- for the current active mission instead of consuming retry attempts on the same request.

create or replace function public.ascend_continue_reasoning_request(
  p_request_id uuid,
  p_worker text,
  p_summary text,
  p_next_instruction text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_request public.ascend_reasoning_requests%rowtype;
  v_mission public.ascend_missions%rowtype;
  v_project public.ascend_projects%rowtype;
  v_event_id uuid;
  v_analysis_id uuid;
  v_next_request_id uuid;
  v_pattern_key text;
  v_summary text:=nullif(btrim(coalesce(p_summary,'')),'');
  v_next text:=nullif(btrim(coalesce(p_next_instruction,'')),'');
begin
  if p_request_id is null or nullif(btrim(coalesce(p_worker,'')),'') is null then
    raise exception 'request_id and worker are required';
  end if;

  select * into v_request
  from public.ascend_reasoning_requests
  where id=p_request_id
  for update;

  if not found then
    raise exception 'ASCEND reasoning request not found';
  end if;

  if v_request.status<>'claimed' then
    raise exception 'ASCEND reasoning request is not claimed';
  end if;

  if v_request.claimed_by is distinct from p_worker then
    raise exception 'ASCEND reasoning worker mismatch';
  end if;

  select * into v_project
  from public.ascend_projects
  where id=v_request.project_id;

  select * into v_mission
  from public.ascend_missions m
  where m.project_id=v_request.project_id
    and m.status='active'
    and m.blocked_reason is null
  order by m.priority desc,m.updated_at desc,m.created_at desc
  limit 1;

  update public.ascend_reasoning_requests
  set status='resolved',
      resolution_summary=coalesce(v_summary,'Autonomous continuation cycle completed.'),
      last_error=null,
      claimed_at=null,
      claimed_by=null,
      resolved_at=now(),
      updated_at=now()
  where id=v_request.id;

  update public.ascend_event_analysis
  set requires_reasoning=false
  where id=v_request.analysis_id;

  insert into public.ascend_events(
    project_id,mission_id,event_type,source,severity,payload,processed_at
  )
  values(
    v_request.project_id,
    v_request.mission_id,
    'reasoning_continued',
    'system',
    'notice',
    jsonb_build_object(
      'reasoning_request_id',v_request.id,
      'resolution','resolved',
      'summary',v_summary,
      'next_instruction',v_next,
      'worker',p_worker,
      'attempts',v_request.attempts,
      'rolled_over',true,
      'version','0.7'
    ),
    now()
  );

  if v_mission.id is null then
    return jsonb_build_object(
      'kind','CONTINUATION_COMPLETE_NO_ACTIVE_MISSION',
      'request_id',v_request.id,
      'status','resolved',
      'next_request_id',null,
      'version','0.7'
    );
  end if;

  v_pattern_key:='autonomous_continuation::'||lower(v_mission.mission_code);

  insert into public.ascend_events(
    project_id,mission_id,event_type,source,severity,payload
  )
  values(
    v_request.project_id,
    v_mission.id,
    'PROJECT_CONTINUATION_REQUIRED',
    'chatgpt',
    'notice',
    jsonb_build_object(
      'project',v_project.name,
      'project_key',v_project.project_key,
      'mission_code',v_mission.mission_code,
      'predecessor_request_id',v_request.id,
      'summary',v_summary,
      'next_action',coalesce(v_next,v_mission.next_action),
      'autonomy','continue unless a genuine human-only blocker exists',
      'work_type',v_mission.work_type,
      'version','0.7'
    )
  )
  returning id into v_event_id;

  insert into public.ascend_event_analysis(
    event_id,project_id,mission_id,classification,problem_type,
    pattern_key,matched_playbook_id,confidence,requires_reasoning,
    rationale,signals
  )
  values(
    v_event_id,
    v_request.project_id,
    v_mission.id,
    'development_continuation',
    'autonomous_continuation',
    v_pattern_key,
    null,
    1.0000,
    true,
    'Continue the current active mission autonomously from the latest ASCEND CORE state.',
    jsonb_build_array(
      'source:chatgpt',
      'event:PROJECT_CONTINUATION_REQUIRED',
      'mission:'||v_mission.mission_code,
      'fresh_reasoning_request:true'
    )
  )
  returning id into v_analysis_id;

  update public.ascend_events
  set processed_at=now()
  where id=v_event_id;

  insert into public.ascend_reasoning_requests(
    project_id,mission_id,analysis_id,status,priority,
    problem_type,pattern_key,rationale,context_snapshot,
    max_attempts,available_at,chat_session_id
  )
  values(
    v_request.project_id,
    v_mission.id,
    v_analysis_id,
    'pending',
    greatest(1,least(100,coalesce(v_mission.priority,50))),
    'autonomous_continuation',
    v_pattern_key,
    'Continue the current active mission autonomously from the latest ASCEND CORE state.',
    jsonb_build_object(
      'event',jsonb_build_object(
        'event_id',v_event_id,
        'event_type','PROJECT_CONTINUATION_REQUIRED',
        'source','chatgpt',
        'severity','notice',
        'payload',jsonb_build_object(
          'predecessor_request_id',v_request.id,
          'summary',v_summary,
          'next_action',coalesce(v_next,v_mission.next_action)
        )
      ),
      'mission',jsonb_build_object(
        'mission_code',v_mission.mission_code,
        'title',v_mission.title,
        'status',v_mission.status,
        'priority',v_mission.priority,
        'objective',v_mission.objective,
        'next_action',v_mission.next_action,
        'branch_name',v_mission.branch_name,
        'pr_number',v_mission.pr_number
      ),
      'rollover',jsonb_build_object(
        'predecessor_request_id',v_request.id,
        'summary',v_summary,
        'next_instruction',v_next,
        'version','0.7'
      )
    ),
    5,
    now(),
    v_request.chat_session_id
  )
  returning id into v_next_request_id;

  return jsonb_build_object(
    'kind','CONTINUATION_ROLLED_OVER',
    'request_id',v_request.id,
    'status','resolved',
    'next_request_id',v_next_request_id,
    'mission_id',v_mission.id,
    'mission_code',v_mission.mission_code,
    'attempts_reset',true,
    'version','0.7'
  );
end;
$function$;

create or replace function public.ascend_resolve_reasoning_request(
  p_request_id uuid,
  p_worker text,
  p_resolution text,
  p_summary text default null::text,
  p_decision_id uuid default null::uuid,
  p_error text default null::text,
  p_retry_after_seconds integer default 900
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_request public.ascend_reasoning_requests%rowtype;
  v_new_status text;
  v_event_type text;
begin
  if p_resolution not in ('resolved','retry','blocked','dismissed') then
    raise exception 'invalid ASCEND reasoning resolution';
  end if;

  select * into v_request
  from public.ascend_reasoning_requests
  where id=p_request_id
  for update;

  if not found then raise exception 'ASCEND reasoning request not found'; end if;

  if v_request.status<>'claimed' then
    raise exception 'ASCEND reasoning request is not claimed';
  end if;

  if v_request.claimed_by is distinct from p_worker then
    raise exception 'ASCEND reasoning worker mismatch';
  end if;

  v_new_status:=case
    when p_resolution='retry' and v_request.attempts>=v_request.max_attempts then 'blocked'
    else p_resolution
  end;

  update public.ascend_reasoning_requests
  set
    status=v_new_status,
    resolution_summary=p_summary,
    resolution_decision_id=p_decision_id,
    last_error=p_error,
    available_at=case
      when v_new_status='retry'
        then now()+make_interval(secs=>greatest(60,least(coalesce(p_retry_after_seconds,900),86400)))
      else available_at
    end,
    claimed_at=null,
    claimed_by=null,
    resolved_at=case when v_new_status in ('resolved','dismissed') then now() else null end,
    updated_at=now()
  where id=p_request_id
  returning * into v_request;

  if v_new_status in ('resolved','dismissed') then
    update public.ascend_event_analysis
    set requires_reasoning=false
    where id=v_request.analysis_id;
  end if;

  v_event_type:=case v_new_status
    when 'resolved' then 'reasoning_resolved'
    when 'retry' then 'reasoning_retry'
    when 'blocked' then 'reasoning_blocked'
    else 'reasoning_dismissed'
  end;

  insert into public.ascend_events(
    project_id,mission_id,event_type,source,severity,payload
  )
  values(
    v_request.project_id,
    v_request.mission_id,
    v_event_type,
    'system',
    'notice',
    jsonb_build_object(
      'reasoning_request_id',v_request.id,
      'resolution',v_new_status,
      'summary',p_summary,
      'decision_id',p_decision_id,
      'error',p_error,
      'worker',p_worker,
      'attempts',v_request.attempts,
      'attention_required',v_new_status='blocked',
      'version','0.7'
    )
  );

  return jsonb_build_object(
    'request_id',v_request.id,
    'status',v_new_status,
    'attempts',v_request.attempts,
    'resolved_at',v_request.resolved_at,
    'version','0.7'
  );
end;
$function$;

revoke all on function public.ascend_continue_reasoning_request(uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.ascend_continue_reasoning_request(uuid,text,text,text) to service_role;

comment on function public.ascend_continue_reasoning_request(uuid,text,text,text)
is 'ASCEND v0.7 continuation rollover: resolves the current cycle and queues a fresh reasoning request for the latest active mission with attempts reset.';

comment on function public.ascend_resolve_reasoning_request(uuid,text,text,text,uuid,text,integer)
is 'ASCEND v0.7 resolution lifecycle. Blocked outcomes are recorded as notice events to avoid recursive reasoning warnings.';
