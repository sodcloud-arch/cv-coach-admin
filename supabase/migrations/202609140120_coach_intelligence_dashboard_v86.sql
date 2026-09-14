-- CV Coach V86 — Coach Intelligence Dashboard + observed pilot registry

create table if not exists public.coach_intelligence_pilots (
  id uuid primary key default gen_random_uuid(),
  coach_id uuid not null references public.profiles(id) on delete cascade,
  client_id uuid null references public.profiles(id) on delete set null,
  subject_label text not null,
  source_system text not null,
  source_external_id text null,
  mode text not null default 'observed_only',
  status text not null default 'collecting_baseline',
  engine_version text not null default 'V86_COACH_INTELLIGENCE',
  baseline_snapshot jsonb not null default '{}'::jsonb,
  started_at timestamptz not null default now(),
  linked_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint coach_intelligence_pilots_mode_check check (mode in ('observed_only')),
  constraint coach_intelligence_pilots_status_check check (status in ('collecting_baseline','ready_observed','active_observed','paused','completed','linked')),
  constraint coach_intelligence_pilots_source_check check (source_system in ('native','cv12_legacy'))
);

create unique index if not exists coach_intelligence_pilots_external_uniq
  on public.coach_intelligence_pilots(coach_id,source_system,source_external_id)
  where source_external_id is not null;
create index if not exists coach_intelligence_pilots_coach_status_idx
  on public.coach_intelligence_pilots(coach_id,status,updated_at desc);

alter table public.coach_intelligence_pilots enable row level security;

drop policy if exists coach_intelligence_pilots_select on public.coach_intelligence_pilots;
create policy coach_intelligence_pilots_select on public.coach_intelligence_pilots
for select to authenticated
using (coach_id=auth.uid() or private.is_admin());

drop policy if exists coach_intelligence_pilots_insert on public.coach_intelligence_pilots;
create policy coach_intelligence_pilots_insert on public.coach_intelligence_pilots
for insert to authenticated
with check (coach_id=auth.uid() or private.is_admin());

drop policy if exists coach_intelligence_pilots_update on public.coach_intelligence_pilots;
create policy coach_intelligence_pilots_update on public.coach_intelligence_pilots
for update to authenticated
using (coach_id=auth.uid() or private.is_admin())
with check (coach_id=auth.uid() or private.is_admin());

grant select,insert,update on public.coach_intelligence_pilots to authenticated;

create or replace function public.get_coach_intelligence_dashboard_v86(p_actor_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
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

  select coalesce(jsonb_agg(to_jsonb(q) order by q.attention_score desc,q.last_name,q.first_name),'[]'::jsonb)
  into v_attention
  from public.get_coach_attention_queue() q;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',a.id,
    'client_id',a.client_id,
    'client_name',concat_ws(' ',p.first_name,p.last_name),
    'alert_type',a.alert_type,
    'severity',a.severity::text,
    'title',a.title,
    'message',a.message,
    'status',a.status::text,
    'created_at',a.created_at
  ) order by case a.severity::text when 'critical' then 0 when 'warning' then 1 else 2 end,a.created_at desc),'[]'::jsonb)
  into v_alerts
  from public.coach_alerts a
  join public.profiles p on p.id=a.client_id
  where a.status::text in ('open','acknowledged')
    and (v_role='admin'::public.app_role or a.coach_id=p_actor_id);

  select coalesce(jsonb_agg(jsonb_build_object(
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
      v_role='admin'::public.app_role
      or exists(select 1 from public.coach_clients cc where cc.coach_id=p_actor_id and cc.client_id=s.client_id and cc.status='active'::public.coach_client_status)
    );

  select coalesce(jsonb_agg(jsonb_build_object(
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
      v_role='admin'::public.app_role
      or exists(select 1 from public.coach_clients cc where cc.coach_id=p_actor_id and cc.client_id=r.client_id and cc.status='active'::public.coach_client_status)
    );

  select coalesce(jsonb_agg(jsonb_build_object(
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
        and coalesce((x.baseline_snapshot->>'evidence_exercises')::integer,0)>=2 then true
      else false end,
    'next_action',case
      when x.status='collecting_baseline' and coalesce((x.baseline_snapshot->>'sessions_completed')::integer,0)<3
        then 'Recolectar al menos 3 sesiones completadas antes de interpretar tendencia longitudinal.'
      when x.client_id is null then 'Mantener observación shadow hasta vincular una cuenta nativa de CV Coach.'
      else 'Revisar recomendaciones; ninguna decisión se aplica automáticamente.' end
  ) order by x.updated_at desc),'[]'::jsonb)
  into v_pilots
  from public.coach_intelligence_pilots x
  where x.coach_id=p_actor_id or v_role='admin'::public.app_role;

  select jsonb_build_object(
    'native_clients',count(*),
    'open_alerts',(select count(*) from jsonb_array_elements(v_alerts)),
    'pending_progressions',(select count(*) from jsonb_array_elements(v_progressions)),
    'deload_reviews',(select count(*) from jsonb_array_elements(v_adaptations) a where coalesce((a->>'deload_recommended')::boolean,false)),
    'active_pilots',(select count(*) from jsonb_array_elements(v_pilots) p where p->>'status' not in ('paused','completed')),
    'high_attention',(select count(*) from jsonb_array_elements(v_attention) q where q->>'priority' in ('CRITICAL','HIGH'))
  ) into v_summary
  from public.coach_clients cc
  where cc.status='active'::public.coach_client_status
    and (v_role='admin'::public.app_role or cc.coach_id=p_actor_id);

  return jsonb_build_object(
    'engine_version','COACH_INTELLIGENCE_V86',
    'generated_at',now(),
    'guardrails',jsonb_build_object(
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

grant execute on function public.get_coach_intelligence_dashboard_v86(uuid) to authenticated;

comment on table public.coach_intelligence_pilots is 'V86 observed-only pilot registry. Legacy subjects may be tracked without creating fake auth users.';
comment on function public.get_coach_intelligence_dashboard_v86(uuid) is 'V86 consolidated coach attention dashboard. Read-only intelligence; never edits programs or publishes.';
