-- CV Coach V80 — Exercise Library E2E canary program
-- Reuses the dedicated QA client's unused draft program instead of creating extra client versions.
-- The previous active DEMO program is archived (not deleted), preserving history.
-- Safe no-op on environments without the configured production canary client.

do $$
declare
  v_client_id uuid;
  v_coach_id uuid;
  v_program_id uuid;
  v_day_id uuid;
  v_initializing boolean := false;
begin
  select client_id into v_client_id
  from public.cv_canary_clients
  where label='production-v76' and enabled=true
  limit 1;

  if v_client_id is null then
    raise notice 'V80 canary client not configured; skipping QA program seed';
    return;
  end if;

  select id into v_coach_id
  from public.profiles
  where role='admin'::public.app_role and status='active'
  order by created_at
  limit 1;

  if v_coach_id is null then
    raise exception 'V80 requires one active admin coach';
  end if;

  select id into v_program_id
  from public.programs
  where client_id=v_client_id and name='CANARY — V80 Biblioteca E2E'
  order by version desc
  limit 1;

  if v_program_id is null then
    select p.id into v_program_id
    from public.programs p
    where p.client_id=v_client_id
      and p.status='draft'::public.program_status
      and not exists(select 1 from public.workout_sessions ws where ws.program_id=p.id)
    order by p.version desc
    limit 1;
    v_initializing := v_program_id is not null;
  end if;

  if v_program_id is null then
    raise exception 'V80 requires an unused canary draft program to preserve client version constraints';
  end if;

  if v_initializing then
    delete from public.program_days where program_id=v_program_id;
  end if;

  update public.programs
     set coach_id=v_coach_id,
         name='CANARY — V80 Biblioteca E2E',
         goal='QA automatizado: biblioteca, técnica y persistencia',
         updated_at=now()
   where id=v_program_id;

  select id into v_day_id
  from public.program_days
  where program_id=v_program_id and day_number=1;

  if v_day_id is null then
    insert into public.program_days(program_id,day_number,name,focus,estimated_minutes,notes)
    values(v_program_id,1,'V80 — Biblioteca E2E','QA · piernas · pecho · espalda · core',30,'Rutina técnica dedicada exclusivamente al canary de producción.')
    returning id into v_day_id;
  else
    update public.program_days
       set name='V80 — Biblioteca E2E',
           focus='QA · piernas · pecho · espalda · core',
           estimated_minutes=30,
           notes='Rutina técnica dedicada exclusivamente al canary de producción.',
           updated_at=now()
     where id=v_day_id;
  end if;

  if (select count(*) from public.exercises where active=true and slug in ('hack-squat','press-banca-barra','jalon-pecho-neutro','pallof-press','dead-bug')) <> 5 then
    raise exception 'V80 representative exercise set is incomplete or inactive';
  end if;

  insert into public.program_exercises(program_day_id,exercise_id,exercise_order,target_sets,rep_min,rep_max,rir_target,tempo,rest_seconds,load_strategy,coach_notes,allow_substitution,active,prescription_unit)
  select v_day_id,e.id,v.exercise_order,v.target_sets,v.rep_min,v.rep_max,v.rir_target,v.tempo,v.rest_seconds,'fixed','V80 E2E · ejercicio representativo de biblioteca',false,true,e.prescription_unit
  from (values
    ('hack-squat',1,2,8,10,2.0::numeric,'3-1-1-0',120),
    ('press-banca-barra',2,2,8,10,2.0::numeric,'3-1-1-0',150),
    ('jalon-pecho-neutro',3,2,10,12,2.0::numeric,'2-1-3-0',90),
    ('pallof-press',4,2,10,12,2.0::numeric,'2-1-2-1',45),
    ('dead-bug',5,2,8,10,2.0::numeric,'2-1-2-0',45)
  ) as v(slug,exercise_order,target_sets,rep_min,rep_max,rir_target,tempo,rest_seconds)
  join public.exercises e on e.slug=v.slug and e.active=true
  on conflict (program_day_id,exercise_order) do update
    set exercise_id=excluded.exercise_id,
        target_sets=excluded.target_sets,
        rep_min=excluded.rep_min,
        rep_max=excluded.rep_max,
        rir_target=excluded.rir_target,
        tempo=excluded.tempo,
        rest_seconds=excluded.rest_seconds,
        load_strategy=excluded.load_strategy,
        coach_notes=excluded.coach_notes,
        allow_substitution=excluded.allow_substitution,
        active=true,
        prescription_unit=excluded.prescription_unit,
        updated_at=now();

  update public.program_exercises
     set active=false, updated_at=now()
   where program_day_id=v_day_id and exercise_order > 5;

  update public.programs
     set status='archived'::public.program_status,
         updated_at=now()
   where client_id=v_client_id
     and status='active'::public.program_status
     and id<>v_program_id;

  update public.programs
     set status='active'::public.program_status,
         published_at=coalesce(published_at,now()),
         updated_at=now()
   where id=v_program_id;
end $$;
