-- CV Coach V96 — Action Reconciliation & Outcome Intelligence
-- Deterministic post-action assessment over V95 decisions.
-- It measures evidence after coach actions without mutating client/training/program/billing state.
-- Important: outcome association is not a causal claim.

create table if not exists private.coach_action_outcome_events_v96 (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references private.coach_action_workspace_v95(id) on delete cascade,
  actor_id uuid not null references public.profiles(id) on delete restrict,
  client_id uuid not null references public.profiles(id) on delete restrict,
  action_code text not null,
  domain text,
  outcome_status text not null check (outcome_status in ('WAITING_EVIDENCE','RESOLVED','IMPROVED','MIXED','NO_CHANGE','WORSENED')),
  evidence_status text not null check (evidence_status in ('INSUFFICIENT','SUFFICIENT')),
  effectiveness_score smallint check (effectiveness_score is null or effectiveness_score between -100 and 100),
  confidence numeric(4,3) not null default 0 check (confidence between 0 and 1),
  evidence_fingerprint text not null,
  assessment jsonb not null default '{}'::jsonb,
  next_check_after timestamptz,
  assessed_at timestamptz not null default now(),
  unique(workspace_id,evidence_fingerprint)
);

create index if not exists idx_coach_action_outcome_v96_actor_assessed
  on private.coach_action_outcome_events_v96(actor_id,assessed_at desc);
create index if not exists idx_coach_action_outcome_v96_workspace_assessed
  on private.coach_action_outcome_events_v96(workspace_id,assessed_at desc);
create index if not exists idx_coach_action_outcome_v96_client_assessed
  on private.coach_action_outcome_events_v96(client_id,assessed_at desc);

revoke all on table private.coach_action_outcome_events_v96 from public, anon, authenticated;

create or replace function private.risk_rank_v96(p_risk text)
returns integer
language sql
immutable
set search_path=''
as $$
  select case upper(coalesce(p_risk,'')) when 'RED' then 3 when 'YELLOW' then 2 when 'GREEN' then 1 else 0 end;
$$;

create or replace function private.lifecycle_rank_v96(p_stage text)
returns integer
language sql
immutable
set search_path=''
as $$
  select case lower(coalesce(p_stage,''))
    when 'account_blocked' then 0
    when 'profile_incomplete' then 1
    when 'onboarding_in_progress' then 2
    when 'onboarding_review' then 3
    when 'coach_assignment' then 4
    when 'needs_review' then 4
    when 'program_needed' then 5
    when 'program_draft' then 6
    when 'operational' then 7
    else -1
  end;
$$;

revoke all on function private.risk_rank_v96(text) from public, anon, authenticated;
revoke all on function private.lifecycle_rank_v96(text) from public, anon, authenticated;

