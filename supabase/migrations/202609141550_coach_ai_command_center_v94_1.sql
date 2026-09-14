-- CV Coach V94.1 — deterministic routing fix for coach-required YELLOW training risk.
-- Keeps the V94 base engine intact, moves it behind a private boundary, and exposes a corrected read-only wrapper.

alter function public.get_coach_ai_command_center_v94(uuid) set schema private;
revoke all on function private.get_coach_ai_command_center_v94(uuid) from public,anon,authenticated;
grant execute on function private.get_coach_ai_command_center_v94(uuid) to service_role;

create or replace function public.get_coach_ai_command_center_v94(p_actor_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_base jsonb;
  v_items jsonb;
  v_pilots jsonb;
  v_summary jsonb;
begin
  v_base := private.get_coach_ai_command_center_v94(p_actor_id);
  v_pilots := coalesce(v_base->'pilots','[]'::jsonb);

  select coalesce(jsonb_agg(
    case
      when coalesce(nullif(x#>>'{training,requires_coach}','')::boolean,false)
        and upper(coalesce(x#>>'{training,risk_level}','GREEN'))='YELLOW'
        and coalesce(x->>'recommended_action_code','')='monitor_client'
      then jsonb_set(
        jsonb_set(
          jsonb_set(x,'{primary_domain}',to_jsonb('PROGRAMMING'::text),true),
          '{recommended_action_code}',to_jsonb('review_training_signals'::text),true
        ),
        '{recommended_action}',
        to_jsonb('Revisar las señales de entrenamiento y recuperación antes de progresar carga, volumen o dificultad.'::text),
        true
      )
      else x
    end
    order by coalesce(nullif(x->>'command_score','')::int,0) desc,lower(coalesce(x->>'client_name',''))
  ),'[]'::jsonb)
  into v_items
  from jsonb_array_elements(coalesce(v_base->'items','[]'::jsonb)) x;

  select jsonb_build_object(
    'total_clients',jsonb_array_length(v_items),
    'critical',(select count(*) from jsonb_array_elements(v_items) x where x->>'priority'='CRITICAL'),
    'high',(select count(*) from jsonb_array_elements(v_items) x where x->>'priority'='HIGH'),
    'medium',(select count(*) from jsonb_array_elements(v_items) x where x->>'priority'='MEDIUM'),
    'normal',(select count(*) from jsonb_array_elements(v_items) x where x->>'priority'='NORMAL'),
    'requires_attention',(select count(*) from jsonb_array_elements(v_items) x where x->>'priority' in ('CRITICAL','HIGH','MEDIUM')),
    'safety',(select count(*) from jsonb_array_elements(v_items) x where x->>'primary_domain'='SAFETY'),
    'onboarding',(select count(*) from jsonb_array_elements(v_items) x where x->>'primary_domain'='ONBOARDING'),
    'programming',(select count(*) from jsonb_array_elements(v_items) x where x->>'primary_domain'='PROGRAMMING'),
    'adherence',(select count(*) from jsonb_array_elements(v_items) x where x->>'primary_domain'='ADHERENCE'),
    'progression',(select count(*) from jsonb_array_elements(v_items) x where x->>'primary_domain'='PROGRESSION'),
    'active_pilots',jsonb_array_length(v_pilots)
  ) into v_summary;

  return jsonb_set(
    jsonb_set(
      jsonb_set(v_base,'{items}',v_items,true),
      '{summary}',v_summary,true
    ),
    '{contract_revision}',to_jsonb('V94.1_RISK_ROUTING'::text),true
  );
end;
$function$;

revoke all on function public.get_coach_ai_command_center_v94(uuid) from public,anon;
grant execute on function public.get_coach_ai_command_center_v94(uuid) to authenticated,service_role;

comment on function public.get_coach_ai_command_center_v94(uuid) is
  'V94.1 public Coach AI command center. Adds deterministic action routing for coach-required YELLOW training risk while remaining read-only and recommendation-only.';
