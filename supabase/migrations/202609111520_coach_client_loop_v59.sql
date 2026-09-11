-- CV Coach V59 · Coach <-> Client Loop
-- Keeps historical risk evidence while clearing resolved coach attention,
-- audits direct alert closes, and notifies clients when a draft program becomes active.

create or replace function public.resolve_coach_alert_backend(
  p_actor_id uuid,
  p_alert_id uuid,
  p_resolution text default 'resolved',
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_alert public.coach_alerts%rowtype;
  v_actor_role text;
  v_request_role text:=coalesce(auth.role(),'');
  v_request_user uuid:=auth.uid();
  v_resolution public.alert_status;
  v_other_active_risk boolean:=false;
  v_risk_attention_cleared boolean:=false;
begin
  if p_actor_id is null or p_alert_id is null then
    raise exception 'actor_id and alert_id are required';
  end if;
  if v_request_role<>'service_role' and (v_request_user is null or v_request_user<>p_actor_id) then
    raise exception 'actor identity mismatch';
  end if;
  if lower(coalesce(p_resolution,'')) not in ('resolved','dismissed') then
    raise exception 'resolution must be resolved or dismissed';
  end if;
  if char_length(coalesce(p_note,''))>500 then
    raise exception 'resolution note too long';
  end if;
  v_resolution:=lower(p_resolution)::public.alert_status;

  select role::text into v_actor_role
  from public.profiles
  where id=p_actor_id and status::text='active';
  if v_actor_role not in ('admin','coach') then
    raise exception 'actor is not authorized to resolve coach alerts';
  end if;

  select * into v_alert
  from public.coach_alerts
  where id=p_alert_id
  for update;
  if not found then raise exception 'coach alert not found'; end if;

  if v_actor_role='coach' then
    if v_alert.coach_id<>p_actor_id or not exists(
      select 1 from public.coach_clients cc
      where cc.coach_id=p_actor_id and cc.client_id=v_alert.client_id
        and cc.status='active'::public.coach_client_status
    ) then
      raise exception 'coach is not assigned to this alert client';
    end if;
  end if;

  if v_alert.status not in ('open'::public.alert_status,'acknowledged'::public.alert_status) then
    return jsonb_build_object(
      'alert_id',v_alert.id,'client_id',v_alert.client_id,'status',v_alert.status::text,
      'idempotent',true,'risk_attention_cleared',false
    );
  end if;

  update public.coach_alerts
  set status=v_resolution,
      resolved_at=coalesce(resolved_at,now()),
      updated_at=now(),
      source_data=coalesce(source_data,'{}'::jsonb)||jsonb_strip_nulls(jsonb_build_object(
        'resolved_by',p_actor_id,
        'resolution',v_resolution::text,
        'resolution_note',nullif(btrim(coalesce(p_note,'')),''),
        'resolved_at',now()
      ))
  where id=v_alert.id;

  if v_alert.alert_type in ('training_risk','weekly_recovery') then
    select exists(
      select 1 from public.coach_alerts a
      where a.client_id=v_alert.client_id
        and a.id<>v_alert.id
        and a.alert_type in ('training_risk','weekly_recovery')
        and a.status in ('open'::public.alert_status,'acknowledged'::public.alert_status)
    ) into v_other_active_risk;

    if not v_other_active_risk then
      update public.client_risk_state
      set requires_coach=false,updated_at=now()
      where client_id=v_alert.client_id and requires_coach=true;
      v_risk_attention_cleared:=found;
    end if;
  end if;

  return jsonb_build_object(
    'alert_id',v_alert.id,
    'client_id',v_alert.client_id,
    'status',v_resolution::text,
    'idempotent',false,
    'risk_attention_cleared',v_risk_attention_cleared,
    'risk_level_preserved',(select level::text from public.client_risk_state where client_id=v_alert.client_id),
    'risk_score_preserved',(select score from public.client_risk_state where client_id=v_alert.client_id)
  );
end;
$function$;

revoke all on function public.resolve_coach_alert_backend(uuid,uuid,text,text) from public;
grant execute on function public.resolve_coach_alert_backend(uuid,uuid,text,text) to authenticated,service_role;

create or replace function public.get_coach_attention_queue()
returns table(
  client_id uuid, first_name text, last_name text, risk_level public.risk_level, risk_score integer,
  risk_reason text, requires_coach boolean, open_alerts integer, critical_alerts integer,
  warning_alerts integer, pending_progressions integer, last_workout_at timestamptz,
  days_since_workout integer, attention_score integer, priority text, next_action text
)
language sql
stable security definer
set search_path to ''
as $function$
  with base as (
    select
      cc.client_id,p.first_name,p.last_name,
      coalesce(r.level,'GREEN'::public.risk_level) as risk_level,
      coalesce(r.score,0) as risk_score,
      r.reason_text as risk_reason,
      coalesce(r.requires_coach,false) as requires_coach,
      coalesce(a.open_alerts,0)::integer as open_alerts,
      coalesce(a.critical_alerts,0)::integer as critical_alerts,
      coalesce(a.warning_alerts,0)::integer as warning_alerts,
      coalesce(a.weekly_program_review_alerts,0)::integer as weekly_program_review_alerts,
      coalesce(a.active_risk_alerts,0)::integer as active_risk_alerts,
      coalesce(ps.pending_progressions,0)::integer as pending_progressions,
      w.last_workout_at,
      case when w.last_workout_at is null then null
           else floor(extract(epoch from (now()-w.last_workout_at))/86400)::integer end as days_since_workout
    from public.coach_clients cc
    join public.profiles p on p.id=cc.client_id
    left join public.client_risk_state r on r.client_id=cc.client_id
    left join lateral (
      select
        count(*) filter(where ca.status in ('open'::public.alert_status,'acknowledged'::public.alert_status))::integer as open_alerts,
        count(*) filter(where ca.status in ('open'::public.alert_status,'acknowledged'::public.alert_status) and ca.severity='critical'::public.alert_severity)::integer as critical_alerts,
        count(*) filter(where ca.status in ('open'::public.alert_status,'acknowledged'::public.alert_status) and ca.severity='warning'::public.alert_severity)::integer as warning_alerts,
        count(*) filter(where ca.status in ('open'::public.alert_status,'acknowledged'::public.alert_status) and ca.alert_type='weekly_program_review')::integer as weekly_program_review_alerts,
        count(*) filter(where ca.status in ('open'::public.alert_status,'acknowledged'::public.alert_status) and ca.alert_type in ('training_risk','weekly_recovery'))::integer as active_risk_alerts
      from public.coach_alerts ca
      where ca.client_id=cc.client_id and ca.coach_id=cc.coach_id
    ) a on true
    left join lateral (
      select count(*)::integer as pending_progressions
      from public.progression_suggestions s
      where s.client_id=cc.client_id and s.status='pending'::public.progression_status
    ) ps on true
    left join lateral (
      select max(coalesce(ws.finished_at,ws.started_at)) as last_workout_at
      from public.workout_sessions ws
      where ws.client_id=cc.client_id and ws.status::text in ('completed','partial','abandoned')
    ) w on true
    where cc.status='active'::public.coach_client_status
      and (cc.coach_id=auth.uid() or private.is_admin() or auth.role()='service_role')
  ), scored as (
    select b.*,
      greatest(
        (
          case when b.requires_coach or b.active_risk_alerts>0 then
            (case b.risk_level
              when 'RED'::public.risk_level then 100
              when 'YELLOW'::public.risk_level then 60
              else 0 end)+b.risk_score
          else 0 end
          + b.critical_alerts*40
          + b.warning_alerts*15
          + least(b.pending_progressions,5)*3
          + case when b.days_since_workout is null then 20
                 when b.days_since_workout>=14 then 25
                 when b.days_since_workout>=7 then 10 else 0 end
        )::integer,
        case when b.weekly_program_review_alerts>0 then 20 else 0 end
      )::integer as attention_score
    from base b
  )
  select
    s.client_id,s.first_name,s.last_name,s.risk_level,s.risk_score,s.risk_reason,s.requires_coach,
    s.open_alerts,s.critical_alerts,s.warning_alerts,s.pending_progressions,
    s.last_workout_at,s.days_since_workout,s.attention_score,
    case when s.attention_score>=120 then 'CRITICAL'
         when s.attention_score>=60 then 'HIGH'
         when s.attention_score>=20 then 'MEDIUM' else 'NORMAL' end as priority,
    case
      when (s.requires_coach or s.active_risk_alerts>0)
           and (s.risk_level='RED'::public.risk_level or s.critical_alerts>0) then 'Revisar inmediatamente'
      when s.weekly_program_review_alerts>0 then 'Revisar programación semanal'
      when (s.requires_coach or s.active_risk_alerts>0)
           and (s.risk_level='YELLOW'::public.risk_level or s.warning_alerts>0) then 'Revisar señales de entrenamiento'
      when s.days_since_workout is null or s.days_since_workout>=14 then 'Contactar por inactividad'
      when s.pending_progressions>0 then 'Revisar progresiones pendientes'
      else 'Sin acción prioritaria'
    end as next_action
  from scored s
  order by s.attention_score desc,s.last_name,s.first_name;
$function$;

create or replace function private.notify_client_program_published_v59()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if old.status='draft'::public.program_status and new.status='active'::public.program_status then
    insert into public.notifications(user_id,type,title,body,action_url,metadata)
    values(
      new.client_id,
      'program_published',
      'Nueva rutina publicada',
      'Tu coach publicó una nueva versión de tu rutina. Revísala antes de tu próximo entrenamiento.',
      '/routine',
      jsonb_build_object(
        'program_id',new.id,'version',new.version,'coach_id',new.coach_id,'published_at',new.published_at
      )
    );
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_notify_client_program_published_v59 on public.programs;
create trigger trg_notify_client_program_published_v59
after update of status on public.programs
for each row
when (old.status is distinct from new.status)
execute function private.notify_client_program_published_v59();

-- Preserve compatibility with the current Admin direct PATCH while adding
-- audit metadata and reconciling coach-attention state.
create or replace function private.audit_coach_alert_close_v59()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if old.status in ('open'::public.alert_status,'acknowledged'::public.alert_status)
     and new.status in ('resolved'::public.alert_status,'dismissed'::public.alert_status) then
    new.resolved_at:=coalesce(new.resolved_at,now());
    new.updated_at:=now();
    new.source_data:=coalesce(new.source_data,'{}'::jsonb)||jsonb_strip_nulls(jsonb_build_object(
      'resolved_by',auth.uid(),
      'resolution',new.status::text,
      'resolved_at',new.resolved_at
    ));
  end if;
  return new;
end;
$function$;

create or replace function private.reconcile_risk_attention_on_alert_close_v59()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if old.status in ('open'::public.alert_status,'acknowledged'::public.alert_status)
     and new.status in ('resolved'::public.alert_status,'dismissed'::public.alert_status)
     and new.alert_type in ('training_risk','weekly_recovery')
     and not exists(
       select 1 from public.coach_alerts a
       where a.client_id=new.client_id
         and a.id<>new.id
         and a.alert_type in ('training_risk','weekly_recovery')
         and a.status in ('open'::public.alert_status,'acknowledged'::public.alert_status)
     ) then
    update public.client_risk_state
    set requires_coach=false,updated_at=now()
    where client_id=new.client_id and requires_coach=true;
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_audit_coach_alert_close_v59 on public.coach_alerts;
create trigger trg_audit_coach_alert_close_v59
before update of status on public.coach_alerts
for each row
when (old.status is distinct from new.status)
execute function private.audit_coach_alert_close_v59();

drop trigger if exists trg_reconcile_risk_attention_v59 on public.coach_alerts;
create trigger trg_reconcile_risk_attention_v59
after update of status on public.coach_alerts
for each row
when (old.status is distinct from new.status)
execute function private.reconcile_risk_attention_on_alert_close_v59();