create or replace function private.compute_coach_action_outcome_v96(
  p_actor_id uuid,
  p_workspace_id uuid,
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_client_id uuid;
  v_action_code text;
  v_domain text;
  v_baseline jsonb;
  v_current jsonb;
  v_completed_at timestamptz;
  v_current_action text;
  v_elapsed_days integer;
  v_pre_sessions integer := 0;
  v_post_sessions integer := 0;
  v_latest_post timestamptz;
  v_pre_completion numeric;
  v_post_completion numeric;
  v_pre_effort numeric;
  v_post_effort numeric;
  v_pre_fatigue numeric;
  v_post_fatigue numeric;
  v_pre_pain numeric;
  v_post_pain numeric;
  v_post_max_pain numeric;
  v_post_pain_sessions integer := 0;
  v_base_risk text;
  v_current_risk text;
  v_base_risk_rank integer := 0;
  v_current_risk_rank integer := 0;
  v_base_critical integer := 0;
  v_current_critical integer := 0;
  v_base_warning integer := 0;
  v_current_warning integer := 0;
  v_base_recovery integer := 0;
  v_current_recovery integer := 0;
  v_base_stagnation integer := 0;
  v_current_stagnation integer := 0;
  v_base_pending integer := 0;
  v_current_pending integer := 0;
  v_base_deload boolean := false;
  v_current_deload boolean := false;
  v_base_requires boolean := false;
  v_current_requires boolean := false;
  v_base_burden integer := 0;
  v_current_burden integer := 0;
  v_base_stage text;
  v_current_stage text;
  v_base_stage_rank integer := -1;
  v_current_stage_rank integer := -1;
  v_base_subscription text;
  v_current_subscription text;
  v_base_active_program text;
  v_current_active_program text;
  v_base_draft_program text;
  v_current_draft_program text;
  v_positive boolean := false;
  v_negative boolean := false;
  v_evidence_status text := 'INSUFFICIENT';
  v_outcome text := 'WAITING_EVIDENCE';
  v_score smallint := null;
  v_confidence numeric := 0.20;
  v_explanation text := 'Aún no existe evidencia posterior suficiente para evaluar esta acción.';
  v_next_check timestamptz;
  v_fingerprint text;
  v_evidence jsonb;
  v_min_sessions integer := 0;
begin
  if p_as_of is null then p_as_of := now(); end if;

  select w.client_id,w.effective_action_code,w.recommendation_snapshot,w.completed_at,
         coalesce(nullif(w.recommendation_snapshot->>'primary_domain',''),upper(coalesce(w.execution_target,'')))
    into v_client_id,v_action_code,v_baseline,v_completed_at,v_domain
  from private.coach_action_workspace_v95 w
  where w.id=p_workspace_id
    and w.actor_id=p_actor_id
    and w.workflow_status='COMPLETED';

  if v_client_id is null or v_completed_at is null then
    raise exception 'Completed V95 action not found for actor';
  end if;

  select x into v_current
  from jsonb_array_elements(coalesce(public.get_coach_ai_command_center_v94(p_actor_id)->'items','[]'::jsonb)) x
  where x->>'client_id'=v_client_id::text
  limit 1;

  v_elapsed_days := greatest(0,floor(extract(epoch from (p_as_of-v_completed_at))/86400)::int);
  v_current_action := coalesce(v_current->>'recommended_action_code','monitor_client');

  with pre_rows as (
    select ws.completion_pct,ws.client_effort,ws.fatigue_score,ws.pain_score,ws.had_pain,ws.finished_at
    from public.workout_sessions ws
    where ws.client_id=v_client_id
      and ws.finished_at is not null
      and ws.finished_at<=v_completed_at
      and ws.status::text in ('completed','partial')
    order by ws.finished_at desc
    limit 3
  )
  select count(*)::int,round(avg(completion_pct),2),round(avg(client_effort),2),round(avg(fatigue_score),2),round(avg(pain_score),2)
    into v_pre_sessions,v_pre_completion,v_pre_effort,v_pre_fatigue,v_pre_pain
  from pre_rows;

  with post_rows as (
    select ws.completion_pct,ws.client_effort,ws.fatigue_score,ws.pain_score,ws.had_pain,ws.finished_at
    from public.workout_sessions ws
    where ws.client_id=v_client_id
      and ws.finished_at is not null
      and ws.finished_at>v_completed_at
      and ws.finished_at<=p_as_of
      and ws.status::text in ('completed','partial')
    order by ws.finished_at asc
    limit 6
  )
  select count(*)::int,max(finished_at),round(avg(completion_pct),2),round(avg(client_effort),2),round(avg(fatigue_score),2),round(avg(pain_score),2),max(pain_score),
         count(*) filter(where coalesce(had_pain,false) or coalesce(pain_score,0)>0)::int
    into v_post_sessions,v_latest_post,v_post_completion,v_post_effort,v_post_fatigue,v_post_pain,v_post_max_pain,v_post_pain_sessions
  from post_rows;

  v_base_risk := coalesce(v_baseline#>>'{training,risk_level}','');
  v_current_risk := coalesce(v_current#>>'{training,risk_level}','');
  v_base_risk_rank := private.risk_rank_v96(v_base_risk);
  v_current_risk_rank := private.risk_rank_v96(v_current_risk);
  v_base_critical := coalesce(nullif(v_baseline#>>'{training,critical_alerts}','')::int,0);
  v_current_critical := coalesce(nullif(v_current#>>'{training,critical_alerts}','')::int,0);
  v_base_warning := coalesce(nullif(v_baseline#>>'{training,warning_alerts}','')::int,0);
  v_current_warning := coalesce(nullif(v_current#>>'{training,warning_alerts}','')::int,0);
  v_base_recovery := coalesce(nullif(v_baseline#>>'{training,recovery_flags}','')::int,0);
  v_current_recovery := coalesce(nullif(v_current#>>'{training,recovery_flags}','')::int,0);
  v_base_stagnation := coalesce(nullif(v_baseline#>>'{training,stagnation_signals}','')::int,0);
  v_current_stagnation := coalesce(nullif(v_current#>>'{training,stagnation_signals}','')::int,0);
  v_base_pending := coalesce(nullif(v_baseline#>>'{training,pending_progressions}','')::int,0);
  v_current_pending := coalesce(nullif(v_current#>>'{training,pending_progressions}','')::int,0);
  v_base_deload := coalesce(nullif(v_baseline#>>'{training,deload_recommended}','')::boolean,false);
  v_current_deload := coalesce(nullif(v_current#>>'{training,deload_recommended}','')::boolean,false);
  v_base_requires := coalesce(nullif(v_baseline#>>'{training,requires_coach}','')::boolean,false);
  v_current_requires := coalesce(nullif(v_current#>>'{training,requires_coach}','')::boolean,false);
  v_base_burden := v_base_critical*4+v_base_warning*2+v_base_recovery*2+v_base_stagnation*2+(case when v_base_deload then 3 else 0 end)+(case when v_base_requires then 2 else 0 end);
  v_current_burden := v_current_critical*4+v_current_warning*2+v_current_recovery*2+v_current_stagnation*2+(case when v_current_deload then 3 else 0 end)+(case when v_current_requires then 2 else 0 end);

  v_base_stage := coalesce(v_baseline#>>'{lifecycle,stage}','');
  v_current_stage := coalesce(v_current#>>'{lifecycle,stage}','');
  v_base_stage_rank := private.lifecycle_rank_v96(v_base_stage);
  v_current_stage_rank := private.lifecycle_rank_v96(v_current_stage);
  v_base_subscription := nullif(v_baseline#>>'{lifecycle,subscription_status}','');
  v_current_subscription := nullif(v_current#>>'{lifecycle,subscription_status}','');
  v_base_active_program := nullif(v_baseline#>>'{lifecycle,active_program_id}','');
  v_current_active_program := nullif(v_current#>>'{lifecycle,active_program_id}','');
  v_base_draft_program := nullif(v_baseline#>>'{lifecycle,draft_program_id}','');
  v_current_draft_program := nullif(v_current#>>'{lifecycle,draft_program_id}','');

  if v_action_code in ('review_immediately','review_deload','review_recovery','review_stagnation','review_training_signals') then
    v_min_sessions := case when v_action_code='review_immediately' then 1 else 2 end;
    if v_current is null or v_post_sessions<v_min_sessions then
      v_next_check := p_as_of+interval '1 day';
    else
      v_evidence_status := 'SUFFICIENT';
      v_positive := (v_current_risk_rank<v_base_risk_rank)
                    or (v_current_burden<=greatest(0,v_base_burden-2))
                    or (v_current_action<>v_action_code and v_current_risk_rank<=v_base_risk_rank)
                    or (v_pre_fatigue is not null and v_post_fatigue is not null and v_post_fatigue<=v_pre_fatigue-1 and coalesce(v_post_completion,100)>=coalesce(v_pre_completion,100)-5);
      v_negative := (v_current_risk_rank>v_base_risk_rank)
                    or (v_current_burden>=v_base_burden+2)
                    or coalesce(v_post_max_pain,0)>=7
                    or (v_pre_completion is not null and v_post_completion is not null and v_post_completion<=v_pre_completion-15);
      if v_action_code='review_immediately' and v_current_critical=0 and v_current_risk_rank<3 and coalesce(v_post_max_pain,0)<7 then v_positive:=true; end if;
      if v_positive and not v_negative then
        if v_current_risk_rank<=1 and v_current_burden=0 then v_outcome:='RESOLVED';v_score:=100;v_explanation:='Las señales que originaron la revisión bajaron y la evidencia posterior no muestra un deterioro relevante.';
        else v_outcome:='IMPROVED';v_score:=70;v_explanation:='La evidencia posterior muestra una mejora respecto de las señales que originaron la acción.'; end if;
      elsif v_positive and v_negative then v_outcome:='MIXED';v_score:=25;v_explanation:='Hay señales favorables y desfavorables después de la acción; conviene seguir observando antes de concluir.';
      elsif v_negative then v_outcome:='WORSENED';v_score:=-70;v_explanation:='Las señales posteriores empeoraron o apareció una señal de seguridad relevante; requiere nueva revisión del coach.';
      else v_outcome:='NO_CHANGE';v_score:=0;v_explanation:='Con evidencia posterior suficiente, las señales relevantes no muestran un cambio material todavía.'; end if;
      v_confidence := least(0.90,0.55+(v_post_sessions*0.08));
    end if;

  elsif v_action_code='review_progressions' then
    v_min_sessions := 1;
    if v_current is null or v_post_sessions<1 then v_next_check:=p_as_of+interval '1 day';
    else
      v_evidence_status:='SUFFICIENT';v_confidence:=least(0.90,0.65+(v_post_sessions*0.07));
      if v_current_pending<v_base_pending then
        if v_current_pending=0 then v_outcome:='RESOLVED';v_score:=100;v_explanation:='La cola de progresiones pendiente se resolvió y ya existe entrenamiento posterior para observar el cambio.';
        else v_outcome:='IMPROVED';v_score:=70;v_explanation:='Disminuyeron las progresiones pendientes y existe entrenamiento posterior a la acción.';end if;
      elsif v_current_pending>v_base_pending then v_outcome:='WORSENED';v_score:=-60;v_explanation:='Aumentaron las progresiones pendientes después de la acción.';
      else v_outcome:='NO_CHANGE';v_score:=0;v_explanation:='La cola de progresiones no cambió de forma material después de la acción.';end if;
    end if;

  elsif v_action_code='contact_inactive_client' then
    if v_post_sessions>=1 then
      v_evidence_status:='SUFFICIENT';v_outcome:='RESOLVED';v_score:=100;v_confidence:=0.95;v_explanation:='El cliente registró una nueva sesión después de la acción de adherencia.';
    elsif v_elapsed_days>=14 then
      v_evidence_status:='SUFFICIENT';v_outcome:='WORSENED';v_score:=-50;v_confidence:=0.80;v_explanation:='No existe una nueva sesión registrada durante 14 días después de la acción de adherencia.';
    elsif v_elapsed_days>=7 then
      v_evidence_status:='SUFFICIENT';v_outcome:='NO_CHANGE';v_score:=0;v_confidence:=0.70;v_explanation:='Todavía no existe una nueva sesión registrada siete días después de la acción de adherencia.';v_next_check:=p_as_of+interval '3 days';
    else v_next_check:=least(v_completed_at+interval '7 days',p_as_of+interval '1 day'); end if;

  elsif v_action_code in ('review_account_status','review_client_profile','review_onboarding','review_coach_assignment') then
    if v_current is null then v_next_check:=p_as_of+interval '1 day';
    elsif v_current_stage_rank>v_base_stage_rank then
      v_evidence_status:='SUFFICIENT';v_confidence:=0.88;
      if v_current_stage='operational' then v_outcome:='RESOLVED';v_score:=100;v_explanation:='El cliente avanzó hasta estado operacional después de la acción.';
      else v_outcome:='IMPROVED';v_score:=70;v_explanation:='El cliente avanzó a una etapa posterior del ciclo de vida.';v_next_check:=p_as_of+interval '3 days';end if;
    elsif v_current_stage_rank>=0 and v_base_stage_rank>=0 and v_current_stage_rank<v_base_stage_rank then
      v_evidence_status:='SUFFICIENT';v_outcome:='WORSENED';v_score:=-70;v_confidence:=0.85;v_explanation:='El ciclo de vida retrocedió a una etapa anterior después de la acción.';
    elsif v_elapsed_days>=1 then
      v_evidence_status:='SUFFICIENT';v_outcome:='NO_CHANGE';v_score:=0;v_confidence:=0.65;v_explanation:='La etapa del ciclo de vida no cambió después de la acción.';v_next_check:=p_as_of+interval '2 days';
    else v_next_check:=p_as_of+interval '12 hours';end if;

  elsif v_action_code in ('create_initial_program','finish_program_draft') then
    if v_current is null then v_next_check:=p_as_of+interval '1 day';
    elsif v_current_active_program is not null and (v_base_active_program is null or v_current_active_program<>v_base_active_program) then
      v_evidence_status:='SUFFICIENT';v_outcome:='RESOLVED';v_score:=100;v_confidence:=0.95;v_explanation:='Existe un programa activo posterior a la acción de programación.';
    elsif v_current_draft_program is not null and v_current_draft_program is distinct from v_base_draft_program then
      v_evidence_status:='SUFFICIENT';v_outcome:='IMPROVED';v_score:=60;v_confidence:=0.80;v_explanation:='La programación avanzó a un nuevo borrador, pero todavía no existe publicación/activación que cierre el objetivo.';v_next_check:=p_as_of+interval '2 days';
    elsif v_elapsed_days>=1 then
      v_evidence_status:='SUFFICIENT';v_outcome:='NO_CHANGE';v_score:=0;v_confidence:=0.65;v_explanation:='No se observa todavía un cambio de estado del programa después de la acción.';v_next_check:=p_as_of+interval '2 days';
    else v_next_check:=p_as_of+interval '12 hours';end if;

  elsif v_action_code='review_subscription' then
    if v_current is null or v_current_subscription is null then v_next_check:=p_as_of+interval '1 day';
    elsif lower(v_current_subscription) not in ('past_due','cancelled','ended') and lower(coalesce(v_base_subscription,'')) in ('past_due','cancelled','ended') then
      v_evidence_status:='SUFFICIENT';v_outcome:='RESOLVED';v_score:=100;v_confidence:=0.90;v_explanation:='El estado de suscripción dejó de estar en una condición problemática después de la revisión.';
    elsif lower(v_current_subscription) in ('cancelled','ended') and lower(coalesce(v_base_subscription,''))='past_due' then
      v_evidence_status:='SUFFICIENT';v_outcome:='WORSENED';v_score:=-70;v_confidence:=0.88;v_explanation:='La suscripción pasó de vencida a cancelada/finalizada.';
    elsif v_elapsed_days>=1 then
      v_evidence_status:='SUFFICIENT';v_outcome:='NO_CHANGE';v_score:=0;v_confidence:=0.70;v_explanation:='El estado de suscripción no cambió después de la revisión.';v_next_check:=p_as_of+interval '2 days';
    else v_next_check:=p_as_of+interval '12 hours';end if;

  else
    if v_post_sessions>=2 then
      v_evidence_status:='SUFFICIENT';v_outcome:='NO_CHANGE';v_score:=0;v_confidence:=0.55;v_explanation:='Existe evidencia posterior, pero esta acción no tiene todavía una regla específica de eficacia; se conserva como resultado neutral.';
    else v_next_check:=p_as_of+interval '1 day';end if;
  end if;

  if v_evidence_status='SUFFICIENT' then
    if v_outcome in ('IMPROVED') and v_next_check is null then v_next_check:=p_as_of+interval '7 days'; end if;
    if v_outcome in ('MIXED','NO_CHANGE') and v_next_check is null then v_next_check:=p_as_of+interval '3 days'; end if;
  end if;

  v_evidence := jsonb_build_object(
    'pre_sessions',v_pre_sessions,
    'post_sessions',v_post_sessions,
    'minimum_post_sessions',v_min_sessions,
    'latest_post_session_at',v_latest_post,
    'elapsed_days',v_elapsed_days,
    'pre',jsonb_build_object('avg_completion_pct',v_pre_completion,'avg_effort',v_pre_effort,'avg_fatigue',v_pre_fatigue,'avg_pain',v_pre_pain),
    'post',jsonb_build_object('avg_completion_pct',v_post_completion,'avg_effort',v_post_effort,'avg_fatigue',v_post_fatigue,'avg_pain',v_post_pain,'max_pain',v_post_max_pain,'pain_sessions',v_post_pain_sessions),
    'risk',jsonb_build_object('before',nullif(v_base_risk,''),'after',nullif(v_current_risk,''),'before_rank',v_base_risk_rank,'after_rank',v_current_risk_rank),
    'signal_burden',jsonb_build_object('before',v_base_burden,'after',v_current_burden),
    'pending_progressions',jsonb_build_object('before',v_base_pending,'after',v_current_pending),
    'lifecycle',jsonb_build_object('before',nullif(v_base_stage,''),'after',nullif(v_current_stage,''),'before_rank',v_base_stage_rank,'after_rank',v_current_stage_rank),
    'subscription',jsonb_build_object('before',v_base_subscription,'after',v_current_subscription),
    'program',jsonb_build_object('active_before',v_base_active_program,'active_after',v_current_active_program,'draft_before',v_base_draft_program,'draft_after',v_current_draft_program),
    'current_action_code',v_current_action,
    'recommendation_cleared_or_changed',v_current_action<>v_action_code
  );

  v_fingerprint := md5(jsonb_build_object(
    'action_code',v_action_code,
    'post_sessions',v_post_sessions,
    'latest_post',v_latest_post,
    'risk',v_current_risk,
    'critical',v_current_critical,
    'warning',v_current_warning,
    'recovery',v_current_recovery,
    'stagnation',v_current_stagnation,
    'pending',v_current_pending,
    'stage',v_current_stage,
    'subscription',v_current_subscription,
    'active_program',v_current_active_program,
    'draft_program',v_current_draft_program,
    'current_action',v_current_action,
    'elapsed_day_bucket',case when v_action_code in ('contact_inactive_client','review_account_status','review_client_profile','review_onboarding','review_coach_assignment','create_initial_program','finish_program_draft','review_subscription') then v_elapsed_days else 0 end
  )::text);

  return jsonb_build_object(
    'version','ACTION_OUTCOME_INTELLIGENCE_V96',
    'workspace_id',p_workspace_id,
    'client_id',v_client_id,
    'action_code',v_action_code,
    'domain',v_domain,
    'outcome_status',v_outcome,
    'evidence_status',v_evidence_status,
    'effectiveness_score',v_score,
    'confidence',round(v_confidence,3),
    'explanation',v_explanation,
    'evidence_fingerprint',v_fingerprint,
    'evidence',v_evidence,
    'next_check_after',v_next_check,
    'assessed_at',p_as_of,
    'guardrails',jsonb_build_object(
      'correlation_not_causation',true,
      'single_training_session_is_not_enough',true,
      'training_minimum_sessions',2,
      'safety_review_minimum_sessions',1,
      'no_auto_publish',true,
      'no_auto_program_edit',true,
      'no_auto_message',true,
      'no_auto_billing_mutation',true,
      'no_client_state_mutation',true
    )
  );
end;
$function$;

revoke all on function private.compute_coach_action_outcome_v96(uuid,uuid,timestamptz) from public, anon, authenticated;

create or replace function public.reconcile_coach_action_outcome_v96(
  p_actor_id uuid,
  p_workspace_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_role public.app_role;
  v_assessment jsonb;
  v_event_id uuid;
  v_client_id uuid;
  v_existing uuid;
begin
  if auth.uid() is null or p_actor_id is null or auth.uid()<>p_actor_id then raise exception 'Authenticated actor mismatch'; end if;
  select p.role into v_role from public.profiles p where p.id=p_actor_id and p.status='active'::public.profile_status;
  if v_role is null or v_role not in ('admin'::public.app_role,'coach'::public.app_role) then raise exception 'Coach/admin required'; end if;

  select w.client_id into v_client_id
  from private.coach_action_workspace_v95 w
  where w.id=p_workspace_id and w.actor_id=p_actor_id and w.workflow_status='COMPLETED';
  if v_client_id is null then raise exception 'Completed V95 action not found for actor'; end if;
  if v_role='coach'::public.app_role and not exists(
    select 1 from public.coach_clients cc where cc.coach_id=p_actor_id and cc.client_id=v_client_id and cc.status='active'::public.coach_client_status
  ) then raise exception 'Client outside coach scope'; end if;

  v_assessment:=private.compute_coach_action_outcome_v96(p_actor_id,p_workspace_id,now());

  select e.id into v_existing
  from private.coach_action_outcome_events_v96 e
  where e.workspace_id=p_workspace_id and e.evidence_fingerprint=v_assessment->>'evidence_fingerprint';

  if v_existing is null then
    insert into private.coach_action_outcome_events_v96(
      workspace_id,actor_id,client_id,action_code,domain,outcome_status,evidence_status,
      effectiveness_score,confidence,evidence_fingerprint,assessment,next_check_after,assessed_at
    ) values(
      p_workspace_id,p_actor_id,v_client_id,v_assessment->>'action_code',v_assessment->>'domain',v_assessment->>'outcome_status',v_assessment->>'evidence_status',
      nullif(v_assessment->>'effectiveness_score','')::smallint,coalesce(nullif(v_assessment->>'confidence','')::numeric,0),v_assessment->>'evidence_fingerprint',v_assessment,
      nullif(v_assessment->>'next_check_after','')::timestamptz,now()
    ) returning id into v_event_id;
  else
    v_event_id:=v_existing;
  end if;

  if v_assessment->>'evidence_status'='SUFFICIENT' then
    update private.coach_action_workspace_v95
       set completion_verification='system_reconciled',updated_at=now()
     where id=p_workspace_id and actor_id=p_actor_id and completion_verification is distinct from 'system_reconciled';
  end if;

  return v_assessment||jsonb_build_object('event_id',v_event_id,'persisted',v_existing is null,'completion_verification',case when v_assessment->>'evidence_status'='SUFFICIENT' then 'system_reconciled' else 'coach_reported' end);
end;
$function$;

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
      and (l.workspace_id is null or l.next_check_after is null and false or l.next_check_after<=now())
    order by coalesce(l.next_check_after,w.completed_at) asc nulls first
    limit greatest(1,least(coalesce(p_limit,50),100))
  loop
    v_result:=public.reconcile_coach_action_outcome_v96(p_actor_id,v_row.id);
    v_processed:=v_processed+1;
  end loop;

  return jsonb_build_object('ok',true,'version','ACTION_OUTCOME_INTELLIGENCE_V96','processed',v_processed,'client_state_mutated',false,'training_data_mutated',false,'program_data_mutated',false,'billing_data_mutated',false);
end;
$function$;

create or replace function public.get_coach_outcome_intelligence_v96(p_actor_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_role public.app_role;
  v_items jsonb;
  v_learning jsonb;
  v_summary jsonb;
begin
  if auth.uid() is null or p_actor_id is null or auth.uid()<>p_actor_id then raise exception 'Authenticated actor mismatch'; end if;
  select p.role into v_role from public.profiles p where p.id=p_actor_id and p.status='active'::public.profile_status;
  if v_role is null or v_role not in ('admin'::public.app_role,'coach'::public.app_role) then raise exception 'Coach/admin required'; end if;

  with latest as (
    select distinct on (e.workspace_id) e.*
    from private.coach_action_outcome_events_v96 e
    where e.actor_id=p_actor_id
    order by e.workspace_id,e.assessed_at desc,e.id desc
  ), rows as (
    select w.*,l.id as outcome_event_id,l.outcome_status,l.evidence_status,l.effectiveness_score,l.confidence,l.assessment,l.next_check_after,l.assessed_at,
           coalesce(nullif(w.recommendation_snapshot->>'client_name',''),nullif(concat_ws(' ',p.first_name,p.last_name),''),'Cliente') as client_name
    from private.coach_action_workspace_v95 w
    join public.profiles p on p.id=w.client_id
    left join latest l on l.workspace_id=w.id
    where w.actor_id=p_actor_id and w.workflow_status='COMPLETED'
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'workspace_id',r.id,
    'client_id',r.client_id,
    'client_name',r.client_name,
    'action_code',r.effective_action_code,
    'action',r.effective_action,
    'domain',r.recommendation_snapshot->>'primary_domain',
    'completed_at',r.completed_at,
    'completion_verification',r.completion_verification,
    'outcome_event_id',r.outcome_event_id,
    'outcome_status',coalesce(r.outcome_status,'WAITING_EVIDENCE'),
    'evidence_status',coalesce(r.evidence_status,'INSUFFICIENT'),
    'effectiveness_score',r.effectiveness_score,
    'confidence',coalesce(r.confidence,0),
    'explanation',r.assessment->>'explanation',
    'evidence',coalesce(r.assessment->'evidence','{}'::jsonb),
    'assessed_at',r.assessed_at,
    'next_check_after',r.next_check_after,
    'due',case when r.outcome_event_id is null then true when r.next_check_after is not null and r.next_check_after<=now() then true else false end
  ) order by r.completed_at desc),'[]'::jsonb)
  into v_items from rows r;

  with latest as (
    select distinct on (e.workspace_id) e.*
    from private.coach_action_outcome_events_v96 e
    where e.actor_id=p_actor_id
    order by e.workspace_id,e.assessed_at desc,e.id desc
  ), sufficient as (
    select * from latest where evidence_status='SUFFICIENT' and outcome_status<>'WAITING_EVIDENCE'
  ), agg as (
    select action_code,count(*)::int as sample_size,
           count(*) filter(where outcome_status in ('RESOLVED','IMPROVED'))::int as positive,
           count(*) filter(where outcome_status='MIXED')::int as mixed,
           count(*) filter(where outcome_status='NO_CHANGE')::int as no_change,
           count(*) filter(where outcome_status='WORSENED')::int as worsened,
           round(avg(effectiveness_score)::numeric,1) as avg_score,
           round(avg(confidence)::numeric,3) as avg_confidence
    from sufficient group by action_code
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'action_code',a.action_code,
    'sample_size',a.sample_size,
    'positive',a.positive,
    'mixed',a.mixed,
    'no_change',a.no_change,
    'worsened',a.worsened,
    'positive_rate',round(a.positive::numeric/nullif(a.sample_size,0),3),
    'average_score',a.avg_score,
    'average_confidence',a.avg_confidence,
    'learning_ready',a.sample_size>=3,
    'association_pattern',case when a.sample_size<3 then 'INSUFFICIENT_SAMPLE' when a.positive::numeric/a.sample_size>=0.75 then 'FAVORABLE_ASSOCIATION' when a.positive::numeric/a.sample_size>=0.40 then 'VARIABLE_ASSOCIATION' else 'WEAK_ASSOCIATION' end
  ) order by a.sample_size desc,a.action_code),'[]'::jsonb)
  into v_learning from agg a;

  with x as (select value j from jsonb_array_elements(v_items))
  select jsonb_build_object(
    'completed_actions',count(*),
    'assessed',count(*) filter(where j->>'outcome_event_id' is not null),
    'waiting',count(*) filter(where j->>'outcome_status'='WAITING_EVIDENCE'),
    'positive',count(*) filter(where j->>'outcome_status' in ('RESOLVED','IMPROVED')),
    'mixed',count(*) filter(where j->>'outcome_status'='MIXED'),
    'no_change',count(*) filter(where j->>'outcome_status'='NO_CHANGE'),
    'worsened',count(*) filter(where j->>'outcome_status'='WORSENED'),
    'due',count(*) filter(where coalesce((j->>'due')::boolean,false)),
    'system_reconciled',count(*) filter(where j->>'completion_verification'='system_reconciled')
  ) into v_summary from x;

  return jsonb_build_object(
    'version','ACTION_OUTCOME_INTELLIGENCE_V96',
    'actor_id',p_actor_id,
    'summary',coalesce(v_summary,'{}'::jsonb),
    'items',v_items,
    'learning',v_learning,
    'guardrails',jsonb_build_object(
      'correlation_not_causation',true,
      'minimum_learning_sample',3,
      'single_training_session_is_not_enough',true,
      'training_minimum_sessions',2,
      'no_auto_publish',false,
      'auto_publish',false,
      'auto_program_edit',false,
      'auto_message',false,
      'auto_billing_mutation',false,
      'mutates_only_outcome_audit_metadata',true
    )
  );
end;
$function$;

grant execute on function public.reconcile_coach_action_outcome_v96(uuid,uuid) to authenticated,service_role;
grant execute on function public.reconcile_due_coach_action_outcomes_v96(uuid,integer) to authenticated,service_role;
grant execute on function public.get_coach_outcome_intelligence_v96(uuid) to authenticated,service_role;
revoke all on function public.reconcile_coach_action_outcome_v96(uuid,uuid) from public,anon;
revoke all on function public.reconcile_due_coach_action_outcomes_v96(uuid,integer) from public,anon;
revoke all on function public.get_coach_outcome_intelligence_v96(uuid) from public,anon;
