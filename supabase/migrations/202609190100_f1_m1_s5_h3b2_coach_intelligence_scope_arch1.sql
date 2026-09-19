-- F1.M1.S5 H3B2 — Coach Intelligence tenant scope
-- Separates coach recommendations, action workspace, outcome learning and dashboard data by Organization.

alter table private.coach_action_workspace_v95
  add column if not exists organization_id uuid;

update private.coach_action_workspace_v95 w
set organization_id=private.resolve_legacy_professional_organization_v1(w.actor_id,w.client_id)
where w.organization_id is null;

alter table private.coach_action_workspace_v95
  alter column organization_id set not null;

alter table private.coach_action_workspace_v95
  drop constraint if exists coach_action_workspace_v95_actor_id_recommendation_key_key;

alter table private.coach_action_workspace_v95
  drop constraint if exists coach_action_workspace_v95_organization_id_fkey;
alter table private.coach_action_workspace_v95
  add constraint coach_action_workspace_v95_organization_id_fkey
  foreign key(organization_id) references public.organizations(id) on delete restrict;

alter table private.coach_action_workspace_v95
  drop constraint if exists coach_action_workspace_v95_client_same_org;
alter table private.coach_action_workspace_v95
  add constraint coach_action_workspace_v95_client_same_org
  foreign key(organization_id,client_id)
  references public.clients(organization_id,user_id) on delete restrict;

create unique index if not exists ux_coach_action_workspace_v95_org_id
  on private.coach_action_workspace_v95(organization_id,id);

create unique index if not exists uq_coach_action_workspace_v95_org_actor_recommendation
  on private.coach_action_workspace_v95(organization_id,actor_id,recommendation_key);

create index if not exists idx_coach_action_workspace_v95_org_client_updated
  on private.coach_action_workspace_v95(organization_id,client_id,updated_at desc);

update private.coach_action_workspace_v95
set recommendation_snapshot=
  jsonb_build_object('organization_id',organization_id)
  ||coalesce(recommendation_snapshot,'{}'::jsonb)
where coalesce(recommendation_snapshot->>'organization_id','')<>organization_id::text;

alter table private.coach_action_outcome_events_v96
  add column if not exists organization_id uuid;

update private.coach_action_outcome_events_v96 e
set organization_id=w.organization_id
from private.coach_action_workspace_v95 w
where w.id=e.workspace_id
  and e.organization_id is null;

alter table private.coach_action_outcome_events_v96
  alter column organization_id set not null;

alter table private.coach_action_outcome_events_v96
  drop constraint if exists coach_action_outcome_events_v_workspace_id_evidence_fingerp_key;

alter table private.coach_action_outcome_events_v96
  drop constraint if exists coach_action_outcome_events_v96_organization_id_fkey;
alter table private.coach_action_outcome_events_v96
  add constraint coach_action_outcome_events_v96_organization_id_fkey
  foreign key(organization_id) references public.organizations(id) on delete restrict;

alter table private.coach_action_outcome_events_v96
  drop constraint if exists coach_action_outcome_events_v96_client_same_org;
alter table private.coach_action_outcome_events_v96
  add constraint coach_action_outcome_events_v96_client_same_org
  foreign key(organization_id,client_id)
  references public.clients(organization_id,user_id) on delete restrict;

alter table private.coach_action_outcome_events_v96
  drop constraint if exists coach_action_outcome_events_v96_workspace_same_org;
alter table private.coach_action_outcome_events_v96
  add constraint coach_action_outcome_events_v96_workspace_same_org
  foreign key(organization_id,workspace_id)
  references private.coach_action_workspace_v95(organization_id,id) on delete cascade;

create unique index if not exists uq_coach_action_outcome_v96_org_workspace_fingerprint
  on private.coach_action_outcome_events_v96(organization_id,workspace_id,evidence_fingerprint);

create index if not exists idx_coach_action_outcome_v96_org_actor_assessed
  on private.coach_action_outcome_events_v96(organization_id,actor_id,assessed_at desc);

revoke all on private.coach_action_workspace_v95 from public,anon,authenticated;
revoke all on private.coach_action_outcome_events_v96 from public,anon,authenticated;

