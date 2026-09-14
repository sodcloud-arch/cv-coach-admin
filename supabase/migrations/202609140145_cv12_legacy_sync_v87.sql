-- CV Coach V87 — CV12 Legacy Sync Bridge + native cutover preparation

create table if not exists public.legacy_cv12_sessions_v87 (
  id uuid primary key default gen_random_uuid(),
  pilot_id uuid not null references public.coach_intelligence_pilots(id) on delete cascade,
  source_row_key text not null,
  completed_at timestamptz not null,
  week_start date null,
  day_label text null,
  title text null,
  difficulty numeric null,
  final_observation text null,
  state text null,
  counted boolean null,
  level integer null,
  rank_name text null,
  class_name text null,
  training_progress text null,
  nutrition_progress text null,
  walk_progress text null,
  leveled_up boolean null,
  reward text null,
  raw jsonb not null default '{}'::jsonb,
  source_revision text null,
  ingested_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(pilot_id, source_row_key)
);

create table if not exists public.legacy_cv12_exercise_logs_v87 (
  id uuid primary key default gen_random_uuid(),
  pilot_id uuid not null references public.coach_intelligence_pilots(id) on delete cascade,
  source_row_key text not null,
  completed_at timestamptz not null,
  day_label text null,
  day_title text null,
  exercise_name text not null,
  exercise_id uuid null references public.exercises(id) on delete set null,
  mapping_status text not null default 'unmapped' check (mapping_status in ('linked','unmapped','ambiguous')),
  target_sets integer null,
  target_reps text null,
  weight_raw text null,
  series_values jsonb not null default '[]'::jsonb,
  difficulty numeric null,
  observation text null,
  raw jsonb not null default '{}'::jsonb,
  source_revision text null,
  ingested_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(pilot_id, source_row_key)
);

create table if not exists public.legacy_cv12_measurements_v87 (
  id uuid primary key default gen_random_uuid(),
  pilot_id uuid not null references public.coach_intelligence_pilots(id) on delete cascade,
  source_row_key text not null,
  measured_at timestamptz not null,
  body_weight numeric null,
  waist_cm numeric null,
  hip_cm numeric null,
  thigh_cm numeric null,
  energy numeric null,
  nutrition_adherence numeric null,
  comments text null,
  raw jsonb not null default '{}'::jsonb,
  source_revision text null,
  ingested_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(pilot_id, source_row_key)
);

