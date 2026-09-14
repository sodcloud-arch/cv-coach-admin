-- CV Coach V95 — Coach Action Workspace
-- Human-controlled bridge from V94 recommendations to audited execution handoffs.
-- No automatic program edits, publishing, messaging, billing mutation or client-state mutation.

create table if not exists private.coach_action_workspace_v95 (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid not null references public.profiles(id) on delete restrict,
  client_id uuid not null references public.profiles(id) on delete restrict,
  recommendation_key text not null,
  source_version text not null default 'V94_COACH_AI',
  recommendation_snapshot jsonb not null default '{}'::jsonb,
  decision text not null default 'PENDING' check (decision in ('PENDING','ACCEPTED','MODIFIED','REJECTED')),
  workflow_status text not null default 'PENDING' check (workflow_status in ('PENDING','READY','EXECUTING','COMPLETED','REJECTED')),
  effective_action_code text not null,
  effective_action text not null,
  coach_note text,
  execution_target text,
  resolution_note text,
  completion_verification text check (completion_verification is null or completion_verification in ('coach_reported','system_reconciled')),
  decided_at timestamptz,
  execution_started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(actor_id,recommendation_key)
);

create index if not exists idx_coach_action_workspace_v95_actor_status
  on private.coach_action_workspace_v95(actor_id,workflow_status,updated_at desc);
create index if not exists idx_coach_action_workspace_v95_client
  on private.coach_action_workspace_v95(client_id,updated_at desc);

revoke all on table private.coach_action_workspace_v95 from public, anon, authenticated;

create or replace function private.coach_action_route_v95(p_action_code text)
returns text
language sql
immutable
set search_path=''
as $$
  select case
    when p_action_code in ('review_account_status','review_client_profile','review_onboarding','review_coach_assignment') then 'lifecycle'
    when p_action_code in ('create_initial_program','finish_program_draft') then 'programming'
    when p_action_code in ('review_immediately','review_deload','review_recovery','review_stagnation','review_training_signals') then 'training_trends'
    when p_action_code='review_progressions' then 'progression'
    when p_action_code='contact_inactive_client' then 'communications'
    when p_action_code='review_subscription' then 'commercial'
    else 'client_profile'
  end;
$$;