create or replace function private.get_coach_attention_queue_tenant_v1(p_actor_id uuid)
returns table(
  organization_id uuid,
  client_id uuid,
  first_name text,
  last_name text,
  risk_level public.risk_level,
  risk_score integer,
  risk_reason text,
  requires_coach boolean,
  open_alerts integer,
  critical_alerts integer,
  warning_alerts integer,
  pending_progressions integer,
  last_workout_at timestamptz,
  days_since_workout integer,
  attention_score integer,
  priority text,
  next_action text
)
language sql
stable
security definer
set search_path to ''
as $function$
  with canonical_assignments as (
    select distinct
      a.organization_id,
      cl.user_id as client_user_id,
      cp.user_id as coach_user_id
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
    where a.status='active'::public.client_coach_assignment_status
      and (
        cp.user_id=p_actor_id
        or private.is_org_admin(a.organization_id)
      )
  ),
  base as (
    select
      ca.organization_id,
      ca.client_user_id as client_id,
      p.first_name,
      p.last_name,
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
      case
        when w.last_workout_at is null then null
        else floor(extract(epoch from (now()-w.last_workout_at))/86400)::integer
      end as days_since_workout
    from canonical_assignments ca
    join public.profiles p on p.id=ca.client_user_id
    left join public.client_risk_state r
      on r.organization_id=ca.organization_id
     and r.client_id=ca.client_user_id
    left join lateral (
      select
        count(*) filter(
          where alert.status in ('open'::public.alert_status,'acknowledged'::public.alert_status)
        )::integer as open_alerts,
        count(*) filter(
          where alert.status in ('open'::public.alert_status,'acknowledged'::public.alert_status)
            and alert.severity='critical'::public.alert_severity
        )::integer as critical_alerts,
        count(*) filter(
          where alert.status in ('open'::public.alert_status,'acknowledged'::public.alert_status)
            and alert.severity='warning'::public.alert_severity
        )::integer as warning_alerts,
        count(*) filter(
          where alert.status in ('open'::public.alert_status,'acknowledged'::public.alert_status)
            and alert.alert_type='weekly_program_review'
        )::integer as weekly_program_review_alerts,
        count(*) filter(
          where alert.status in ('open'::public.alert_status,'acknowledged'::public.alert_status)
            and alert.alert_type in ('training_risk','weekly_recovery')
        )::integer as active_risk_alerts
      from public.coach_alerts alert
      where alert.organization_id=ca.organization_id
        and alert.client_id=ca.client_user_id
        and (
          alert.coach_id=ca.coach_user_id
          or private.is_org_admin(ca.organization_id)
        )
    ) a on true
    left join lateral (
      select count(*)::integer as pending_progressions
      from public.progression_suggestions s
      where s.organization_id=ca.organization_id
        and s.client_id=ca.client_user_id
        and s.status='pending'::public.progression_status
    ) ps on true
    left join lateral (
      select max(coalesce(ws.finished_at,ws.started_at)) as last_workout_at
      from public.workout_sessions ws
      where ws.organization_id=ca.organization_id
        and ws.client_id=ca.client_user_id
        and ws.status::text in ('completed','partial','abandoned')
    ) w on true
  ),
  scored as (
    select
      b.*,
      greatest(
        (
          case
            when b.requires_coach or b.active_risk_alerts>0 then
              case b.risk_level
                when 'RED'::public.risk_level then 100
                when 'YELLOW'::public.risk_level then 60
                else 0
              end+b.risk_score
            else 0
          end
          +b.critical_alerts*40
          +b.warning_alerts*15
          +least(b.pending_progressions,5)*3
          +case
            when b.days_since_workout is null then 20
            when b.days_since_workout>=14 then 25
            when b.days_since_workout>=7 then 10
            else 0
          end
        )::integer,
        case when b.weekly_program_review_alerts>0 then 20 else 0 end
      )::integer as attention_score
    from base b
  )
  select
    s.organization_id,s.client_id,s.first_name,s.last_name,
    s.risk_level,s.risk_score,s.risk_reason,s.requires_coach,
    s.open_alerts,s.critical_alerts,s.warning_alerts,s.pending_progressions,
    s.last_workout_at,s.days_since_workout,s.attention_score,
    case
      when s.attention_score>=120 then 'CRITICAL'
      when s.attention_score>=60 then 'HIGH'
      when s.attention_score>=20 then 'MEDIUM'
      else 'NORMAL'
    end as priority,
    case
      when (s.requires_coach or s.active_risk_alerts>0)
           and (s.risk_level='RED'::public.risk_level or s.critical_alerts>0)
        then 'Revisar inmediatamente'
      when s.weekly_program_review_alerts>0 then 'Revisar programación semanal'
      when (s.requires_coach or s.active_risk_alerts>0)
           and (s.risk_level='YELLOW'::public.risk_level or s.warning_alerts>0)
        then 'Revisar señales de entrenamiento'
      when s.days_since_workout is null or s.days_since_workout>=14
        then 'Contactar por inactividad'
      when s.pending_progressions>0 then 'Revisar progresiones pendientes'
      else 'Sin acción prioritaria'
    end as next_action
  from scored s
  order by s.attention_score desc,s.organization_id,s.last_name,s.first_name
