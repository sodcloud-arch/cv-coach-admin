-- F1.M1.S5 H3B1 — Billing / Lifecycle / System tenant hardening
-- Scope every remaining legacy consumer in this wave by organization_id.

create or replace function public.manage_client_subscription_backend(
  p_actor_id uuid,
  p_subscription_id uuid default null::uuid,
  p_client_id uuid default null::uuid,
  p_plan_id uuid default null::uuid,
  p_status public.subscription_status default 'pending'::public.subscription_status,
  p_started_at timestamptz default null::timestamptz,
  p_renews_at timestamptz default null::timestamptz,
  p_ended_at timestamptz default null::timestamptz,
  p_payment_source text default null::text,
  p_external_reference text default null::text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_request_role text:=coalesce(auth.role(),'');
  v_request_user uuid:=auth.uid();
  v_role text;
  v_id uuid;
  v_client_id uuid;
  v_plan_id uuid;
  v_organization uuid;
  v_started timestamptz:=p_started_at;
  v_ended timestamptz:=p_ended_at;
  v_payment_source text:=nullif(btrim(coalesce(p_payment_source,'')),'');
  v_external_reference text:=nullif(btrim(coalesce(p_external_reference,'')),'');
begin
  if p_actor_id is null then raise exception 'actor_id is required'; end if;
  if v_request_role<>'service_role' and (v_request_user is null or v_request_user<>p_actor_id) then
    raise exception 'Authenticated actor mismatch';
  end if;

  select role::text into v_role
  from public.profiles
  where id=p_actor_id and status::text='active';
  if v_role not in ('admin','coach') then
    raise exception 'actor is not authorized to manage subscriptions';
  end if;

  if p_subscription_id is null then
    v_client_id:=p_client_id;
    v_plan_id:=p_plan_id;
    if v_client_id is null or v_plan_id is null then
      raise exception 'client_id and plan_id are required';
    end if;
    v_organization:=private.resolve_legacy_professional_organization_v1(p_actor_id,v_client_id);
  else
    select organization_id,client_id,plan_id
    into v_organization,v_client_id,v_plan_id
    from public.client_subscriptions
    where id=p_subscription_id;
    if v_client_id is null then raise exception 'subscription not found'; end if;
    if p_client_id is not null and p_client_id<>v_client_id then raise exception 'client_id cannot be changed'; end if;
    if p_plan_id is not null then v_plan_id:=p_plan_id; end if;
  end if;

  if not (
    v_request_role='service_role'
    or private.is_org_admin(v_organization)
    or private.actor_can_manage_client_in_org_v1(p_actor_id,v_organization,v_client_id)
  ) then
    raise exception 'actor is not authorized for this client in organization';
  end if;

  if not exists(
    select 1 from public.clients c
    where c.organization_id=v_organization
      and c.user_id=v_client_id
      and c.status<>'archived'::public.client_status
  ) then raise exception 'active client not found in organization'; end if;

  if not exists(select 1 from public.plans p where p.id=v_plan_id and p.active=true) then
    raise exception 'active plan not found';
  end if;

  if p_status in ('trialing'::public.subscription_status,'active'::public.subscription_status) and v_started is null then v_started:=now(); end if;
  if p_status in ('cancelled'::public.subscription_status,'ended'::public.subscription_status) and v_ended is null then v_ended:=now(); end if;
  if p_status in ('pending'::public.subscription_status,'trialing'::public.subscription_status,'active'::public.subscription_status,'past_due'::public.subscription_status) then v_ended:=null; end if;
  if p_renews_at is not null and v_started is not null and p_renews_at<v_started then raise exception 'renews_at cannot be before started_at'; end if;
  if v_ended is not null and v_started is not null and v_ended<v_started then raise exception 'ended_at cannot be before started_at'; end if;
  if v_payment_source is not null and length(v_payment_source)>80 then raise exception 'payment_source must be <= 80 characters'; end if;
  if v_external_reference is not null and length(v_external_reference)>200 then raise exception 'external_reference must be <= 200 characters'; end if;

  if p_subscription_id is null then
    insert into public.client_subscriptions(
      organization_id,client_id,plan_id,status,started_at,renews_at,ended_at,payment_source,external_reference
    ) values(
      v_organization,v_client_id,v_plan_id,p_status,v_started,p_renews_at,v_ended,v_payment_source,v_external_reference
    ) returning id into v_id;
  else
    update public.client_subscriptions
    set plan_id=v_plan_id,status=p_status,started_at=v_started,renews_at=p_renews_at,
        ended_at=v_ended,payment_source=v_payment_source,external_reference=v_external_reference,
        updated_at=now()
    where id=p_subscription_id and organization_id=v_organization
    returning id into v_id;
  end if;

  return (
    select jsonb_build_object(
      'organization_id',s.organization_id,
      'subscription_id',s.id,'client_id',s.client_id,'plan_id',s.plan_id,'status',s.status,
      'started_at',s.started_at,'renews_at',s.renews_at,'ended_at',s.ended_at,
      'payment_source',s.payment_source,'external_reference',s.external_reference
    )
    from public.client_subscriptions s
    where s.id=v_id and s.organization_id=v_organization
  );
exception when unique_violation then
  raise exception 'client already has an open subscription in organization';
end;
$function$;

create or replace function public.manage_subscription_billing_backend(
  p_actor_id uuid,
  p_billing_id uuid default null::uuid,
  p_subscription_id uuid default null::uuid,
  p_due_at date default null::date,
  p_status public.billing_status default 'pending'::public.billing_status,
  p_amount_clp integer default null::integer,
  p_paid_at timestamptz default null::timestamptz,
  p_payment_method text default null::text,
  p_external_reference text default null::text,
  p_notes text default null::text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_request_role text:=coalesce(auth.role(),'');
  v_request_user uuid:=auth.uid();
  v_role text;
  v_id uuid;
  v_organization uuid;
  v_subscription public.client_subscriptions%rowtype;
  v_plan public.plans%rowtype;
  v_old public.subscription_billing_records%rowtype;
  v_amount integer;
  v_due_at date;
  v_paid_at timestamptz:=p_paid_at;
  v_method text:=nullif(btrim(coalesce(p_payment_method,'')),'');
  v_reference text:=nullif(btrim(coalesce(p_external_reference,'')),'');
  v_notes text:=nullif(btrim(coalesce(p_notes,'')),'');
  v_became_paid boolean:=false;
begin
  if p_actor_id is null then raise exception 'actor_id is required'; end if;
  if v_request_role<>'service_role' and (v_request_user is null or v_request_user<>p_actor_id) then
    raise exception 'Authenticated actor mismatch';
  end if;

  select role::text into v_role from public.profiles where id=p_actor_id and status::text='active';
  if v_role not in ('admin','coach') then raise exception 'actor is not authorized to manage billing'; end if;

  if p_billing_id is null then
    if p_subscription_id is null or p_due_at is null then raise exception 'subscription_id and due_at are required'; end if;
    select * into v_subscription from public.client_subscriptions where id=p_subscription_id;
    v_due_at:=p_due_at;
  else
    select * into v_old from public.subscription_billing_records where id=p_billing_id;
    if v_old.id is null then raise exception 'billing record not found'; end if;
    select * into v_subscription
    from public.client_subscriptions
    where id=v_old.subscription_id and organization_id=v_old.organization_id;
    v_due_at:=coalesce(p_due_at,v_old.due_at);
  end if;

  if v_subscription.id is null then raise exception 'subscription not found'; end if;
  v_organization:=v_subscription.organization_id;

  if not (
    v_request_role='service_role'
    or private.is_org_admin(v_organization)
    or private.actor_can_manage_client_in_org_v1(p_actor_id,v_organization,v_subscription.client_id)
  ) then raise exception 'actor is not authorized for this billing record in organization'; end if;

  select * into v_plan from public.plans where id=v_subscription.plan_id;
  if v_plan.id is null then raise exception 'plan not found'; end if;

  v_amount:=coalesce(p_amount_clp,case when v_old.id is not null then v_old.amount_clp else null end,v_plan.price_clp);
  if v_amount is null or v_amount<0 then raise exception 'amount_clp must be >= 0'; end if;
  if v_method is not null and length(v_method)>80 then raise exception 'payment_method must be <= 80 characters'; end if;
  if v_reference is not null and length(v_reference)>200 then raise exception 'external_reference must be <= 200 characters'; end if;
  if v_notes is not null and length(v_notes)>1000 then raise exception 'notes must be <= 1000 characters'; end if;

  if p_status='paid'::public.billing_status and v_paid_at is null then v_paid_at:=now(); end if;
  if p_status<>'paid'::public.billing_status then v_paid_at:=null; end if;

  if p_billing_id is null then
    insert into public.subscription_billing_records(
      organization_id,subscription_id,client_id,plan_id,plan_name_snapshot,amount_clp,due_at,status,
      paid_at,payment_method,external_reference,notes,created_by
    ) values(
      v_organization,v_subscription.id,v_subscription.client_id,v_plan.id,v_plan.name,v_amount,v_due_at,p_status,
      v_paid_at,v_method,v_reference,v_notes,p_actor_id
    ) returning id into v_id;
    v_became_paid:=p_status='paid'::public.billing_status;
  else
    update public.subscription_billing_records
    set status=p_status,amount_clp=v_amount,due_at=v_due_at,paid_at=v_paid_at,
        payment_method=v_method,external_reference=v_reference,notes=v_notes,updated_at=now()
    where id=p_billing_id and organization_id=v_organization
    returning id into v_id;
    v_became_paid:=v_old.status<>'paid'::public.billing_status and p_status='paid'::public.billing_status;
  end if;

  if v_became_paid then
    update public.coach_alerts
    set status='resolved'::public.alert_status,resolved_at=coalesce(resolved_at,now()),updated_at=now()
    where organization_id=v_organization
      and status='open'::public.alert_status
      and alert_type='billing_due'
      and source_data->>'billing_id'=v_id::text;

    if lower(btrim(coalesce(v_plan.billing_period,''))) in ('mensual','monthly','month')
       and v_subscription.renews_at is not null
       and v_due_at=(v_subscription.renews_at at time zone 'America/Santiago')::date then
      update public.client_subscriptions
      set status=case when status='past_due'::public.subscription_status then 'active'::public.subscription_status else status end,
          renews_at=renews_at+interval '1 month',updated_at=now()
      where id=v_subscription.id and organization_id=v_organization;
    end if;
  end if;

  return (
    select to_jsonb(b)
    from public.subscription_billing_records b
    where b.id=v_id and b.organization_id=v_organization
  );
exception when unique_violation then
  raise exception 'billing record already exists for this subscription and due date';
end;
$function$;

create or replace function private.ensure_subscription_billing_records()
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare v_count integer:=0;
begin
  insert into public.subscription_billing_records(
    organization_id,subscription_id,client_id,plan_id,plan_name_snapshot,amount_clp,due_at,status,created_by
  )
  select s.organization_id,s.id,s.client_id,p.id,p.name,p.price_clp,
         (s.renews_at at time zone 'America/Santiago')::date,
         'pending'::public.billing_status,null
  from public.client_subscriptions s
  join public.plans p on p.id=s.plan_id
  where s.status in ('pending'::public.subscription_status,'trialing'::public.subscription_status,'active'::public.subscription_status,'past_due'::public.subscription_status)
    and s.renews_at is not null
    and (s.renews_at at time zone 'America/Santiago')::date<=current_date+31
    and not exists(
      select 1 from public.subscription_billing_records b
      where b.organization_id=s.organization_id
        and b.subscription_id=s.id
        and b.due_at=(s.renews_at at time zone 'America/Santiago')::date
    )
  on conflict(subscription_id,due_at) do nothing;
  get diagnostics v_count=row_count;
  return v_count;
end;
$function$;

create or replace function private.refresh_billing_alerts()
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare v_count integer:=0;
begin
  perform private.ensure_subscription_billing_records();

  update public.subscription_billing_records
  set status='overdue'::public.billing_status,updated_at=now()
  where status='pending'::public.billing_status and due_at<current_date;

  update public.client_subscriptions s
  set status='past_due'::public.subscription_status,updated_at=now()
  where status in ('pending'::public.subscription_status,'trialing'::public.subscription_status,'active'::public.subscription_status)
    and exists(
      select 1 from public.subscription_billing_records b
      where b.organization_id=s.organization_id
        and b.subscription_id=s.id
        and b.status='overdue'::public.billing_status
    );

  insert into public.coach_alerts(
    organization_id,coach_id,client_id,alert_type,severity,title,message,source_data,status
  )
  select
    b.organization_id,
    cp.user_id,
    b.client_id,
    'billing_due',
    case when b.status='overdue'::public.billing_status then 'critical'::public.alert_severity else 'warning'::public.alert_severity end,
    case when b.status='overdue'::public.billing_status then 'Cobro vencido' else 'Cobro próximo a vencer' end,
    b.plan_name_snapshot||' · $'||to_char(b.amount_clp,'FM999G999G999')||' · vence '||to_char(b.due_at,'DD-MM-YYYY'),
    jsonb_build_object(
      'organization_id',b.organization_id,
      'billing_id',b.id,'subscription_id',b.subscription_id,'due_at',b.due_at,'amount_clp',b.amount_clp
    ),
    'open'::public.alert_status
  from public.subscription_billing_records b
  join public.clients cl
    on cl.organization_id=b.organization_id
   and cl.user_id=b.client_id
   and cl.status<>'archived'::public.client_status
  join public.client_coach_assignments a
    on a.organization_id=cl.organization_id
   and a.client_id=cl.id
   and a.status='active'::public.client_coach_assignment_status
  join public.coach_profiles cp
    on cp.organization_id=a.organization_id
   and cp.id=a.coach_id
   and cp.status='active'::public.coach_profile_status
  where b.status in ('pending'::public.billing_status,'overdue'::public.billing_status)
    and b.due_at<=current_date+7
    and not exists(
      select 1 from public.coach_alerts ca
      where ca.organization_id=b.organization_id
        and ca.coach_id=cp.user_id
        and ca.client_id=b.client_id
        and ca.status='open'::public.alert_status
        and ca.alert_type='billing_due'
        and ca.source_data->>'billing_id'=b.id::text
    );

  get diagnostics v_count=row_count;
  return v_count;
end;
$function$;

create or replace function private.refresh_subscription_renewal_alerts()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_created int:=0;
  v_resolved int:=0;
  r record;
  v_type text;
  v_severity public.alert_severity;
  v_title text;
  v_message text;
begin
  update public.coach_alerts a
  set status='resolved'::public.alert_status,
      resolved_at=coalesce(a.resolved_at,now()),
      updated_at=now()
  where a.alert_type in ('subscription_renewal_due','subscription_overdue')
    and a.status in ('open'::public.alert_status,'acknowledged'::public.alert_status)
    and exists(
      select 1 from public.client_subscriptions s
      where s.organization_id=a.organization_id
        and s.id=(a.source_data->>'subscription_id')::uuid
        and (
          s.status in ('cancelled'::public.subscription_status,'ended'::public.subscription_status)
          or s.renews_at is null
          or coalesce(a.source_data->>'renews_at','')<>coalesce(s.renews_at::text,'')
        )
    );
  get diagnostics v_resolved=row_count;

  for r in
    select s.organization_id,s.id as subscription_id,s.client_id,s.plan_id,s.status,s.renews_at,
           p.name as plan_name,cp.user_id as coach_id
    from public.client_subscriptions s
    join public.plans p on p.id=s.plan_id
    join public.clients cl
      on cl.organization_id=s.organization_id
     and cl.user_id=s.client_id
     and cl.status<>'archived'::public.client_status
    join public.client_coach_assignments a
      on a.organization_id=cl.organization_id
     and a.client_id=cl.id
     and a.status='active'::public.client_coach_assignment_status
    join public.coach_profiles cp
      on cp.organization_id=a.organization_id
     and cp.id=a.coach_id
     and cp.status='active'::public.coach_profile_status
    where s.status in ('trialing'::public.subscription_status,'active'::public.subscription_status,'past_due'::public.subscription_status)
      and s.renews_at is not null
      and s.renews_at<=now()+interval '7 days'
  loop
    if r.renews_at<=now() then
      v_type:='subscription_overdue';
      v_severity:='critical'::public.alert_severity;
      v_title:='Renovación vencida';
      v_message:=format('La suscripción %s venció el %s. Revisar pago/renovación.',r.plan_name,to_char(r.renews_at at time zone 'America/Santiago','DD-MM-YYYY'));
    else
      v_type:='subscription_renewal_due';
      v_severity:='warning'::public.alert_severity;
      v_title:='Renovación próxima';
      v_message:=format('La suscripción %s renueva el %s.',r.plan_name,to_char(r.renews_at at time zone 'America/Santiago','DD-MM-YYYY'));
    end if;

    if not exists(
      select 1 from public.coach_alerts a
      where a.organization_id=r.organization_id
        and a.coach_id=r.coach_id
        and a.client_id=r.client_id
        and a.alert_type=v_type
        and a.status in ('open'::public.alert_status,'acknowledged'::public.alert_status)
        and a.source_data->>'subscription_id'=r.subscription_id::text
        and a.source_data->>'renews_at'=r.renews_at::text
    ) then
      insert into public.coach_alerts(
        organization_id,coach_id,client_id,alert_type,severity,title,message,source_data,status
      ) values(
        r.organization_id,r.coach_id,r.client_id,v_type,v_severity,v_title,v_message,
        jsonb_build_object(
          'organization_id',r.organization_id,
          'subscription_id',r.subscription_id,'plan_id',r.plan_id,'renews_at',r.renews_at
        ),
        'open'::public.alert_status
      );
      v_created:=v_created+1;
    end if;
  end loop;

  return jsonb_build_object('created',v_created,'resolved',v_resolved);
end;
$function$;

create or replace function private.sync_onboarding_review_alert()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  r record;
  v_active boolean;
begin
  if tg_op='UPDATE'
     and new.onboarding_status is not distinct from old.onboarding_status then
    return new;
  end if;

  v_active:=new.onboarding_status='completed'::public.onboarding_status;

  for r in
    select cp.user_id as coach_id
    from public.clients cl
    join public.client_coach_assignments a
      on a.organization_id=cl.organization_id
     and a.client_id=cl.id
     and a.status='active'::public.client_coach_assignment_status
    join public.coach_profiles cp
      on cp.organization_id=a.organization_id
     and cp.id=a.coach_id
     and cp.status='active'::public.coach_profile_status
    join public.profiles p
      on p.id=cp.user_id
     and p.status::text='active'
     and p.role in ('coach'::public.app_role,'admin'::public.app_role)
    where cl.organization_id=new.organization_id
      and cl.user_id=new.client_id
      and cl.status<>'archived'::public.client_status
  loop
    perform private.set_coach_alert_in_org(
      new.organization_id,
      r.coach_id,
      new.client_id,
      'onboarding_review',
      v_active,
      'warning'::public.alert_severity,
      case when v_active then 'Onboarding listo para revisión' else 'Onboarding revisado' end,
      case when v_active then 'El cliente completó su evaluación inicial. Revisa su ficha antes de publicar el programa.' else null end,
      jsonb_build_object(
        'organization_id',new.organization_id,
        'onboarding_status',new.onboarding_status::text,
        'submitted_at',case when v_active then now() else null end
      )
    );
  end loop;

  return new;
end;
$function$;

create or replace function private.check_training_e2e_health(p_grace_minutes integer default 10)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  r record;
  v_issue record;
  v_checked integer:=0;
  v_open integer:=0;
  v_resolved integer:=0;
begin
  p_grace_minutes:=greatest(5,least(coalesce(p_grace_minutes,10),120));

  for r in
    select distinct
      a.organization_id,
      cp.user_id as coach_id,
      cl.user_id as client_id
    from public.client_coach_assignments a
    join public.clients cl
      on cl.organization_id=a.organization_id
     and cl.id=a.client_id
     and cl.status<>'archived'::public.client_status
     and cl.user_id is not null
    join public.coach_profiles cp
      on cp.organization_id=a.organization_id
     and cp.id=a.coach_id
     and cp.status='active'::public.coach_profile_status
    join public.profiles p
      on p.id=cl.user_id
     and p.status::text='active'
    where a.status='active'::public.client_coach_assignment_status
  loop
    v_checked:=v_checked+1;
    v_issue:=null;

    select q.* into v_issue
    from (
      select ws.id as session_id,ws.finished_at,ws.status::text as workout_status,
             e.id as event_id,e.status as event_status,e.attempts,e.last_error,
             expected.expected_event,
             coalesce(x.exercise_count,0) as exercise_count,
             coalesce(d.decision_count,0) as decision_count,
             case
               when e.id is null then 'TERMINAL_EVENT_MISSING'
               when e.status='dead_letter' then 'WORKOUT_PIPELINE_DEAD_LETTER'
               when e.status<>'processed' then 'WORKOUT_PIPELINE_NOT_PROCESSED'
               when ra.source_session_id is null then 'WORKOUT_RISK_ASSESSMENT_MISSING'
               when coalesce(d.decision_count,0)<coalesce(x.exercise_count,0) then 'TRAINING_DECISION_INCOMPLETE'
               else null
             end as issue_code
      from public.workout_sessions ws
      cross join lateral (
        select case when ws.status::text='abandoned' then 'WORKOUT_ABANDONED' else 'WORKOUT_COMPLETED' end as expected_event
      ) expected
      left join lateral (
        select eo.*
        from public.event_outbox eo
        where eo.organization_id=ws.organization_id
          and eo.aggregate_id=ws.id
          and eo.client_id=ws.client_id
          and eo.event_key=expected.expected_event
        order by eo.created_at desc
        limit 1
      ) e on true
      left join private.workout_risk_assessments ra on ra.source_session_id=ws.id
      left join lateral (
        select count(distinct se.exercise_id)::integer as exercise_count
        from public.session_exercises se
        where se.workout_session_id=ws.id
      ) x on true
      left join lateral (
        select count(distinct ad.exercise_id)::integer as decision_count
        from private.ai_decisions ad
        where ad.source_session_id=ws.id
          and ad.client_id=ws.client_id
          and ad.decision_type='training_progression'
      ) d on true
      where ws.organization_id=r.organization_id
        and ws.client_id=r.client_id
        and ws.status in (
          'completed'::public.workout_session_status,
          'partial'::public.workout_session_status,
          'abandoned'::public.workout_session_status
        )
        and ws.finished_at is not null
        and ws.finished_at<=now()-(p_grace_minutes||' minutes')::interval
        and ws.finished_at>=now()-interval '30 days'
        and exists(select 1 from public.session_exercises se where se.workout_session_id=ws.id)
        and not private.is_demo_workout(ws.id)
        and coalesce(e.payload->>'test','false')<>'true'
    ) q
    where q.issue_code is not null
    order by q.finished_at desc
    limit 1;

    if v_issue.session_id is not null then
      perform private.set_coach_alert_in_org(
        r.organization_id,r.coach_id,r.client_id,'system_training_pipeline',true,
        case when v_issue.issue_code='WORKOUT_PIPELINE_DEAD_LETTER'
          then 'critical'::public.alert_severity else 'warning'::public.alert_severity end,
        'Revisar procesamiento post-entrenamiento',
        case v_issue.issue_code
          when 'TERMINAL_EVENT_MISSING' then 'La sesión terminó, pero no se creó el evento terminal esperado.'
          when 'WORKOUT_PIPELINE_DEAD_LETTER' then 'El evento post-entrenamiento llegó a dead letter y requiere recuperación.'
          when 'WORKOUT_PIPELINE_NOT_PROCESSED' then 'El evento post-entrenamiento superó la ventana esperada y todavía no fue procesado.'
          when 'WORKOUT_RISK_ASSESSMENT_MISSING' then 'El evento fue procesado, pero falta la evaluación histórica de riesgo asociada a esta sesión.'
          when 'TRAINING_DECISION_INCOMPLETE' then 'El evento fue procesado, pero no todos los ejercicios tienen una decisión de progresión/revisión registrada.'
          else 'El pipeline post-entrenamiento requiere revisión.'
        end,
        jsonb_build_object(
          'organization_id',r.organization_id,
          'issue_code',v_issue.issue_code,'session_id',v_issue.session_id,
          'workout_status',v_issue.workout_status,'expected_event',v_issue.expected_event,
          'event_id',v_issue.event_id,'event_status',v_issue.event_status,
          'attempts',v_issue.attempts,'last_error',v_issue.last_error,
          'exercise_count',v_issue.exercise_count,'decision_count',v_issue.decision_count,
          'finished_at',v_issue.finished_at,'grace_minutes',p_grace_minutes
        )
      );
      v_open:=v_open+1;
    else
      perform private.set_coach_alert_in_org(
        r.organization_id,r.coach_id,r.client_id,'system_training_pipeline',false,
        'info'::public.alert_severity,'Pipeline post-entrenamiento saludable',null,
        jsonb_build_object('organization_id',r.organization_id)
      );
      v_resolved:=v_resolved+1;
    end if;
  end loop;

  return jsonb_build_object(
    'checked_clients',v_checked,
    'open_pipeline_alerts',v_open,
    'healthy_or_resolved',v_resolved,
    'grace_minutes',p_grace_minutes
  );
end;
$function$;

create or replace function public.get_client_lifecycle_center_v93(p_actor_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_role text;
  v_items jsonb;
begin
  if auth.uid() is null or p_actor_id is null or auth.uid()<>p_actor_id then
    raise exception 'Authenticated actor mismatch';
  end if;

  select p.role::text into v_role
  from public.profiles p
  where p.id=p_actor_id and p.status::text='active';

  if v_role not in ('admin','coach') then raise exception 'Coach/admin required'; end if;

  with visible_clients as (
    select c.organization_id,c.id as client_entity_id,c.user_id as client_id,p.*
    from public.clients c
    join public.profiles p
      on p.id=c.user_id
     and p.role::text='client'
    where c.status<>'archived'::public.client_status
      and c.user_id is not null
      and (
        private.is_org_admin(c.organization_id)
        or private.actor_can_manage_client_in_org_v1(p_actor_id,c.organization_id,c.user_id)
      )
  ), lifecycle as (
    select
      vc.organization_id,
      vc.client_entity_id,
      vc.client_id,
      nullif(trim(concat_ws(' ',vc.first_name,vc.last_name)),'') as client_name,
      vc.first_name,vc.last_name,vc.phone,vc.status::text as profile_status,
      cp.primary_goal,cp.onboarding_status::text as onboarding_status,
      coalesce(ob.response_count,0) as onboarding_response_count,
      inv.email,inv.status as invite_status,inv.created_at as invite_created_at,
      inv.last_generated_at,inv.accepted_at,inv.revoked_at,
      rel.status as coach_relationship_status,rel.assigned_at,
      active_program.id as active_program_id,active_program.name as active_program_name,active_program.version as active_program_version,
      draft_program.id as draft_program_id,draft_program.name as draft_program_name,draft_program.version as draft_program_version,
      sub.id as subscription_id,sub.status as subscription_status,sub.renews_at as subscription_renews_at,sub.plan_name,
      case
        when cp.onboarding_status::text in ('in_progress','completed','approved') or coalesce(ob.response_count,0)>0 then 'activity_detected'
        when inv.status='generated' and inv.revoked_at is null then 'setup_link_generated'
        when inv.revoked_at is not null or inv.status='revoked' then 'access_revoked'
        else 'no_access_link'
      end as access_state,
      case
        when vc.status::text<>'active' then 'account_blocked'
        when cp.client_id is null then 'profile_incomplete'
        when cp.onboarding_status::text in ('pending','in_progress') then 'onboarding_in_progress'
        when cp.onboarding_status::text='completed' then 'onboarding_review'
        when cp.onboarding_status::text='approved' and coalesce(rel.status,'')<>'active' then 'coach_assignment'
        when cp.onboarding_status::text='approved' and draft_program.id is not null then 'program_draft'
        when cp.onboarding_status::text='approved' and active_program.id is null then 'program_needed'
        when cp.onboarding_status::text='approved' and active_program.id is not null then 'operational'
        else 'needs_review'
      end as lifecycle_stage,
      case
        when vc.status::text<>'active' then 'review_account_status'
        when cp.client_id is null then 'review_client_profile'
        when cp.onboarding_status::text='pending' and (inv.email is null or inv.revoked_at is not null) then 'generate_access_link'
        when cp.onboarding_status::text='pending' then 'wait_for_onboarding'
        when cp.onboarding_status::text='in_progress' then 'wait_for_onboarding_completion'
        when cp.onboarding_status::text='completed' then 'review_onboarding'
        when cp.onboarding_status::text='approved' and coalesce(rel.status,'')<>'active' then 'review_coach_assignment'
        when cp.onboarding_status::text='approved' and draft_program.id is not null then 'finish_program_draft'
        when cp.onboarding_status::text='approved' and active_program.id is null then 'create_initial_program'
        when cp.onboarding_status::text='approved' and active_program.id is not null then 'monitor_client'
        else 'review_client'
      end as next_action
    from visible_clients vc
    left join public.client_profiles cp
      on cp.organization_id=vc.organization_id and cp.client_id=vc.client_id
    left join lateral (
      select count(*)::int as response_count
      from public.onboarding_responses x
      where x.organization_id=vc.organization_id and x.client_id=vc.client_id
    ) ob on true
    left join lateral (
      select i.email,i.status,i.created_at,i.last_generated_at,i.accepted_at,i.revoked_at
      from public.client_invites i
      where i.organization_id=vc.organization_id
        and i.client_id=vc.client_id
        and (
          v_role='admin'
          or i.coach_id=p_actor_id
          or private.is_org_admin(vc.organization_id)
        )
      order by coalesce(i.last_generated_at,i.created_at) desc nulls last,i.created_at desc
      limit 1
    ) inv on true
    left join lateral (
      select a.status::text as status,a.assigned_at
      from public.client_coach_assignments a
      join public.coach_profiles cpx
        on cpx.organization_id=a.organization_id
       and cpx.id=a.coach_id
      where a.organization_id=vc.organization_id
        and a.client_id=vc.client_entity_id
        and (
          v_role='admin'
          or cpx.user_id=p_actor_id
          or private.is_org_admin(vc.organization_id)
        )
      order by (a.status='active'::public.client_coach_assignment_status) desc,a.assigned_at desc nulls last
      limit 1
    ) rel on true
    left join lateral (
      select pr.id,pr.name,pr.version
      from public.programs pr
      where pr.organization_id=vc.organization_id
        and pr.client_id=vc.client_id
        and pr.status::text='active'
      order by pr.version desc nulls last,pr.updated_at desc
      limit 1
    ) active_program on true
    left join lateral (
      select pr.id,pr.name,pr.version
      from public.programs pr
      where pr.organization_id=vc.organization_id
        and pr.client_id=vc.client_id
        and pr.status::text='draft'
      order by pr.version desc nulls last,pr.updated_at desc
      limit 1
    ) draft_program on true
    left join lateral (
      select cs.id,cs.status::text as status,cs.renews_at,pl.name as plan_name
      from public.client_subscriptions cs
      left join public.plans pl on pl.id=cs.plan_id
      where cs.organization_id=vc.organization_id
        and cs.client_id=vc.client_id
      order by (cs.status::text in ('active','trialing','past_due','pending')) desc,cs.updated_at desc
      limit 1
    ) sub on true
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'organization_id',organization_id,
      'client_id',client_id,
      'client_name',coalesce(client_name,'Cliente sin nombre'),
      'first_name',first_name,'last_name',last_name,'phone',phone,'email',email,
      'profile_status',profile_status,'primary_goal',primary_goal,
      'access_state',access_state,'invite_status',invite_status,
      'invite_created_at',invite_created_at,'last_generated_at',last_generated_at,
      'accepted_at',accepted_at,'revoked_at',revoked_at,
      'onboarding_status',coalesce(onboarding_status,'pending'),
      'onboarding_response_count',onboarding_response_count,
      'coach_relationship_status',coach_relationship_status,'assigned_at',assigned_at,
      'active_program_id',active_program_id,'active_program_name',active_program_name,'active_program_version',active_program_version,
      'draft_program_id',draft_program_id,'draft_program_name',draft_program_name,'draft_program_version',draft_program_version,
      'subscription_id',subscription_id,'subscription_status',subscription_status,'subscription_renews_at',subscription_renews_at,'plan_name',plan_name,
      'lifecycle_stage',lifecycle_stage,'next_action',next_action,
      'guardrails',jsonb_build_object(
        'tenant_scoped',true,'read_only_aggregate',true,
        'reuse_existing_provision_client',true,'reuse_existing_onboarding_review',true,
        'reuse_existing_programming',true,'no_auto_publish',true
      )
    )
    order by
      case lifecycle_stage
        when 'account_blocked' then 1 when 'profile_incomplete' then 2 when 'onboarding_review' then 3
        when 'coach_assignment' then 4 when 'program_draft' then 5 when 'program_needed' then 6
        when 'onboarding_in_progress' then 7 when 'needs_review' then 8 else 9
      end,
      organization_id,
      lower(coalesce(client_name,''))
  ),'[]'::jsonb)
  into v_items
  from lifecycle;

  return jsonb_build_object(
    'ok',true,
    'engine_version','CLIENT_LIFECYCLE_CONTROL_V93_TENANT',
    'count',jsonb_array_length(v_items),
    'items',v_items,
    'guardrails',jsonb_build_object(
      'tenant_scoped',true,'read_only_aggregate',true,
      'mutations_reuse_existing_backend',true,'no_auto_publish',true,'no_synthetic_identity',true
    )
  );
end;
$function$;

create or replace function public.resolve_cv12_native_client_v91(p_email text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid:=auth.uid();
  v_role public.app_role;
  v_email text:=lower(btrim(coalesce(p_email,'')));
  v_client_id uuid;
  v_client_name text;
  v_profile_status public.profile_status;
  v_onboarding public.onboarding_status;
  v_organization uuid;
  v_relationship boolean:=false;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  select role into v_role
  from public.profiles
  where id=v_uid and status='active'::public.profile_status;
  if v_role is null or v_role not in ('admin'::public.app_role,'coach'::public.app_role) then
    raise exception 'Coach/admin required';
  end if;
  if v_email='' or position('@' in v_email)<=1 then raise exception 'Valid email required'; end if;

  select p.id,concat_ws(' ',p.first_name,p.last_name),p.status
  into v_client_id,v_client_name,v_profile_status
  from auth.users u
  join public.profiles p
    on p.id=u.id and p.role='client'::public.app_role
  where lower(u.email)=v_email
  limit 1;

  if v_client_id is null then
    return jsonb_build_object(
      'ok',true,'engine_version','CV12_CUTOVER_CONTROL_API_V91_TENANT',
      'resolution','identity_not_found','email',v_email,'client_id',null,
      'ready_for_v90',false,'next_action','provision_real_client_identity'
    );
  end if;

  v_organization:=private.resolve_legacy_professional_organization_v1(v_uid,v_client_id);

  if not (
    private.is_org_admin(v_organization)
    or private.actor_can_manage_client_in_org_v1(v_uid,v_organization,v_client_id)
  ) then raise exception 'Client outside professional scope in organization'; end if;

  select cp.onboarding_status
  into v_onboarding
  from public.client_profiles cp
  where cp.organization_id=v_organization
    and cp.client_id=v_client_id;

  v_relationship:=
    private.is_org_admin(v_organization)
    or private.actor_can_manage_client_in_org_v1(v_uid,v_organization,v_client_id);

  return jsonb_build_object(
    'ok',true,
    'engine_version','CV12_CUTOVER_CONTROL_API_V91_TENANT',
    'resolution','identity_found',
    'organization_id',v_organization,
    'email',v_email,'client_id',v_client_id,'client_name',v_client_name,
    'profile_status',v_profile_status,'onboarding_status',v_onboarding,
    'coach_relationship_status',case when v_relationship then 'active' else 'inactive' end,
    'ready_for_v90',(
      v_profile_status='active'::public.profile_status
      and v_onboarding is not null
      and v_relationship
    ),
    'next_action',case
      when v_profile_status<>'active'::public.profile_status then 'activate_client_profile'
      when v_onboarding is null then 'create_client_profile'
      when not v_relationship then 'assign_client_to_coach'
      else 'execute_v90'
    end
  );
end;
$function$;

create or replace function public.provision_client_records_backend(
  p_actor_id uuid,
  p_client_id uuid,
  p_email text,
  p_first_name text,
  p_last_name text default null::text,
  p_phone text default null::text,
  p_created_user boolean default false,
  p_client_url text default 'https://cv-coach-roan.vercel.app'::text,
  p_record_invite boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','private'
as $function$
declare
  v_request_role text:=coalesce(auth.role(),'');
  v_request_user uuid:=auth.uid();
  v_actor_role public.app_role;
  v_actor_status public.profile_status;
  v_existing_role public.app_role;
  v_email text:=lower(trim(coalesce(p_email,'')));
  v_first_name text:=trim(coalesce(p_first_name,''));
  v_last_name text:=nullif(trim(coalesce(p_last_name,'')),'');
  v_phone text:=nullif(trim(coalesce(p_phone,'')),'');
  v_organization uuid;
  v_member public.organization_members%rowtype;
  v_client_entity uuid;
  v_coach_entity uuid;
  v_assignment_role public.client_coach_assignment_role;
  v_existing_profile_org uuid;
begin
  if v_request_role<>'service_role'
     and (v_request_user is null or v_request_user<>p_actor_id) then
    raise exception 'Authenticated actor mismatch';
  end if;

  select role,status into v_actor_role,v_actor_status
  from public.profiles
  where id=p_actor_id;

  if not found
     or v_actor_status<>'active'::public.profile_status
     or v_actor_role not in ('admin'::public.app_role,'coach'::public.app_role) then
    raise exception 'Forbidden' using errcode='42501';
  end if;

  if p_client_id is null or p_actor_id=p_client_id then
    return jsonb_build_object('ok',false,'code','invalid_client');
  end if;
  if v_email='' or v_first_name='' then
    return jsonb_build_object('ok',false,'code','invalid_input');
  end if;
  if p_client_url<>'https://cv-coach-roan.vercel.app' then
    return jsonb_build_object('ok',false,'code','invalid_client_url');
  end if;

  v_organization:=private.resolve_legacy_professional_organization_v1(p_actor_id,p_client_id);

  if not (
    v_request_role='service_role'
    or private.is_org_admin(v_organization)
    or private.actor_can_manage_client_in_org_v1(p_actor_id,v_organization,p_client_id)
  ) then
    raise exception 'Forbidden for organization' using errcode='42501';
  end if;

  select role into v_existing_role
  from public.profiles
  where id=p_client_id;

  if found and v_existing_role<>'client'::public.app_role then
    return jsonb_build_object('ok',false,'code','internal_account');
  end if;

  insert into public.profiles(id,role,status,first_name,last_name,phone)
  values(
    p_client_id,'client','active',
    left(v_first_name,80),left(v_last_name,80),left(v_phone,40)
  )
  on conflict(id) do update set
    first_name=excluded.first_name,last_name=excluded.last_name,
    phone=excluded.phone,status='active',updated_at=now();

  select * into v_member
  from public.organization_members om
  where om.organization_id=v_organization and om.user_id=p_client_id
  for update;

  if not found then
    insert into public.organization_members(organization_id,user_id,role,status,joined_at)
    values(
      v_organization,p_client_id,
      'client'::public.organization_member_role,
      'active'::public.organization_member_status,now()
    );
  else
    if v_member.role<>'client'::public.organization_member_role then
      raise exception 'client user already has a non-client role in organization';
    end if;
    if v_member.status<>'active'::public.organization_member_status then
      raise exception 'client organization membership is not active';
    end if;
  end if;

  insert into public.clients(
    organization_id,user_id,status,display_name,contact_metadata,onboarding_state,created_by
  )
  values(
    v_organization,p_client_id,'active'::public.client_status,
    left(btrim(v_first_name||coalesce(' '||v_last_name,'')),160),
    jsonb_strip_nulls(jsonb_build_object(
      'email',v_email,'phone',v_phone,'source','provision_client_records_backend'
    )),
    jsonb_build_object('status','pending'),p_actor_id
  )
  on conflict(organization_id,user_id) do update set
    status='active'::public.client_status,
    display_name=excluded.display_name,
    contact_metadata=public.clients.contact_metadata||excluded.contact_metadata,
    updated_at=now()
  returning id into v_client_entity;

  select organization_id into v_existing_profile_org
  from public.client_profiles
  where client_id=p_client_id;

  if v_existing_profile_org is not null and v_existing_profile_org<>v_organization then
    raise exception 'client personal state is still bound to another organization pending composite identity cutover';
  end if;

  insert into public.client_profiles(
    organization_id,client_id,onboarding_status,timezone
  )
  values(
    v_organization,p_client_id,'pending'::public.onboarding_status,'America/Santiago'
  )
  on conflict(client_id) do update set
    updated_at=now()
  where public.client_profiles.organization_id=excluded.organization_id;

  select cp.id into v_coach_entity
  from public.coach_profiles cp
  where cp.organization_id=v_organization
    and cp.user_id=p_actor_id
    and cp.status='active'::public.coach_profile_status
  limit 1;

  if v_coach_entity is not null
     and not exists(
       select 1 from public.client_coach_assignments a
       where a.organization_id=v_organization
         and a.client_id=v_client_entity
         and a.coach_id=v_coach_entity
         and a.status='active'::public.client_coach_assignment_status
     ) then
    v_assignment_role:=case
      when exists(
        select 1 from public.client_coach_assignments a
        where a.organization_id=v_organization
          and a.client_id=v_client_entity
          and a.assignment_role='primary'::public.client_coach_assignment_role
          and a.status='active'::public.client_coach_assignment_status
      )
      then 'secondary'::public.client_coach_assignment_role
      else 'primary'::public.client_coach_assignment_role
    end;

    insert into public.client_coach_assignments(
      organization_id,client_id,coach_id,assignment_role,status,assigned_at,assigned_by
    )
    values(
      v_organization,v_client_entity,v_coach_entity,v_assignment_role,
      'active'::public.client_coach_assignment_status,now(),p_actor_id
    );
  end if;

  if not exists(
    select 1 from public.coach_clients
    where organization_id=v_organization
      and coach_id=p_actor_id
      and client_id=p_client_id
      and status='active'::public.coach_client_status
  ) then
    insert into public.coach_clients(
      organization_id,coach_id,client_id,status
    )
    values(
      v_organization,p_actor_id,p_client_id,'active'::public.coach_client_status
    );
  end if;

  if p_record_invite then
    insert into public.client_invites(
      organization_id,coach_id,client_id,email,status,metadata
    )
    values(
      v_organization,p_actor_id,p_client_id,v_email,'generated',
      jsonb_build_object(
        'organization_id',v_organization,
        'created_user',coalesce(p_created_user,false),
        'client_url',p_client_url
      )
    );
  end if;

  return jsonb_build_object(
    'ok',true,'organization_id',v_organization,
    'client_id',p_client_id,'client_entity_id',v_client_entity,
    'invite_recorded',p_record_invite
  );
end;
$function$;

comment on function public.manage_client_subscription_backend(uuid,uuid,uuid,uuid,public.subscription_status,timestamptz,timestamptz,timestamptz,text,text)
is 'F1.M1.S5 H3B1 tenant-scoped subscription mutation.';
comment on function public.manage_subscription_billing_backend(uuid,uuid,uuid,date,public.billing_status,integer,timestamptz,text,text,text)
is 'F1.M1.S5 H3B1 tenant-scoped billing mutation.';
comment on function public.get_client_lifecycle_center_v93(uuid)
is 'F1.M1.S5 H3B1 tenant-scoped lifecycle aggregate. Same user may appear independently in multiple Organizations.';
