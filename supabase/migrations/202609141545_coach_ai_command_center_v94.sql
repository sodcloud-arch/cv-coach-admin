-- CV Coach V94 — Coach AI Unified Command Center
-- Read-only orchestration over V86 Coach Intelligence + V93 Client Lifecycle.
-- Safety invariants: recommendations only, no automatic publishing, no automatic program edits,
-- no synthetic client identities, and no mutation of client/training data.

create or replace function public.get_coach_ai_command_center_v94(p_actor_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_role public.app_role;
  v86 jsonb;
  v93 jsonb;
  v_items jsonb;
  v_pilots jsonb;
  v_summary jsonb;
begin
  if auth.uid() is null or p_actor_id is null or auth.uid() <> p_actor_id then
    raise exception 'Authenticated actor mismatch';
  end if;

  select p.role into v_role
  from public.profiles p
  where p.id=p_actor_id
    and p.status='active'::public.profile_status;

  if v_role is null or v_role not in ('admin'::public.app_role,'coach'::public.app_role) then
    raise exception 'Coach/admin required';
  end if;

  -- Search Before Create: V94 consumes the existing engines instead of duplicating their logic.
  v86 := public.get_coach_intelligence_dashboard_v86(p_actor_id);
  v93 := public.get_client_lifecycle_center_v93(p_actor_id);

  with lifecycle as (
    select x as item
    from jsonb_array_elements(coalesce(v93->'items','[]'::jsonb)) x
  ), attention as (
    select x->>'client_id' as client_id, x as item
    from jsonb_array_elements(coalesce(v86->'attention','[]'::jsonb)) x
  ), alert_agg as (
    select
      x->>'client_id' as client_id,
      count(*)::int as open_alerts,
      count(*) filter (where lower(coalesce(x->>'severity',''))='critical')::int as critical_alerts,
      count(*) filter (where lower(coalesce(x->>'severity',''))='warning')::int as warning_alerts,
      coalesce(jsonb_agg(jsonb_build_object(
        'id',x->>'id',
        'type',x->>'alert_type',
        'severity',x->>'severity',
        'title',x->>'title',
        'message',x->>'message',
        'created_at',x->>'created_at'
      ) order by case lower(coalesce(x->>'severity','')) when 'critical' then 0 when 'warning' then 1 else 2 end),'[]'::jsonb) as alerts
    from jsonb_array_elements(coalesce(v86->'alerts','[]'::jsonb)) x
    group by x->>'client_id'
  ), progression_agg as (
    select
      x->>'client_id' as client_id,
      count(*)::int as pending_progressions,
      coalesce(jsonb_agg(jsonb_build_object(
        'id',x->>'id',
        'exercise_name',x->>'exercise_name',
        'action',x->>'action',
        'reason_text',x->>'reason_text',
        'confidence',x->>'confidence',
        'confidence_band',x->>'confidence_band',
        'created_at',x->>'created_at'
      )),'[]'::jsonb) as progressions
    from jsonb_array_elements(coalesce(v86->'progressions','[]'::jsonb)) x
    group by x->>'client_id'
  ), adaptation_ranked as (
    select
      x->>'client_id' as client_id,
      x as item,
      row_number() over (
        partition by x->>'client_id'
        order by nullif(x->>'created_at','')::timestamptz desc nulls last
      ) as rn
    from jsonb_array_elements(coalesce(v86->'adaptations','[]'::jsonb)) x
  ), combined as (
    select
      l.item,
      a.item as attention,
      coalesce(aa.open_alerts,0) as open_alerts,
      coalesce(aa.critical_alerts,0) as critical_alerts,
      coalesce(aa.warning_alerts,0) as warning_alerts,
      coalesce(aa.alerts,'[]'::jsonb) as alerts,
      coalesce(pa.pending_progressions,0) as pending_progressions,
      coalesce(pa.progressions,'[]'::jsonb) as progressions,
      ar.item as adaptation,
      coalesce(nullif(a.item->>'attention_score','')::int,0) as base_attention_score,
      coalesce(nullif(a.item->>'days_since_workout','')::int,null) as days_since_workout,
      coalesce(a.item->>'risk_level','GREEN') as risk_level,
      coalesce(nullif(a.item->>'requires_coach','')::boolean,false) as requires_coach,
      a.item->>'risk_reason' as risk_reason,
      coalesce(nullif(ar.item->>'recovery_flags','')::int,0) as recovery_flags,
      coalesce(nullif(ar.item->>'stagnation_signals','')::int,0) as stagnation_signals,
      coalesce(nullif(ar.item->>'progress_signals','')::int,0) as progress_signals,
      coalesce(nullif(ar.item->>'deload_recommended','')::boolean,false) as deload_recommended,
      coalesce(ar.item->>'state','') as adaptation_state,
      case l.item->>'lifecycle_stage'
        when 'account_blocked' then 100
        when 'profile_incomplete' then 60
        when 'onboarding_review' then 50
        when 'coach_assignment' then 45
        when 'program_needed' then 40
        when 'program_draft' then 35
        when 'needs_review' then 35
        when 'onboarding_in_progress' then 15
        else 0
      end as lifecycle_weight,
      case coalesce(l.item->>'subscription_status','')
        when 'past_due' then 25
        when 'cancelled' then 15
        when 'ended' then 15
        when 'pending' then 5
        else 0
      end as commercial_weight
    from lifecycle l
    left join attention a on a.client_id=l.item->>'client_id'
    left join alert_agg aa on aa.client_id=l.item->>'client_id'
    left join progression_agg pa on pa.client_id=l.item->>'client_id'
    left join adaptation_ranked ar on ar.client_id=l.item->>'client_id' and ar.rn=1
  ), scored as (
    select
      c.*,
      greatest(0,
        c.base_attention_score
        + c.lifecycle_weight
        + c.commercial_weight
        + case when c.deload_recommended then 50 else 0 end
        + least(c.recovery_flags,3)*10
        + least(c.stagnation_signals,3)*7
      )::int as command_score
    from combined c
  ), resolved as (
    select
      s.*,
      case
        when s.critical_alerts>0 or (s.requires_coach and upper(s.risk_level)='RED') then 'SAFETY'
        when s.item->>'lifecycle_stage' in ('account_blocked','profile_incomplete','onboarding_in_progress','onboarding_review','coach_assignment') then 'ONBOARDING'
        when s.item->>'lifecycle_stage' in ('program_needed','program_draft') or s.deload_recommended or s.recovery_flags>0 or s.stagnation_signals>0 then 'PROGRAMMING'
        when s.days_since_workout is null or s.days_since_workout>=14 then 'ADHERENCE'
        when s.pending_progressions>0 then 'PROGRESSION'
        when s.item->>'subscription_status' in ('past_due','cancelled','ended') then 'COMMERCIAL'
        else 'MONITORING'
      end as primary_domain,
      case
        when s.critical_alerts>0 or (s.requires_coach and upper(s.risk_level)='RED') then 'review_immediately'
        when s.item->>'lifecycle_stage'='account_blocked' then 'review_account_status'
        when s.item->>'lifecycle_stage'='profile_incomplete' then 'review_client_profile'
        when s.item->>'lifecycle_stage'='onboarding_review' then 'review_onboarding'
        when s.item->>'lifecycle_stage'='coach_assignment' then 'review_coach_assignment'
        when s.item->>'lifecycle_stage'='program_draft' then 'finish_program_draft'
        when s.item->>'lifecycle_stage'='program_needed' then 'create_initial_program'
        when s.deload_recommended then 'review_deload'
        when s.recovery_flags>0 then 'review_recovery'
        when s.days_since_workout is null or s.days_since_workout>=14 then 'contact_inactive_client'
        when s.pending_progressions>0 then 'review_progressions'
        when s.stagnation_signals>0 then 'review_stagnation'
        when s.item->>'subscription_status'='past_due' then 'review_subscription'
        else coalesce(nullif(s.item->>'next_action',''),'monitor_client')
      end as recommended_action_code,
      case
        when s.critical_alerts>0 or (s.requires_coach and upper(s.risk_level)='RED') then 'Revisar inmediatamente las señales críticas antes de modificar entrenamiento.'
        when s.item->>'lifecycle_stage'='account_blocked' then 'Revisar el estado de la cuenta antes de continuar el servicio.'
        when s.item->>'lifecycle_stage'='profile_incomplete' then 'Completar o revisar la ficha del cliente.'
        when s.item->>'lifecycle_stage'='onboarding_review' then 'Revisar y resolver el onboarding pendiente.'
        when s.item->>'lifecycle_stage'='coach_assignment' then 'Completar la relación coach-cliente.'
        when s.item->>'lifecycle_stage'='program_draft' then 'Revisar y terminar el borrador; no publicar sin aprobación explícita.'
        when s.item->>'lifecycle_stage'='program_needed' then 'Crear el programa inicial usando los datos aprobados del onboarding.'
        when s.deload_recommended then 'Revisar la evidencia adaptativa y decidir si corresponde un deload.'
        when s.recovery_flags>0 then 'Revisar recuperación y fatiga antes de progresar carga o volumen.'
        when s.days_since_workout is null or s.days_since_workout>=14 then 'Contactar al cliente por inactividad y confirmar barreras de adherencia.'
        when s.pending_progressions>0 then 'Revisar las progresiones pendientes y aprobar solo las respaldadas por evidencia.'
        when s.stagnation_signals>0 then 'Revisar estancamiento y tendencias antes de cambiar la programación.'
        when s.item->>'subscription_status'='past_due' then 'Revisar la situación de suscripción sin alterar automáticamente el servicio.'
        else 'Mantener seguimiento normal y esperar nueva evidencia.'
      end as recommended_action
    from scored s
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'client_id',r.item->>'client_id',
      'client_name',r.item->>'client_name',
      'email',r.item->>'email',
      'primary_goal',r.item->>'primary_goal',
      'priority',case when r.command_score>=120 then 'CRITICAL' when r.command_score>=70 then 'HIGH' when r.command_score>=30 then 'MEDIUM' else 'NORMAL' end,
      'command_score',r.command_score,
      'primary_domain',r.primary_domain,
      'recommended_action_code',r.recommended_action_code,
      'recommended_action',r.recommended_action,
      'reasons',to_jsonb(array_remove(array[
        case when r.item->>'lifecycle_stage'<>'operational' then 'Ciclo de vida: '||replace(coalesce(r.item->>'lifecycle_stage','revisar'),'_',' ') end,
        case when r.critical_alerts>0 then r.critical_alerts||' alerta(s) crítica(s) abierta(s)' end,
        case when r.warning_alerts>0 then r.warning_alerts||' alerta(s) de advertencia' end,
        case when r.risk_reason is not null and r.risk_reason<>'' then r.risk_reason end,
        case when r.days_since_workout is null then 'Sin sesión registrada' when r.days_since_workout>=7 then r.days_since_workout||' días desde la última sesión' end,
        case when r.pending_progressions>0 then r.pending_progressions||' progresión(es) pendiente(s)' end,
        case when r.deload_recommended then 'Motor adaptativo recomienda revisar deload' end,
        case when r.recovery_flags>0 then r.recovery_flags||' señal(es) de recuperación/fatiga' end,
        case when r.stagnation_signals>0 then r.stagnation_signals||' señal(es) de estancamiento' end,
        case when r.item->>'subscription_status'='past_due' then 'Suscripción vencida' end
      ]::text[],null)),
      'lifecycle',jsonb_build_object(
        'stage',r.item->>'lifecycle_stage',
        'next_action',r.item->>'next_action',
        'access_state',r.item->>'access_state',
        'onboarding_status',r.item->>'onboarding_status',
        'coach_relationship_status',r.item->>'coach_relationship_status',
        'active_program_id',r.item->>'active_program_id',
        'draft_program_id',r.item->>'draft_program_id',
        'subscription_status',r.item->>'subscription_status',
        'plan_name',r.item->>'plan_name'
      ),
      'training',jsonb_build_object(
        'attention_score',r.base_attention_score,
        'risk_level',r.risk_level,
        'requires_coach',r.requires_coach,
        'days_since_workout',r.days_since_workout,
        'open_alerts',r.open_alerts,
        'critical_alerts',r.critical_alerts,
        'warning_alerts',r.warning_alerts,
        'pending_progressions',r.pending_progressions,
        'adaptation_state',nullif(r.adaptation_state,''),
        'progress_signals',r.progress_signals,
        'stagnation_signals',r.stagnation_signals,
        'recovery_flags',r.recovery_flags,
        'deload_recommended',r.deload_recommended
      ),
      'alerts',r.alerts,
      'progressions',r.progressions,
      'adaptation',coalesce(r.adaptation,'{}'::jsonb),
      'source_versions',jsonb_build_array('V86_COACH_INTELLIGENCE','CLIENT_LIFECYCLE_CONTROL_V93'),
      'guardrails',jsonb_build_object(
        'recommendation_only',true,
        'read_only_aggregate',true,
        'auto_publish',false,
        'auto_program_edit',false,
        'no_synthetic_identity',true,
        'coach_review_required',true
      )
    ) order by r.command_score desc,lower(coalesce(r.item->>'client_name',''))
  ),'[]'::jsonb)
  into v_items
  from resolved r;

  select coalesce(jsonb_agg(jsonb_build_object(
    'pilot_id',p->>'id',
    'client_id',p->>'client_id',
    'subject_label',p->>'subject_label',
    'source_system',p->>'source_system',
    'status',p->>'status',
    'ready_for_v85',coalesce(nullif(p->>'ready_for_v85','')::boolean,false),
    'next_action',p->>'next_action',
    'baseline_snapshot',coalesce(p->'baseline_snapshot','{}'::jsonb),
    'priority',case
      when coalesce(nullif(p->>'ready_for_v85','')::boolean,false) and p->>'client_id' is null then 'MEDIUM'
      when p->>'status'='collecting_baseline' then 'NORMAL'
      else 'NORMAL'
    end,
    'guardrails',jsonb_build_object('observed_only',true,'no_synthetic_identity',true,'no_auto_action',true)
  ) order by case when p->>'status'='collecting_baseline' then 1 else 0 end desc,p->>'subject_label'),'[]'::jsonb)
  into v_pilots
  from jsonb_array_elements(coalesce(v86->'pilots','[]'::jsonb)) p;

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

  return jsonb_build_object(
    'ok',true,
    'engine_version','COACH_AI_COMMAND_CENTER_V94',
    'generated_at',now(),
    'summary',v_summary,
    'items',v_items,
    'pilots',v_pilots,
    'guardrails',jsonb_build_object(
      'recommendation_only',true,
      'read_only_aggregate',true,
      'source_of_truth_v86',true,
      'source_of_truth_v93',true,
      'auto_publish',false,
      'auto_program_edit',false,
      'no_synthetic_identity',true,
      'coach_review_required',true
    )
  );
end;
$function$;

revoke all on function public.get_coach_ai_command_center_v94(uuid) from public,anon;
grant execute on function public.get_coach_ai_command_center_v94(uuid) to authenticated,service_role;

comment on function public.get_coach_ai_command_center_v94(uuid) is
  'V94 unified read-only coach command center. Reconciles V86 training intelligence with V93 lifecycle state and returns deterministic priority, evidence and recommended action. Never mutates client or program state.';