$function$;

revoke all on function private.get_coach_attention_queue_tenant_v1(uuid) from public,anon,authenticated;
grant execute on function private.get_coach_attention_queue_tenant_v1(uuid) to service_role;

create or replace function public.get_coach_intelligence_dashboard_v86(p_actor_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_role public.app_role;
  v_attention jsonb;
  v_alerts jsonb;
  v_progressions jsonb;
  v_adaptations jsonb;
  v_pilots jsonb;
  v_summary jsonb;
begin
  if auth.uid() is null or auth.uid()<>p_actor_id then
    raise exception 'Actor authentication mismatch';
  end if;

  select role into v_role
  from public.profiles
  where id=p_actor_id and status='active'::public.profile_status;

  if v_role is null or v_role not in ('admin'::public.app_role,'coach'::public.app_role) then
    raise exception 'Coach/admin role required';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'organization_id',q.organization_id,
      'client_id',q.client_id,
      'first_name',q.first_name,
      'last_name',q.last_name,
      'risk_level',q.risk_level,
      'risk_score',q.risk_score,
      'risk_reason',q.risk_reason,
      'requires_coach',q.requires_coach,
      'open_alerts',q.open_alerts,
      'critical_alerts',q.critical_alerts,
      'warning_alerts',q.warning_alerts,
      'pending_progressions',q.pending_progressions,
      'last_workout_at',q.last_workout_at,
      'days_since_workout',q.days_since_workout,
      'attention_score',q.attention_score,
      'priority',q.priority,
      'next_action',q.next_action
    )
    order by q.attention_score desc,q.organization_id,q.last_name,q.first_name
  ),'[]'::jsonb)
  into v_attention
  from private.get_coach_attention_queue_tenant_v1(p_actor_id) q;

  select coalesce(jsonb_agg(jsonb_build_object(
    'organization_id',a.organization_id,
    'id',a.id,
    'client_id',a.client_id,
    'client_name',concat_ws(' ',p.first_name,p.last_name),
    'alert_type',a.alert_type,
    'severity',a.severity::text,
    'title',a.title,
    'message',a.message,
    'status',a.status::text,
    'created_at',a.created_at
  ) order by
    case a.severity::text when 'critical' then 0 when 'warning' then 1 else 2 end,
    a.created_at desc
  ),'[]'::jsonb)
  into v_alerts
  from public.coach_alerts a
  join public.profiles p on p.id=a.client_id
  where a.status::text in ('open','acknowledged')
    and (
      private.is_org_admin(a.organization_id)
      or private.actor_can_manage_client_in_org_v1(
        p_actor_id,a.organization_id,a.client_id
      )
    );

  select coalesce(jsonb_agg(jsonb_build_object(
    'organization_id',s.organization_id,
    'id',s.id,
    'client_id',s.client_id,
    'client_name',concat_ws(' ',p.first_name,p.last_name),
    'exercise_name',e.name,
    'action',s.action,
    'reason_text',s.reason_text,
    'confidence',s.confidence,
    'confidence_band',s.confidence_band,
    'created_at',s.created_at
  ) order by s.created_at desc),'[]'::jsonb)
  into v_progressions
  from public.progression_suggestions s
  join public.profiles p on p.id=s.client_id
  join public.exercises e on e.id=s.exercise_id
  where s.status::text='pending'
    and (
      private.is_org_admin(s.organization_id)
      or private.actor_can_manage_client_in_org_v1(
        p_actor_id,s.organization_id,s.client_id
      )
    );

  select coalesce(jsonb_agg(jsonb_build_object(
    'organization_id',r.organization_id,
    'id',r.id,
    'client_id',r.client_id,
    'client_name',concat_ws(' ',p.first_name,p.last_name),
    'program_id',r.program_id,
    'state',r.state,
    'block_week',r.block_week,
    'recent_sessions',r.recent_sessions,
    'progress_signals',r.progress_signals,
    'stagnation_signals',r.stagnation_signals,
    'recovery_flags',r.recovery_flags,
    'average_completion_pct',r.average_completion_pct,
    'deload_recommended',r.deload_recommended,
    'status',r.status,
    'created_at',r.created_at
  ) order by r.created_at desc),'[]'::jsonb)
  into v_adaptations
  from public.training_adaptation_reviews r
  join public.profiles p on p.id=r.client_id
  where r.status in ('pending','reviewed')
    and (
      private.is_org_admin(r.organization_id)
      or private.actor_can_manage_client_in_org_v1(
        p_actor_id,r.organization_id,r.client_id
      )
    );

  select coalesce(jsonb_agg(jsonb_build_object(
    'organization_id',x.organization_id,
    'id',x.id,
    'client_id',x.client_id,
    'subject_label',x.subject_label,
    'source_system',x.source_system,
    'source_external_id',x.source_external_id,
    'mode',x.mode,
    'status',x.status,
    'engine_version',x.engine_version,
    'baseline_snapshot',x.baseline_snapshot,
    'started_at',x.started_at,
    'linked_at',x.linked_at,
    'ready_for_v85',case
      when x.client_id is not null then true
      when coalesce((x.baseline_snapshot->>'sessions_completed')::integer,0)>=3
       and coalesce((x.baseline_snapshot->>'evidence_exercises')::integer,0)>=2
      then true
      else false
    end,
    'next_action',case
      when x.status='collecting_baseline'
       and coalesce((x.baseline_snapshot->>'sessions_completed')::integer,0)<3
        then 'Recolectar al menos 3 sesiones completadas antes de interpretar tendencia longitudinal.'
      when x.client_id is null
        then 'Mantener observación shadow hasta vincular una cuenta nativa de CV Coach.'
      else 'Revisar recomendaciones; ninguna decisión se aplica automáticamente.'
    end
  ) order by x.updated_at desc),'[]'::jsonb)
  into v_pilots
  from public.coach_intelligence_pilots x
  where private.is_org_admin(x.organization_id)
     or x.coach_id=p_actor_id;

  with visible_clients as (
    select distinct c.organization_id,c.user_id
    from public.clients c
    where c.user_id is not null
      and c.status<>'archived'::public.client_status
      and (
        private.is_org_admin(c.organization_id)
        or private.actor_can_manage_client_in_org_v1(
          p_actor_id,c.organization_id,c.user_id
        )
      )
  )
  select jsonb_build_object(
    'native_clients',count(*),
    'open_alerts',(select count(*) from jsonb_array_elements(v_alerts)),
    'pending_progressions',(select count(*) from jsonb_array_elements(v_progressions)),
    'deload_reviews',(
      select count(*) from jsonb_array_elements(v_adaptations) a
      where coalesce((a->>'deload_recommended')::boolean,false)
    ),
    'active_pilots',(
      select count(*) from jsonb_array_elements(v_pilots) p
      where p->>'status' not in ('paused','completed')
    ),
    'high_attention',(
      select count(*) from jsonb_array_elements(v_attention) q
      where q->>'priority' in ('CRITICAL','HIGH')
    )
  ) into v_summary
  from visible_clients;

  return jsonb_build_object(
    'engine_version','COACH_INTELLIGENCE_V86_TENANT',
    'generated_at',now(),
    'guardrails',jsonb_build_object(
      'tenant_scoped',true,
      'recommendation_only',true,
      'auto_publish',false,
      'auto_program_edit',false,
      'pilot_mode','observed_only'
    ),
    'summary',coalesce(v_summary,'{}'::jsonb),
    'attention',coalesce(v_attention,'[]'::jsonb),
    'alerts',coalesce(v_alerts,'[]'::jsonb),
    'progressions',coalesce(v_progressions,'[]'::jsonb),
    'adaptations',coalesce(v_adaptations,'[]'::jsonb),
    'pilots',coalesce(v_pilots,'[]'::jsonb)
  );
