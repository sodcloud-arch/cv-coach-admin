-- CV Coach V97 — Decision Learning Feedback Loop
-- Feeds reconciled V96 outcomes back into Coach AI prioritization without changing the recommended action.
-- Historical association is not causality. Safety and human approval remain authoritative.

-- Preserve the current public V94.1 contract behind a private boundary.
alter function public.get_coach_ai_command_center_v94(uuid)
  rename to get_coach_ai_command_center_prelearning_v97;
alter function public.get_coach_ai_command_center_prelearning_v97(uuid)
  set schema private;
revoke all on function private.get_coach_ai_command_center_prelearning_v97(uuid)
  from public,anon,authenticated;

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
  v_learning jsonb;
  v_summary jsonb;
begin
  -- Search Before Create: V97 consumes the existing V94/V96 contracts.
  -- The preserved V94.1 function keeps authentication, scope and deterministic routing authoritative.
  v_base := private.get_coach_ai_command_center_prelearning_v97(p_actor_id);

  with latest_outcome as (
    select distinct on (e.workspace_id)
      e.workspace_id,
      e.action_code,
      e.outcome_status,
      e.effectiveness_score,
      e.confidence,
      e.assessed_at
    from private.coach_action_outcome_events_v96 e
    where e.actor_id=p_actor_id
      and e.evidence_status='SUFFICIENT'
      and e.outcome_status<>'WAITING_EVIDENCE'
    order by e.workspace_id,e.assessed_at desc,e.id desc
  ), learning as (
    select
      lo.action_code,
      count(*)::int as sample_size,
      count(*) filter(where lo.outcome_status in ('RESOLVED','IMPROVED'))::int as positive,
      count(*) filter(where lo.outcome_status='MIXED')::int as mixed,
      count(*) filter(where lo.outcome_status='NO_CHANGE')::int as no_change,
      count(*) filter(where lo.outcome_status='WORSENED')::int as worsened,
      round(avg(lo.effectiveness_score)::numeric,1) as average_score,
      round(avg(lo.confidence)::numeric,3) as average_outcome_confidence,
      round(least(1::numeric,count(*)::numeric/8::numeric) * avg(lo.confidence)::numeric,3) as reliability
    from latest_outcome lo
    group by lo.action_code
  ), prepared as (
    select
      x.item,
      l.action_code,
      coalesce(l.sample_size,0) as sample_size,
      coalesce(l.positive,0) as positive,
      coalesce(l.mixed,0) as mixed,
      coalesce(l.no_change,0) as no_change,
      coalesce(l.worsened,0) as worsened,
      l.average_score,
      l.average_outcome_confidence,
      coalesce(l.reliability,0) as reliability,
      (coalesce(l.sample_size,0)>=3 and coalesce(l.average_outcome_confidence,0)>=0.55) as learning_ready,
      coalesce(nullif(x.item->>'command_score','')::int,0) as base_score
    from jsonb_array_elements(coalesce(v_base->'items','[]'::jsonb)) x(item)
    left join learning l on l.action_code=x.item->>'recommended_action_code'
  ), adjusted as (
    select
      p.*,
      case
        when not p.learning_ready then 0
        else round((coalesce(p.average_score,0)/100.0) * 12.0 * p.reliability)::int
      end as raw_adjustment
    from prepared p
  ), safe_adjusted as (
    select
      a.*,
      case
        when coalesce(a.item->>'primary_domain','')='SAFETY' then greatest(a.raw_adjustment,0)
        else greatest(-12,least(12,a.raw_adjustment))
      end as applied_adjustment
    from adjusted a
  ), enriched as (
    select
      s.*,
      greatest(0,s.base_score+s.applied_adjustment)::int as learned_score,
      case
        when not s.learning_ready then null
        else round(
          greatest(0.25::numeric,least(0.90::numeric,
            0.50::numeric
            + (coalesce(s.average_score,0)/100.0::numeric) * 0.25::numeric * s.reliability
            + 0.15::numeric * s.reliability
          )),3
        )
      end as recommendation_confidence
    from safe_adjusted s
  ), final_items as (
    select
      e.item || jsonb_build_object(
        'command_score',e.learned_score,
        'priority',case
          when coalesce(e.item->>'primary_domain','')='SAFETY' and coalesce(e.item->>'priority','')='CRITICAL' then 'CRITICAL'
          when e.learned_score>=120 then 'CRITICAL'
          when e.learned_score>=70 then 'HIGH'
          when e.learned_score>=30 then 'MEDIUM'
          else 'NORMAL'
        end,
        'decision_learning',jsonb_build_object(
          'version','DECISION_LEARNING_FEEDBACK_V97',
          'eligible',e.learning_ready,
          'sample_size',e.sample_size,
          'positive',e.positive,
          'mixed',e.mixed,
          'no_change',e.no_change,
          'worsened',e.worsened,
          'positive_rate',case when e.sample_size>0 then round(e.positive::numeric/e.sample_size,3) else null end,
          'average_effectiveness_score',e.average_score,
          'average_outcome_confidence',e.average_outcome_confidence,
          'reliability',round(e.reliability,3),
          'base_command_score',e.base_score,
          'score_adjustment',e.applied_adjustment,
          'learned_command_score',e.learned_score,
          'recommendation_confidence',e.recommendation_confidence,
          'association_pattern',case
            when e.sample_size<3 then 'INSUFFICIENT_SAMPLE'
            when e.positive::numeric/nullif(e.sample_size,0)>=0.75 then 'FAVORABLE_ASSOCIATION'
            when e.positive::numeric/nullif(e.sample_size,0)>=0.40 then 'VARIABLE_ASSOCIATION'
            else 'WEAK_ASSOCIATION'
          end,
          'safety_negative_adjustment_blocked',coalesce(e.item->>'primary_domain','')='SAFETY' and e.raw_adjustment<0,
          'action_code_unchanged',true,
          'historical_association_not_causality',true
        ),
        'source_versions',coalesce(e.item->'source_versions','[]'::jsonb) || jsonb_build_array('V96_OUTCOME_INTELLIGENCE','V97_DECISION_LEARNING'),
        'guardrails',coalesce(e.item->'guardrails','{}'::jsonb) || jsonb_build_object(
          'decision_learning_sample_gate',3,
          'decision_learning_max_score_adjustment',12,
          'decision_learning_cannot_change_action_code',true,
          'decision_learning_cannot_override_safety',true,
          'historical_association_not_causality',true,
          'coach_review_required',true,
          'auto_publish',false,
          'auto_program_edit',false
        )
      ) as item,
      e.learned_score,
      e.learning_ready,
      e.applied_adjustment
    from enriched e
  )
  select coalesce(jsonb_agg(f.item order by f.learned_score desc,lower(coalesce(f.item->>'client_name',''))),'[]'::jsonb)
  into v_items
  from final_items f;

  with latest_outcome as (
    select distinct on (e.workspace_id)
      e.workspace_id,e.action_code,e.outcome_status,e.effectiveness_score,e.confidence,e.assessed_at
    from private.coach_action_outcome_events_v96 e
    where e.actor_id=p_actor_id
      and e.evidence_status='SUFFICIENT'
      and e.outcome_status<>'WAITING_EVIDENCE'
    order by e.workspace_id,e.assessed_at desc,e.id desc
  ), learning as (
    select
      lo.action_code,
      count(*)::int as sample_size,
      count(*) filter(where lo.outcome_status in ('RESOLVED','IMPROVED'))::int as positive,
      count(*) filter(where lo.outcome_status='WORSENED')::int as worsened,
      round(avg(lo.effectiveness_score)::numeric,1) as average_score,
      round(avg(lo.confidence)::numeric,3) as average_outcome_confidence,
      round(least(1::numeric,count(*)::numeric/8::numeric) * avg(lo.confidence)::numeric,3) as reliability
    from latest_outcome lo
    group by lo.action_code
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'action_code',l.action_code,
    'sample_size',l.sample_size,
    'positive',l.positive,
    'worsened',l.worsened,
    'positive_rate',round(l.positive::numeric/nullif(l.sample_size,0),3),
    'average_effectiveness_score',l.average_score,
    'average_outcome_confidence',l.average_outcome_confidence,
    'reliability',l.reliability,
    'learning_ready',l.sample_size>=3 and l.average_outcome_confidence>=0.55
  ) order by l.sample_size desc,l.action_code),'[]'::jsonb)
  into v_learning
  from learning l;

  with x as (select value j from jsonb_array_elements(v_items))
  select jsonb_build_object(
    'total_clients',count(*),
    'critical',count(*) filter(where j->>'priority'='CRITICAL'),
    'high',count(*) filter(where j->>'priority'='HIGH'),
    'medium',count(*) filter(where j->>'priority'='MEDIUM'),
    'normal',count(*) filter(where j->>'priority'='NORMAL'),
    'requires_attention',count(*) filter(where j->>'priority' in ('CRITICAL','HIGH','MEDIUM')),
    'safety',count(*) filter(where j->>'primary_domain'='SAFETY'),
    'onboarding',count(*) filter(where j->>'primary_domain'='ONBOARDING'),
    'programming',count(*) filter(where j->>'primary_domain'='PROGRAMMING'),
    'adherence',count(*) filter(where j->>'primary_domain'='ADHERENCE'),
    'progression',count(*) filter(where j->>'primary_domain'='PROGRESSION'),
    'active_pilots',jsonb_array_length(coalesce(v_base->'pilots','[]'::jsonb)),
    'learning_applied',count(*) filter(where coalesce((j#>>'{decision_learning,eligible}')::boolean,false)),
    'learning_boosted',count(*) filter(where coalesce(nullif(j#>>'{decision_learning,score_adjustment}','')::int,0)>0),
    'learning_dampened',count(*) filter(where coalesce(nullif(j#>>'{decision_learning,score_adjustment}','')::int,0)<0)
  ) into v_summary from x;

  return v_base
    || jsonb_build_object(
      'version','COACH_AI_COMMAND_CENTER_V97',
      'contract_revision','V97_DECISION_LEARNING_FEEDBACK',
      'items',v_items,
      'summary',v_summary,
      'decision_learning_catalog',v_learning,
      'decision_learning_guardrails',jsonb_build_object(
        'minimum_sample_size',3,
        'minimum_average_outcome_confidence',0.55,
        'max_absolute_score_adjustment',12,
        'recommended_action_code_is_immutable',true,
        'negative_safety_adjustment_forbidden',true,
        'historical_association_not_causality',true,
        'coach_review_required',true,
        'auto_publish',false,
        'auto_program_edit',false,
        'auto_message',false,
        'auto_billing_mutation',false
      )
    );
end;
$function$;

revoke all on function public.get_coach_ai_command_center_v94(uuid) from public,anon;
grant execute on function public.get_coach_ai_command_center_v94(uuid) to authenticated,service_role;

comment on function public.get_coach_ai_command_center_v94(uuid) is
  'V97 Coach AI command center wrapper. Uses sample-gated V96 outcome history to modestly calibrate prioritization/confidence without changing action routing, overriding safety or automating execution.';