create table if not exists public.legacy_cv12_exercise_aliases_v87 (
  id uuid primary key default gen_random_uuid(),
  legacy_name text not null unique,
  exercise_id uuid null references public.exercises(id) on delete set null,
  mapping_status text not null default 'unmapped' check (mapping_status in ('linked','unmapped','ambiguous')),
  confidence numeric null,
  note text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists legacy_cv12_sessions_v87_pilot_time_idx on public.legacy_cv12_sessions_v87(pilot_id, completed_at desc);
create index if not exists legacy_cv12_exercise_logs_v87_pilot_time_idx on public.legacy_cv12_exercise_logs_v87(pilot_id, completed_at desc);
create index if not exists legacy_cv12_exercise_logs_v87_exercise_idx on public.legacy_cv12_exercise_logs_v87(exercise_id, completed_at desc) where exercise_id is not null;

alter table public.legacy_cv12_sessions_v87 enable row level security;
alter table public.legacy_cv12_exercise_logs_v87 enable row level security;
alter table public.legacy_cv12_measurements_v87 enable row level security;
alter table public.legacy_cv12_exercise_aliases_v87 enable row level security;

-- Read access follows pilot ownership; writes are intentionally service/admin controlled during the bridge phase.
do $$ begin
  create policy legacy_cv12_sessions_v87_select on public.legacy_cv12_sessions_v87 for select to authenticated using (
    exists(select 1 from public.coach_intelligence_pilots p where p.id=pilot_id and (p.coach_id=auth.uid() or private.is_admin()))
  );
exception when duplicate_object then null; end $$;
do $$ begin
  create policy legacy_cv12_exercise_logs_v87_select on public.legacy_cv12_exercise_logs_v87 for select to authenticated using (
    exists(select 1 from public.coach_intelligence_pilots p where p.id=pilot_id and (p.coach_id=auth.uid() or private.is_admin()))
  );
exception when duplicate_object then null; end $$;
do $$ begin
  create policy legacy_cv12_measurements_v87_select on public.legacy_cv12_measurements_v87 for select to authenticated using (
    exists(select 1 from public.coach_intelligence_pilots p where p.id=pilot_id and (p.coach_id=auth.uid() or private.is_admin()))
  );
exception when duplicate_object then null; end $$;
do $$ begin
  create policy legacy_cv12_exercise_aliases_v87_select on public.legacy_cv12_exercise_aliases_v87 for select to authenticated using (private.is_admin() or exists(select 1 from public.profiles where id=auth.uid() and role in ('admin'::public.app_role,'coach'::public.app_role)));
exception when duplicate_object then null; end $$;

grant select on public.legacy_cv12_sessions_v87, public.legacy_cv12_exercise_logs_v87, public.legacy_cv12_measurements_v87, public.legacy_cv12_exercise_aliases_v87 to authenticated;

create or replace function public.refresh_cv12_pilot_baseline_v87(p_pilot_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_sessions integer;
  v_evidence integer;
  v_last timestamptz;
  v_first timestamptz;
  v_status text;
begin
  select count(*), min(completed_at), max(completed_at)
    into v_sessions, v_first, v_last
  from public.legacy_cv12_sessions_v87 where pilot_id=p_pilot_id;

  select count(*) into v_evidence
  from (
    select coalesce(exercise_id::text, lower(exercise_name)) k
    from public.legacy_cv12_exercise_logs_v87
    where pilot_id=p_pilot_id
    group by coalesce(exercise_id::text, lower(exercise_name))
    having count(distinct completed_at)>=2
  ) q;

  v_status := case when v_sessions>=3 and v_evidence>=2 then 'ready_observed' else 'collecting_baseline' end;

  update public.coach_intelligence_pilots p
  set status=v_status,
      baseline_snapshot=coalesce(p.baseline_snapshot,'{}'::jsonb) || jsonb_build_object(
        'sessions_completed',v_sessions,
        'evidence_exercises',v_evidence,
        'first_completed_session_at',v_first,
        'last_completed_session_at',v_last,
        'v87_last_refresh_at',now(),
        'v87_sync_state',case when v_sessions>0 then 'synced' else 'empty' end,
        'auto_publish',false,
        'auto_program_edit',false
      ),
      updated_at=now()
  where p.id=p_pilot_id;

  return jsonb_build_object(
    'engine_version','CV12_LEGACY_SYNC_V87',
    'pilot_id',p_pilot_id,
    'sessions_completed',v_sessions,
    'evidence_exercises',v_evidence,
    'first_completed_session_at',v_first,
    'last_completed_session_at',v_last,
    'status',v_status,
    'ready_for_v85',(v_sessions>=3 and v_evidence>=2),
    'guardrails',jsonb_build_object('auto_publish',false,'auto_program_edit',false,'legacy_source_preserved',true)
  );
end;
$function$;

create or replace function public.get_cv12_native_cutover_plan_v87(p_pilot_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  p public.coach_intelligence_pilots%rowtype;
  v_sessions integer;
  v_logs integer;
  v_unmapped integer;
  v_measurements integer;
  v_blockers jsonb := '[]'::jsonb;
begin
  select * into p from public.coach_intelligence_pilots where id=p_pilot_id;
  if p.id is null then raise exception 'Pilot not found'; end if;

  select count(*) into v_sessions from public.legacy_cv12_sessions_v87 where pilot_id=p_pilot_id;
  select count(*) into v_logs from public.legacy_cv12_exercise_logs_v87 where pilot_id=p_pilot_id;
  select count(*) into v_unmapped from public.legacy_cv12_exercise_logs_v87 where pilot_id=p_pilot_id and mapping_status<>'linked';
  select count(*) into v_measurements from public.legacy_cv12_measurements_v87 where pilot_id=p_pilot_id;

  if p.client_id is null then v_blockers:=v_blockers||jsonb_build_array('native_auth_identity_required'); end if;
  if v_sessions=0 then v_blockers:=v_blockers||jsonb_build_array('legacy_history_not_synced'); end if;

  return jsonb_build_object(
    'engine_version','CV12_NATIVE_CUTOVER_V87',
    'pilot_id',p.id,
    'subject_label',p.subject_label,
    'source_system',p.source_system,
    'client_id',p.client_id,
    'sessions',v_sessions,
    'exercise_logs',v_logs,
    'unmapped_exercise_logs',v_unmapped,
    'measurements',v_measurements,
    'ai_ready',p.status in ('ready_observed','active_observed','linked'),
    'migration_ready',(p.client_id is not null and v_sessions>0),
    'blockers',v_blockers,
    'next_action',case when p.client_id is null then 'Create or identify the real native auth user, then link this pilot. Never create a synthetic identity.' when v_sessions=0 then 'Sync legacy history before cutover.' else 'Native cutover can proceed with legacy history preserved.' end,
    'guardrails',jsonb_build_object('preserve_legacy_rows',true,'auto_publish',false,'auto_program_edit',false)
  );
end;
$function$;

create or replace function public.link_cv12_pilot_native_v87(p_pilot_id uuid,p_client_id uuid,p_actor_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_role public.app_role;
  v_name text;
begin
  if auth.uid() is null or auth.uid()<>p_actor_id then raise exception 'Actor authentication mismatch'; end if;
  select role into v_role from public.profiles where id=p_actor_id and status='active'::public.profile_status;
  if v_role is null or v_role not in ('admin'::public.app_role,'coach'::public.app_role) then raise exception 'Coach/admin required'; end if;
  select concat_ws(' ',first_name,last_name) into v_name from public.profiles where id=p_client_id and role='client'::public.app_role and status='active'::public.profile_status;
  if v_name is null then raise exception 'Native active client profile required'; end if;
  update public.coach_intelligence_pilots set client_id=p_client_id, linked_at=now(), status='linked', updated_at=now() where id=p_pilot_id;
  if not found then raise exception 'Pilot not found'; end if;
  return jsonb_build_object('ok',true,'pilot_id',p_pilot_id,'client_id',p_client_id,'client_name',v_name,'legacy_history_preserved',true,'auto_publish',false);
end;
$function$;

grant execute on function public.refresh_cv12_pilot_baseline_v87(uuid) to authenticated;
grant execute on function public.get_cv12_native_cutover_plan_v87(uuid) to authenticated;
grant execute on function public.link_cv12_pilot_native_v87(uuid,uuid,uuid) to authenticated;

-- Safe, explicit alias seeds for Charlotte's current CV12 history. Ambiguous/absent movements remain unmapped by design.
insert into public.legacy_cv12_exercise_aliases_v87(legacy_name,exercise_id,mapping_status,confidence,note)
select v.legacy_name,e.id,v.mapping_status,v.confidence,v.note
from (values
  ('Hip thrust con barra','hip-thrust','linked',1.0,'Canonical V81 active/approved exercise'),
  ('Sentadilla goblet','sentadilla-goblet','linked',1.0,'Direct semantic match'),
  ('Patada de glúteo en polea','patada-gluteo-polea','linked',1.0,'Direct semantic match'),
  ('Plancha frontal','plancha-frontal','linked',1.0,'Direct semantic match'),
  ('Remo con mancuerna en banco','remo-mancuerna-unilateral','linked',0.95,'Legacy bench-supported unilateral row maps to one-arm dumbbell row'),
  ('Jalón en polea al pecho','jalon-al-pecho','linked',0.98,'Direct movement match'),
  ('Extensión de tríceps en polea','triceps-polea','linked',0.90,'Legacy generic cable extension maps to rope extension'),
  ('Caminadora inclinada','caminata-cinta','linked',0.95,'Incline treadmill cardio'),
  ('Caminadora ritmo moderado','caminata-cinta','linked',0.90,'Moderate treadmill cardio')
) as v(legacy_name,slug,mapping_status,confidence,note)
join public.exercises e on e.slug=v.slug and e.active=true
on conflict (legacy_name) do update set exercise_id=excluded.exercise_id,mapping_status=excluded.mapping_status,confidence=excluded.confidence,note=excluded.note,updated_at=now();

comment on table public.legacy_cv12_sessions_v87 is 'V87 immutable/idempotent staging history from CV12 legacy spreadsheets.';
comment on function public.get_cv12_native_cutover_plan_v87(uuid) is 'V87 cutover readiness. Requires a real native auth/client identity; never synthesizes one.';