end;
$function$;

create or replace function private.get_coach_ai_command_center_v94(p_actor_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_role public.app_role;
  v86 jsonb;
  v93 jsonb;
  v_items jsonb;
  v_pilots jsonb;
  v_summary jsonb;
begin
  if auth.uid() is null or p_actor_id is null or auth.uid()<>p_actor_id then
    raise exception 'Authenticated actor mismatch';
  end if;

  select p.role into v_role
  from public.profiles p
  where p.id=p_actor_id and p.status='active'::public.profile_status;
  if v_role is null or v_role not in ('admin'::public.app_role,'coach'::public.app_role) then
    raise exception 'Coach/admin required';
  end if;

  v86:=public.get_coach_intelligence_dashboard_v86(p_actor_id);
  v93:=public.get_client_lifecycle_center_v93(p_actor_id);

  with lifecycle as (
    select
      x->>'organization_id' as organization_id,
      x->>'client_id' as client_id,
      x as item
    from jsonb_array_elements(coalesce(v93->'items','[]'::jsonb)) x
  ),
  attention as (
    select
      x->>'organization_id' as organization_id,
      x->>'client_id' as client_id,
      x as item
    from jsonb_array_elements(coalesce(v86->'attention','[]'::jsonb)) x
  ),
  alert_agg as (
    select
      x->>'organization_id' as organization_id,
      x->>'client_id' as client_id,
      count(*)::int as open_alerts,
      count(*) filter(where lower(coalesce(x->>'severity',''))='critical')::int as critical_alerts,
      count(*) filter(where lower(coalesce(x->>'severity',''))='warning')::int as warning_alerts,
      coalesce(jsonb_agg(jsonb_build_object(
        'id',x->>'id','type',x->>'alert_type','severity',x->>'severity',
        'title',x->>'title','message',x->>'message','created_at',x->>'created_at'
      )),'[]'::jsonb) as alerts
    from jsonb_array_elements(coalesce(v86->'alerts','[]'::jsonb)) x
    group by x->>'organization_id',x->>'client_id'
  ),
  progression_agg as (
    select
      x->>'organization_id' as organization_id,
      x->>'client_id' as client_id,
      count(*)::int as pending_progressions,
      coalesce(jsonb_agg(jsonb_build_object(
        'id',x->>'id','exercise_name',x->>'exercise_name','action',x->>'action',
        'reason_text',x->>'reason_text','confidence',x->>'confidence',
        'confidence_band',x->>'confidence_band','created_at',x->>'created_at'
      )),'[]'::jsonb) as progressions
    from jsonb_array_elements(coalesce(v86->'progressions','[]'::jsonb)) x
    group by x->>'organization_id',x->>'client_id'
  ),
  adaptation_ranked as (
    select
      x->>'organization_id' as organization_id,
      x->>'client_id' as client_id,
      x as item,
      row_number() over(
        partition by x->>'organization_id',x->>'client_id'
        order by nullif(x->>'created_at','')::timestamptz desc nulls last
      ) as rn
    from jsonb_array_elements(coalesce(v86->'adaptations','[]'::jsonb)) x
  ),
  combined as (
    select
      l.organization_id,
      l.client_id,
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
    left join attention a
      on a.organization_id=l.organization_id
     and a.client_id=l.client_id
    left join alert_agg aa
      on aa.organization_id=l.organization_id
     and aa.client_id=l.client_id
    left join progression_agg pa
      on pa.organization_id=l.organization_id
     and pa.client_id=l.client_id
    left join adaptation_ranked ar
      on ar.organization_id=l.organization_id
     and ar.client_id=l.client_id
     and ar.rn=1
  ),
  scored as (
    select c.*,
      greatest(
        0,
        c.base_attention_score+c.lifecycle_weight+c.commercial_weight
        +case when c.deload_recommended then 50 else 0 end
        +least(c.recovery_flags,3)*10
        +least(c.stagnation_signals,3)*7
      )::int as command_score
    from combined c
  ),
  resolved as (
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
      'organization_id',r.organization_id,
      'client_id',r.client_id,
      'client_name',r.item->>'client_name',
      'email',r.item->>'email',
      'primary_goal',r.item->>'primary_goal',
      'priority',case
        when r.command_score>=120 then 'CRITICAL'
        when r.command_score>=70 then 'HIGH'
        when r.command_score>=30 then 'MEDIUM'
        else 'NORMAL'
      end,
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
      'source_versions',jsonb_build_array('V86_COACH_INTELLIGENCE_TENANT','CLIENT_LIFECYCLE_CONTROL_V93_TENANT'),
      'guardrails',jsonb_build_object(
        'tenant_scoped',true,'recommendation_only',true,'read_only_aggregate',true,
        'auto_publish',false,'auto_program_edit',false,
        'no_synthetic_identity',true,'coach_review_required',true
      )
    )
    order by r.command_score desc,r.organization_id,lower(coalesce(r.item->>'client_name',''))
  ),'[]'::jsonb)
  into v_items
  from resolved r;

  select coalesce(jsonb_agg(jsonb_build_object(
    'organization_id',p->>'organization_id',
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
      else 'NORMAL'
    end,
    'guardrails',jsonb_build_object('tenant_scoped',true,'observed_only',true,'no_synthetic_identity',true,'no_auto_action',true)
  ) order by p->>'organization_id',p->>'subject_label'),'[]'::jsonb)
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
    'engine_version','COACH_AI_COMMAND_CENTER_V94_TENANT',
    'generated_at',now(),
    'summary',v_summary,
    'items',v_items,
    'pilots',v_pilots,
    'guardrails',jsonb_build_object(
      'tenant_scoped',true,'recommendation_only',true,'read_only_aggregate',true,
      'source_of_truth_v86',true,'source_of_truth_v93',true,
      'auto_publish',false,'auto_program_edit',false,
      'no_synthetic_identity',true,'coach_review_required',true
    )
  );
