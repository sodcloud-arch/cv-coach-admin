-- CV Coach V96.1 — Outcome guardrail + due reconciliation hardening

-- Preserve V96 implementation privately, then expose a corrected public read wrapper.
alter function public.get_coach_outcome_intelligence_v96(uuid) set schema private;
alter function private.get_coach_outcome_intelligence_v96(uuid) rename to get_coach_outcome_intelligence_base_v96;
revoke all on function private.get_coach_outcome_intelligence_base_v96(uuid) from public,anon,authenticated;

create or replace function public.get_coach_outcome_intelligence_v96(p_actor_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v jsonb;
begin
  v:=private.get_coach_outcome_intelligence_base_v96(p_actor_id);
  v:=jsonb_set(v,'{guardrails,no_auto_publish}','true'::jsonb,true);
  return v;
end;
$function$;

grant execute on function public.get_coach_outcome_intelligence_v96(uuid) to authenticated,service_role;
revoke all on function public.get_coach_outcome_intelligence_v96(uuid) from public,anon;

create or replace function public.reconcile_due_coach_action_outcomes_v96(
  p_actor_id uuid,
  p_limit integer default 50
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_role public.app_role;
  v_row record;
  v_processed integer:=0;
  v_result jsonb;
begin
  if auth.uid() is null or p_actor_id is null or auth.uid()<>p_actor_id then raise exception 'Authenticated actor mismatch'; end if;
  select p.role into v_role from public.profiles p where p.id=p_actor_id and p.status='active'::public.profile_status;
  if v_role is null or v_role not in ('admin'::public.app_role,'coach'::public.app_role) then raise exception 'Coach/admin required'; end if;

  for v_row in
    with latest as (
      select distinct on (e.workspace_id) e.workspace_id,e.next_check_after,e.assessed_at
      from private.coach_action_outcome_events_v96 e
      where e.actor_id=p_actor_id
      order by e.workspace_id,e.assessed_at desc,e.id desc
    )
    select w.id
    from private.coach_action_workspace_v95 w
    left join latest l on l.workspace_id=w.id
    where w.actor_id=p_actor_id
      and w.workflow_status='COMPLETED'
      and (l.workspace_id is null or l.next_check_after<=now())
    order by coalesce(l.next_check_after,w.completed_at) asc nulls first
    limit greatest(1,least(coalesce(p_limit,50),100))
  loop
    v_result:=public.reconcile_coach_action_outcome_v96(p_actor_id,v_row.id);
    v_processed:=v_processed+1;
  end loop;

  return jsonb_build_object(
    'ok',true,
    'version','ACTION_OUTCOME_INTELLIGENCE_V96_1',
    'processed',v_processed,
    'client_state_mutated',false,
    'training_data_mutated',false,
    'program_data_mutated',false,
    'billing_data_mutated',false
  );
end;
$function$;

grant execute on function public.reconcile_due_coach_action_outcomes_v96(uuid,integer) to authenticated,service_role;
revoke all on function public.reconcile_due_coach_action_outcomes_v96(uuid,integer) from public,anon;