create or replace function private.current_coach_actions_v95(p_actor_id uuid)
returns table(recommendation_key text, client_id uuid, item jsonb)
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v94 jsonb;
begin
  v94 := public.get_coach_ai_command_center_v94(p_actor_id);

  return query
  with src as (
    select x as item
    from jsonb_array_elements(coalesce(v94->'items','[]'::jsonb)) x
  ), actionable as (
    select s.item,
      (s.item->>'client_id')::uuid as client_id,
      case
        when nullif(s.item#>>'{training,days_since_workout}','') is null then 'none'
        when (s.item#>>'{training,days_since_workout}')::int < 7 then '0_6'
        when (s.item#>>'{training,days_since_workout}')::int < 14 then '7_13'
        when (s.item#>>'{training,days_since_workout}')::int < 21 then '14_20'
        else '21_plus'
      end as inactivity_bucket
    from src s
    where coalesce(s.item->>'recommended_action_code','monitor_client') <> 'monitor_client'
       or coalesce(s.item->>'priority','NORMAL') <> 'NORMAL'
  )
  select
    'v95:'||a.client_id::text||':'||md5(jsonb_build_object(
      'action_code',a.item->>'recommended_action_code',
      'domain',a.item->>'primary_domain',
      'lifecycle_stage',a.item#>>'{lifecycle,stage}',
      'risk_level',a.item#>>'{training,risk_level}',
      'critical_alerts',a.item#>>'{training,critical_alerts}',
      'warning_alerts',a.item#>>'{training,warning_alerts}',
      'pending_progressions',a.item#>>'{training,pending_progressions}',
      'adaptation_state',a.item#>>'{training,adaptation_state}',
      'deload_recommended',a.item#>>'{training,deload_recommended}',
      'recovery_flags',a.item#>>'{training,recovery_flags}',
      'stagnation_signals',a.item#>>'{training,stagnation_signals}',
      'inactivity_bucket',a.inactivity_bucket
    )::text) as recommendation_key,
    a.client_id,
    a.item
  from actionable a;
end;
$function$;

revoke all on function private.current_coach_actions_v95(uuid) from public, anon, authenticated;
revoke all on function private.coach_action_route_v95(text) from public, anon, authenticated;

create or replace function public.get_coach_action_workspace_v95(p_actor_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_role public.app_role;
  v_current jsonb;
  v_history jsonb;
  v_summary jsonb;
begin
  if auth.uid() is null or p_actor_id is null or auth.uid() <> p_actor_id then
    raise exception 'Authenticated actor mismatch';
  end if;

  select p.role into v_role from public.profiles p
  where p.id=p_actor_id and p.status='active'::public.profile_status;
  if v_role is null or v_role not in ('admin'::public.app_role,'coach'::public.app_role) then
    raise exception 'Coach/admin required';
  end if;

  with cur as (
    select c.recommendation_key,c.client_id,c.item,w.id as workspace_id,w.decision,w.workflow_status,
           w.effective_action_code,w.effective_action,w.coach_note,w.execution_target,
           w.decided_at,w.execution_started_at,w.completed_at,w.updated_at
    from private.current_coach_actions_v95(p_actor_id) c
    left join private.coach_action_workspace_v95 w
      on w.actor_id=p_actor_id and w.recommendation_key=c.recommendation_key
  )
  select coalesce(jsonb_agg(
    c.item || jsonb_build_object(
      'recommendation_key',c.recommendation_key,
      'workspace_id',c.workspace_id,
      'decision',coalesce(c.decision,'PENDING'),
      'workflow_status',coalesce(c.workflow_status,'PENDING'),
      'effective_action_code',coalesce(c.effective_action_code,c.item->>'recommended_action_code'),
      'effective_action',coalesce(c.effective_action,c.item->>'recommended_action'),
      'coach_note',c.coach_note,
      'execution_target',coalesce(c.execution_target,private.coach_action_route_v95(c.item->>'recommended_action_code')),
      'decided_at',c.decided_at,
      'execution_started_at',c.execution_started_at,
      'completed_at',c.completed_at,
      'workspace_updated_at',c.updated_at
    ) order by
      case c.item->>'priority' when 'CRITICAL' then 0 when 'HIGH' then 1 when 'MEDIUM' then 2 else 3 end,
      coalesce((c.item->>'command_score')::int,0) desc,
      lower(coalesce(c.item->>'client_name',''))
  ),'[]'::jsonb) into v_current
  from cur c;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',w.id,
    'client_id',w.client_id,
    'recommendation_key',w.recommendation_key,
    'decision',w.decision,
    'workflow_status',w.workflow_status,
    'effective_action_code',w.effective_action_code,
    'effective_action',w.effective_action,
    'coach_note',w.coach_note,
    'execution_target',w.execution_target,
    'resolution_note',w.resolution_note,
    'completion_verification',w.completion_verification,
    'recommendation_snapshot',w.recommendation_snapshot,
    'decided_at',w.decided_at,
    'execution_started_at',w.execution_started_at,
    'completed_at',w.completed_at,
    'updated_at',w.updated_at
  ) order by w.updated_at desc),'[]'::jsonb)
  into v_history
  from (select * from private.coach_action_workspace_v95 where actor_id=p_actor_id order by updated_at desc limit 100) w;

  with x as (select value as j from jsonb_array_elements(v_current))
  select jsonb_build_object(
    'total',count(*),
    'pending',count(*) filter(where j->>'workflow_status'='PENDING'),
    'ready',count(*) filter(where j->>'workflow_status'='READY'),
    'executing',count(*) filter(where j->>'workflow_status'='EXECUTING'),
    'critical',count(*) filter(where j->>'priority'='CRITICAL'),
    'high',count(*) filter(where j->>'priority'='HIGH')
  ) into v_summary from x;

  return jsonb_build_object(
    'version','COACH_ACTION_WORKSPACE_V95',
    'actor_id',p_actor_id,
    'current',v_current,
    'history',v_history,
    'summary',coalesce(v_summary,'{}'::jsonb),
    'guardrails',jsonb_build_object(
      'human_decision_required',true,
      'auto_publish',false,
      'auto_program_edit',false,
      'auto_message',false,
      'auto_billing_mutation',false,
      'execution_is_handoff_only',true,
      'completion_is_coach_reported',true,
      'source_of_truth','V94_COACH_AI'
    )
  );
end;
$function$;

create or replace function public.decide_coach_action_v95(
  p_actor_id uuid,
  p_recommendation_key text,
  p_client_id uuid,
  p_decision text,
  p_modified_action_code text default null,
  p_modified_action text default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_role public.app_role;
  v_item jsonb;
  v_current_key text;
  v_effective_code text;
  v_effective_action text;
  v_id uuid;
  v_status text;
begin
  if auth.uid() is null or p_actor_id is null or auth.uid() <> p_actor_id then raise exception 'Authenticated actor mismatch'; end if;
  if upper(coalesce(p_decision,'')) not in ('ACCEPTED','MODIFIED','REJECTED') then raise exception 'Invalid decision'; end if;

  select p.role into v_role from public.profiles p where p.id=p_actor_id and p.status='active'::public.profile_status;
  if v_role is null or v_role not in ('admin'::public.app_role,'coach'::public.app_role) then raise exception 'Coach/admin required'; end if;
  if v_role='coach'::public.app_role and not exists(
    select 1 from public.coach_clients cc where cc.coach_id=p_actor_id and cc.client_id=p_client_id and cc.status='active'::public.coach_client_status
  ) then raise exception 'Client outside coach scope'; end if;

  select c.recommendation_key,c.item into v_current_key,v_item
  from private.current_coach_actions_v95(p_actor_id) c
  where c.recommendation_key=p_recommendation_key and c.client_id=p_client_id;
  if v_item is null then raise exception 'Recommendation is stale or no longer actionable'; end if;

  if upper(p_decision)='MODIFIED' and nullif(btrim(coalesce(p_modified_action,'')),'') is null then
    raise exception 'Modified action text is required';
  end if;

  v_effective_code := case when upper(p_decision)='MODIFIED' then coalesce(nullif(btrim(p_modified_action_code),''),'custom_coach_action') else v_item->>'recommended_action_code' end;
  v_effective_action := case when upper(p_decision)='MODIFIED' then btrim(p_modified_action) else v_item->>'recommended_action' end;
  v_status := case when upper(p_decision)='REJECTED' then 'REJECTED' else 'READY' end;

  insert into private.coach_action_workspace_v95(
    actor_id,client_id,recommendation_key,recommendation_snapshot,decision,workflow_status,
    effective_action_code,effective_action,coach_note,execution_target,decided_at,updated_at
  ) values(
    p_actor_id,p_client_id,p_recommendation_key,v_item,upper(p_decision),v_status,
    v_effective_code,v_effective_action,nullif(btrim(coalesce(p_note,'')),''),private.coach_action_route_v95(v_effective_code),now(),now()
  )
  on conflict(actor_id,recommendation_key) do update set
    client_id=excluded.client_id,
    recommendation_snapshot=excluded.recommendation_snapshot,
    decision=excluded.decision,
    workflow_status=excluded.workflow_status,
    effective_action_code=excluded.effective_action_code,
    effective_action=excluded.effective_action,
    coach_note=excluded.coach_note,
    execution_target=excluded.execution_target,
    resolution_note=null,
    completion_verification=null,
    decided_at=now(),execution_started_at=null,completed_at=null,updated_at=now()
  returning id into v_id;

  return jsonb_build_object(
    'ok',true,'workspace_id',v_id,'decision',upper(p_decision),'workflow_status',v_status,
    'effective_action_code',v_effective_code,'effective_action',v_effective_action,
    'execution_target',private.coach_action_route_v95(v_effective_code),
    'client_data_mutated',false,'training_data_mutated',false,'program_data_mutated',false,
    'auto_publish',false,'auto_program_edit',false
  );
end;
$function$;

create or replace function public.start_coach_action_v95(p_actor_id uuid,p_workspace_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare v_row private.coach_action_workspace_v95%rowtype;
begin
  if auth.uid() is null or p_actor_id is null or auth.uid() <> p_actor_id then raise exception 'Authenticated actor mismatch'; end if;
  select * into v_row from private.coach_action_workspace_v95 where id=p_workspace_id and actor_id=p_actor_id for update;
  if v_row.id is null then raise exception 'Workspace action not found'; end if;
  if v_row.decision not in ('ACCEPTED','MODIFIED') or v_row.workflow_status not in ('READY','EXECUTING') then raise exception 'Action must be accepted or modified before execution'; end if;

  update private.coach_action_workspace_v95 set workflow_status='EXECUTING',execution_started_at=coalesce(execution_started_at,now()),updated_at=now() where id=v_row.id;
  return jsonb_build_object(
    'ok',true,'workspace_id',v_row.id,'client_id',v_row.client_id,
    'workflow_status','EXECUTING','execution_target',v_row.execution_target,
    'effective_action_code',v_row.effective_action_code,'effective_action',v_row.effective_action,
    'handoff_only',true,'side_effect_executed',false,'coach_must_execute_in_target_module',true
  );
end;
$function$;

create or replace function public.complete_coach_action_v95(
  p_actor_id uuid,p_workspace_id uuid,p_resolution_note text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare v_row private.coach_action_workspace_v95%rowtype;
begin
  if auth.uid() is null or p_actor_id is null or auth.uid() <> p_actor_id then raise exception 'Authenticated actor mismatch'; end if;
  if nullif(btrim(coalesce(p_resolution_note,'')),'') is null then raise exception 'Resolution note required'; end if;
  select * into v_row from private.coach_action_workspace_v95 where id=p_workspace_id and actor_id=p_actor_id for update;
  if v_row.id is null then raise exception 'Workspace action not found'; end if;
  if v_row.workflow_status not in ('READY','EXECUTING') then raise exception 'Action is not executable'; end if;

  update private.coach_action_workspace_v95
  set workflow_status='COMPLETED',resolution_note=btrim(p_resolution_note),completion_verification='coach_reported',completed_at=now(),updated_at=now()
  where id=v_row.id;

  return jsonb_build_object(
    'ok',true,'workspace_id',v_row.id,'workflow_status','COMPLETED',
    'completion_verification','coach_reported','underlying_side_effect_verified',false,
    'auto_publish',false,'auto_program_edit',false
  );
end;
$function$;

revoke all on function public.get_coach_action_workspace_v95(uuid) from public, anon;
revoke all on function public.decide_coach_action_v95(uuid,text,uuid,text,text,text,text) from public, anon;
revoke all on function public.start_coach_action_v95(uuid,uuid) from public, anon;
revoke all on function public.complete_coach_action_v95(uuid,uuid,text) from public, anon;
grant execute on function public.get_coach_action_workspace_v95(uuid) to authenticated;
grant execute on function public.decide_coach_action_v95(uuid,text,uuid,text,text,text,text) to authenticated;
grant execute on function public.start_coach_action_v95(uuid,uuid) to authenticated;
grant execute on function public.complete_coach_action_v95(uuid,uuid,text) to authenticated;