end;
$function$;

create or replace function private.current_coach_actions_v95(p_actor_id uuid)
returns table(recommendation_key text,client_id uuid,item jsonb)
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v94 jsonb;
begin
  v94:=public.get_coach_ai_command_center_v94(p_actor_id);

  return query
  with src as (
    select x as item
    from jsonb_array_elements(coalesce(v94->'items','[]'::jsonb)) x
  ),
  actionable as (
    select
      s.item,
      (s.item->>'client_id')::uuid as client_id,
      (s.item->>'organization_id')::uuid as organization_id,
      case
        when nullif(s.item#>>'{training,days_since_workout}','') is null then 'none'
        when (s.item#>>'{training,days_since_workout}')::int<7 then '0_6'
        when (s.item#>>'{training,days_since_workout}')::int<14 then '7_13'
        when (s.item#>>'{training,days_since_workout}')::int<21 then '14_20'
        else '21_plus'
      end as inactivity_bucket
    from src s
    where coalesce(s.item->>'recommended_action_code','monitor_client')<>'monitor_client'
       or coalesce(s.item->>'priority','NORMAL')<>'NORMAL'
  )
  select
    'v95:'||a.organization_id::text||':'||a.client_id::text||':'||
    md5(jsonb_build_object(
      'organization_id',a.organization_id,
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
    jsonb_build_object('organization_id',a.organization_id)||a.item
  from actionable a;
end;
$function$;

create or replace function public.decide_coach_action_v95(
  p_actor_id uuid,
  p_recommendation_key text,
  p_client_id uuid,
  p_decision text,
  p_modified_action_code text default null::text,
  p_modified_action text default null::text,
  p_note text default null::text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_role public.app_role;
  v_item jsonb;
  v_organization uuid;
  v_effective_code text;
  v_effective_action text;
  v_id uuid;
  v_status text;
begin
  if auth.uid() is null or p_actor_id is null or auth.uid()<>p_actor_id then
    raise exception 'Authenticated actor mismatch';
  end if;
  if upper(coalesce(p_decision,'')) not in ('ACCEPTED','MODIFIED','REJECTED') then
    raise exception 'Invalid decision';
  end if;

  select p.role into v_role
  from public.profiles p
  where p.id=p_actor_id and p.status='active'::public.profile_status;
  if v_role is null or v_role not in ('admin'::public.app_role,'coach'::public.app_role) then
    raise exception 'Coach/admin required';
  end if;

  select c.item into v_item
  from private.current_coach_actions_v95(p_actor_id) c
  where c.recommendation_key=p_recommendation_key
    and c.client_id=p_client_id;

  if v_item is null then raise exception 'Recommendation is stale or no longer actionable'; end if;

  v_organization:=nullif(v_item->>'organization_id','')::uuid;
  if v_organization is null then raise exception 'Recommendation organization is missing'; end if;

  if not (
    private.is_org_admin(v_organization)
    or private.actor_can_manage_client_in_org_v1(
      p_actor_id,v_organization,p_client_id
    )
  ) then raise exception 'Client outside coach scope in organization'; end if;

  if upper(p_decision)='MODIFIED'
     and nullif(btrim(coalesce(p_modified_action,'')),'') is null then
    raise exception 'Modified action text is required';
  end if;

  v_effective_code:=case
    when upper(p_decision)='MODIFIED'
      then coalesce(nullif(btrim(p_modified_action_code),''),'custom_coach_action')
    else v_item->>'recommended_action_code'
  end;
  v_effective_action:=case
    when upper(p_decision)='MODIFIED' then btrim(p_modified_action)
    else v_item->>'recommended_action'
  end;
  v_status:=case when upper(p_decision)='REJECTED' then 'REJECTED' else 'READY' end;

  insert into private.coach_action_workspace_v95(
    organization_id,actor_id,client_id,recommendation_key,recommendation_snapshot,
    decision,workflow_status,effective_action_code,effective_action,coach_note,
    execution_target,decided_at,updated_at
  ) values(
    v_organization,p_actor_id,p_client_id,p_recommendation_key,
    jsonb_build_object('organization_id',v_organization)||v_item,
    upper(p_decision),v_status,v_effective_code,v_effective_action,
    nullif(btrim(coalesce(p_note,'')),''),
    private.coach_action_route_v95(v_effective_code),now(),now()
  )
  on conflict(organization_id,actor_id,recommendation_key) do update set
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
    decided_at=now(),
    execution_started_at=null,
    completed_at=null,
    updated_at=now()
  returning id into v_id;

  return jsonb_build_object(
    'ok',true,'organization_id',v_organization,'workspace_id',v_id,
    'decision',upper(p_decision),'workflow_status',v_status,
    'effective_action_code',v_effective_code,'effective_action',v_effective_action,
    'execution_target',private.coach_action_route_v95(v_effective_code),
    'client_data_mutated',false,'training_data_mutated',false,'program_data_mutated',false,
    'auto_publish',false,'auto_program_edit',false
  );
end;
$function$;

create or replace function public.get_coach_action_workspace_v95(p_actor_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_role public.app_role;
  v_current jsonb;
  v_history jsonb;
  v_summary jsonb;
begin
  if auth.uid() is null or p_actor_id is null or auth.uid()<>p_actor_id then
    raise exception 'Authenticated actor mismatch';
  end if;

  select p.role into v_role
  from public.profiles p
  where p.id=p_actor_id and p.status='active'::public.profile_status;
  if v_role is null or v_role not in ('admin'::public.app_role,'coach'::public.app_role) then
    raise exception 'Coach/admin required';
  end if;

  with cur as (
    select
      (c.item->>'organization_id')::uuid as organization_id,
      c.recommendation_key,c.client_id,c.item,
      w.id as workspace_id,w.decision,w.workflow_status,
      w.effective_action_code,w.effective_action,w.coach_note,w.execution_target,
      w.decided_at,w.execution_started_at,w.completed_at,w.updated_at
    from private.current_coach_actions_v95(p_actor_id) c
    left join private.coach_action_workspace_v95 w
      on w.organization_id=(c.item->>'organization_id')::uuid
     and w.actor_id=p_actor_id
     and w.recommendation_key=c.recommendation_key
  )
  select coalesce(jsonb_agg(
    c.item||jsonb_build_object(
      'organization_id',c.organization_id,
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
    )
    order by
      case c.item->>'priority' when 'CRITICAL' then 0 when 'HIGH' then 1 when 'MEDIUM' then 2 else 3 end,
      coalesce((c.item->>'command_score')::int,0) desc,
      c.organization_id,
      lower(coalesce(c.item->>'client_name',''))
  ),'[]'::jsonb)
  into v_current
  from cur c;

  select coalesce(jsonb_agg(jsonb_build_object(
    'organization_id',w.organization_id,
    'id',w.id,'client_id',w.client_id,'recommendation_key',w.recommendation_key,
    'decision',w.decision,'workflow_status',w.workflow_status,
    'effective_action_code',w.effective_action_code,'effective_action',w.effective_action,
    'coach_note',w.coach_note,'execution_target',w.execution_target,
    'resolution_note',w.resolution_note,'completion_verification',w.completion_verification,
    'recommendation_snapshot',w.recommendation_snapshot,
    'decided_at',w.decided_at,'execution_started_at',w.execution_started_at,
    'completed_at',w.completed_at,'updated_at',w.updated_at
  ) order by w.updated_at desc),'[]'::jsonb)
  into v_history
  from (
    select *
    from private.coach_action_workspace_v95
    where actor_id=p_actor_id
    order by updated_at desc
    limit 100
  ) w;

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
    'version','COACH_ACTION_WORKSPACE_V95_TENANT',
    'actor_id',p_actor_id,'current',v_current,'history',v_history,
    'summary',coalesce(v_summary,'{}'::jsonb),
    'guardrails',jsonb_build_object(
      'tenant_scoped',true,'human_decision_required',true,
      'auto_publish',false,'auto_program_edit',false,'auto_message',false,
      'auto_billing_mutation',false,'execution_is_handoff_only',true,
      'completion_is_coach_reported',true,'source_of_truth','V94_COACH_AI_TENANT'
    )
  );
end;
$function$;

create or replace function public.start_coach_action_v95(
  p_actor_id uuid,p_workspace_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_row private.coach_action_workspace_v95%rowtype;
begin
  if auth.uid() is null or p_actor_id is null or auth.uid()<>p_actor_id then
    raise exception 'Authenticated actor mismatch';
  end if;

  select * into v_row
  from private.coach_action_workspace_v95
  where id=p_workspace_id and actor_id=p_actor_id
  for update;

  if v_row.id is null then raise exception 'Workspace action not found'; end if;
  if not (
    private.is_org_admin(v_row.organization_id)
    or private.actor_can_manage_client_in_org_v1(
      p_actor_id,v_row.organization_id,v_row.client_id
    )
  ) then raise exception 'Client outside coach scope in organization'; end if;

  if v_row.decision not in ('ACCEPTED','MODIFIED')
     or v_row.workflow_status not in ('READY','EXECUTING') then
    raise exception 'Action must be accepted or modified before execution';
  end if;

  update private.coach_action_workspace_v95
  set workflow_status='EXECUTING',
      execution_started_at=coalesce(execution_started_at,now()),
      updated_at=now()
  where id=v_row.id and organization_id=v_row.organization_id;

  return jsonb_build_object(
    'ok',true,'organization_id',v_row.organization_id,
    'workspace_id',v_row.id,'client_id',v_row.client_id,
    'workflow_status','EXECUTING','execution_target',v_row.execution_target,
    'effective_action_code',v_row.effective_action_code,
    'effective_action',v_row.effective_action,
    'handoff_only',true,'side_effect_executed',false,
    'coach_must_execute_in_target_module',true
  );
end;
$function$;

create or replace function public.complete_coach_action_v95(
  p_actor_id uuid,p_workspace_id uuid,p_resolution_note text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_row private.coach_action_workspace_v95%rowtype;
begin
  if auth.uid() is null or p_actor_id is null or auth.uid()<>p_actor_id then
    raise exception 'Authenticated actor mismatch';
  end if;
  if nullif(btrim(coalesce(p_resolution_note,'')),'') is null then
    raise exception 'Resolution note required';
  end if;

  select * into v_row
  from private.coach_action_workspace_v95
  where id=p_workspace_id and actor_id=p_actor_id
  for update;

  if v_row.id is null then raise exception 'Workspace action not found'; end if;
  if not (
    private.is_org_admin(v_row.organization_id)
    or private.actor_can_manage_client_in_org_v1(
      p_actor_id,v_row.organization_id,v_row.client_id
    )
  ) then raise exception 'Client outside coach scope in organization'; end if;

  if v_row.workflow_status not in ('READY','EXECUTING') then
    raise exception 'Action is not executable';
  end if;

  update private.coach_action_workspace_v95
  set workflow_status='COMPLETED',
      resolution_note=btrim(p_resolution_note),
      completion_verification='coach_reported',
      completed_at=now(),
      updated_at=now()
  where id=v_row.id and organization_id=v_row.organization_id;

  return jsonb_build_object(
    'ok',true,'organization_id',v_row.organization_id,
    'workspace_id',v_row.id,'workflow_status','COMPLETED',
    'completion_verification','coach_reported',
    'underlying_side_effect_verified',false,
    'auto_publish',false,'auto_program_edit',false
  );
end;
$function$;

-- Outcome computation is redefined later in this migration after the public V97 command center
-- so it can read current Organization-specific recommendations.

create or replace function public.reconcile_due_coach_action_outcomes_v96(
  p_actor_id uuid,p_limit integer default 50
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_role public.app_role;
  v_row record;
  v_processed integer:=0;
  v_result jsonb;
begin
  if auth.uid() is null or p_actor_id is null or auth.uid()<>p_actor_id then
    raise exception 'Authenticated actor mismatch';
  end if;
  select p.role into v_role
  from public.profiles p
  where p.id=p_actor_id and p.status='active'::public.profile_status;
  if v_role is null or v_role not in ('admin'::public.app_role,'coach'::public.app_role) then
    raise exception 'Coach/admin required';
  end if;

  for v_row in
    with latest as (
      select distinct on (e.organization_id,e.workspace_id)
        e.organization_id,e.workspace_id,e.next_check_after,e.assessed_at
      from private.coach_action_outcome_events_v96 e
      where e.actor_id=p_actor_id
      order by e.organization_id,e.workspace_id,e.assessed_at desc,e.id desc
    )
    select w.organization_id,w.id
    from private.coach_action_workspace_v95 w
    left join latest l
      on l.organization_id=w.organization_id
     and l.workspace_id=w.id
    where w.actor_id=p_actor_id
      and w.workflow_status='COMPLETED'
      and (
        private.is_org_admin(w.organization_id)
        or private.actor_can_manage_client_in_org_v1(
          p_actor_id,w.organization_id,w.client_id
        )
      )
      and (l.workspace_id is null or l.next_check_after<=now())
    order by coalesce(l.next_check_after,w.completed_at) asc nulls first
    limit greatest(1,least(coalesce(p_limit,50),100))
  loop
    v_result:=public.reconcile_coach_action_outcome_v96(p_actor_id,v_row.id);
    v_processed:=v_processed+1;
  end loop;

  return jsonb_build_object(
    'ok',true,'version','ACTION_OUTCOME_INTELLIGENCE_V96_1_TENANT',
    'processed',v_processed,'client_state_mutated',false,
    'training_data_mutated',false,'program_data_mutated',false,
    'billing_data_mutated',false
  );
end;
$function$;

comment on table private.coach_action_workspace_v95 is
  'F1.M1.S5 H3B2: coach action workspace identity is Organization + actor + recommendation.';
comment on table private.coach_action_outcome_events_v96 is
  'F1.M1.S5 H3B2: outcome evidence is isolated by Organization.';
