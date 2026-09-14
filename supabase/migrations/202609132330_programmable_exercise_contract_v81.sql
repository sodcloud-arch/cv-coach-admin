-- CV Coach V81 — Programmable Exercise Contract
-- Convierte "activo + QA aprobado" en una invariante de base de datos.
-- Objetivo: impedir que IA, editor manual o futuras integraciones asignen ejercicios
-- bloqueados, pendientes o inactivos a programas, sin tocar rutinas existentes.

begin;

-- Todo ejercicio nuevo nace en staging/inactivo. La activación ocurre sólo después de QA.
alter table public.exercises alter column active set default false;

create or replace function private.is_exercise_programmable(p_exercise_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.exercises e
    join public.exercise_library_reviews r on r.exercise_id = e.id
    where e.id = p_exercise_id
      and e.active = true
      and r.qa_status = 'approved'
  );
$$;

revoke all on function private.is_exercise_programmable(uuid) from public, anon, authenticated;
grant execute on function private.is_exercise_programmable(uuid) to service_role;

comment on function private.is_exercise_programmable(uuid) is
  'V81 canonical programming gate: an exercise is programmable only when active and QA approved.';

create or replace function private.guard_exercise_active_state_v81()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.active = true then
    if not exists (
      select 1
      from public.exercise_library_reviews r
      where r.exercise_id = new.id
        and r.qa_status = 'approved'
    ) then
      raise exception 'QA approval required before exercise activation';
    end if;
  end if;

  if tg_op = 'UPDATE' then
    if old.active = true and new.active = false then
      if exists (
        select 1
        from public.program_exercises pe
        join public.program_days pd on pd.id = pe.program_day_id
        join public.programs pr on pr.id = pd.program_id
        where pe.exercise_id = new.id
          and pe.active = true
          and pr.status in ('draft'::public.program_status, 'active'::public.program_status)
      ) then
        raise exception 'Exercise is used by an active or draft program; replace it there before deactivation';
      end if;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_exercise_active_state_v81 on public.exercises;
create trigger trg_guard_exercise_active_state_v81
before insert or update of active on public.exercises
for each row execute function private.guard_exercise_active_state_v81();

comment on function private.guard_exercise_active_state_v81() is
  'V81 enforces QA-before-activation and protects exercises already used by draft/active programs.';

create or replace function private.guard_exercise_review_state_v81()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_exercise_id uuid;
begin
  if tg_op = 'DELETE' then
    v_exercise_id := old.exercise_id;
  else
    v_exercise_id := new.exercise_id;
  end if;

  if exists (
    select 1
    from public.exercises e
    where e.id = v_exercise_id
      and e.active = true
  ) then
    if tg_op = 'DELETE' then
      raise exception 'Deactivate exercise before removing QA approval';
    end if;
    if new.qa_status <> 'approved' then
      raise exception 'Deactivate exercise before removing QA approval';
    end if;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_exercise_review_state_v81 on public.exercise_library_reviews;
create trigger trg_guard_exercise_review_state_v81
before delete or update of qa_status on public.exercise_library_reviews
for each row execute function private.guard_exercise_review_state_v81();

comment on function private.guard_exercise_review_state_v81() is
  'V81 prevents an active exercise from losing/deleting QA approval before safe deactivation.';

create or replace function private.guard_program_exercise_programmable_v81()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(new.active, true) = true
     and not private.is_exercise_programmable(new.exercise_id) then
    raise exception 'Exercise is not programmable: active + QA approved required';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_program_exercise_programmable_v81 on public.program_exercises;
create trigger trg_program_exercise_programmable_v81
before insert or update of exercise_id, active on public.program_exercises
for each row execute function private.guard_program_exercise_programmable_v81();

comment on function private.guard_program_exercise_programmable_v81() is
  'V81 hard gate for every new/reactivated program assignment, independent of UI or AI source.';

-- V78 lifecycle updated for the V81 invariant: when blocking/resetting QA,
-- deactivate first (after the existing in-use check), then change QA state.
create or replace function public.manage_exercise_library_backend(
  p_actor_id uuid,
  p_exercise_id uuid,
  p_action text,
  p_note text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor_role public.app_role;
  v_exercise public.exercises%rowtype;
  v_review public.exercise_library_reviews%rowtype;
  v_note text := nullif(btrim(coalesce(p_note,'')), '');
  v_in_use boolean := false;
begin
  if auth.uid() is null or auth.uid() <> p_actor_id then raise exception 'Actor authentication mismatch'; end if;
  select role into v_actor_role from public.profiles where id = auth.uid();
  if v_actor_role is distinct from 'admin'::public.app_role then raise exception 'Admin role required'; end if;
  if p_action not in ('approve_qa','block','reset_qa','activate','deactivate') then raise exception 'Unsupported action'; end if;

  select * into v_exercise from public.exercises where id = p_exercise_id for update;
  if not found then raise exception 'Exercise not found'; end if;
  insert into public.exercise_library_reviews(exercise_id) values (p_exercise_id) on conflict (exercise_id) do nothing;

  if p_action in ('block','reset_qa','deactivate') and v_exercise.active then
    select exists(
      select 1 from public.program_exercises pe
      join public.program_days pd on pd.id=pe.program_day_id
      join public.programs pr on pr.id=pd.program_id
      where pe.exercise_id=p_exercise_id and pe.active=true
        and pr.status in ('draft'::public.program_status,'active'::public.program_status)
    ) into v_in_use;
    if v_in_use then raise exception 'Exercise is used by an active or draft program; replace it there before deactivation'; end if;
  end if;

  if p_action='approve_qa' then
    update public.exercise_library_reviews
    set qa_status='approved',qa_notes=v_note,reviewed_by=auth.uid(),reviewed_at=now(),updated_at=now()
    where exercise_id=p_exercise_id;
  elsif p_action='block' then
    if v_note is null then raise exception 'A blocking note is required'; end if;
    update public.exercises set active=false,updated_at=now() where id=p_exercise_id;
    update public.exercise_library_reviews
    set qa_status='blocked',qa_notes=v_note,reviewed_by=auth.uid(),reviewed_at=now(),updated_at=now()
    where exercise_id=p_exercise_id;
  elsif p_action='reset_qa' then
    update public.exercises set active=false,updated_at=now() where id=p_exercise_id;
    update public.exercise_library_reviews
    set qa_status='pending',qa_notes=v_note,reviewed_by=null,reviewed_at=null,updated_at=now()
    where exercise_id=p_exercise_id;
  elsif p_action='deactivate' then
    update public.exercises set active=false,updated_at=now() where id=p_exercise_id;
  elsif p_action='activate' then
    select * into v_review from public.exercise_library_reviews where exercise_id=p_exercise_id;
    if v_review.qa_status is distinct from 'approved' then raise exception 'QA approval required before activation'; end if;
    if nullif(btrim(v_exercise.name),'') is null
      or nullif(btrim(v_exercise.slug),'') is null
      or nullif(btrim(coalesce(v_exercise.primary_muscle,'')),'') is null
      or nullif(btrim(coalesce(v_exercise.equipment,'')),'') is null
      or nullif(btrim(coalesce(v_exercise.movement_pattern,'')),'') is null
      or v_exercise.difficulty is null
      or nullif(btrim(coalesce(v_exercise.instructions,'')),'') is null
      or nullif(btrim(coalesce(v_exercise.default_tempo,'')),'') is null
      or v_exercise.default_rest_sec is null
      or nullif(btrim(coalesce(v_exercise.image_path,'')),'') is null
      or v_exercise.prescription_unit not in ('reps','seconds')
    then raise exception 'Exercise metadata is incomplete'; end if;
    update public.exercises set active=true,updated_at=now() where id=p_exercise_id;
  end if;

  select * into v_exercise from public.exercises where id=p_exercise_id;
  select * into v_review from public.exercise_library_reviews where exercise_id=p_exercise_id;
  return jsonb_build_object(
    'exercise_id',v_exercise.id,
    'active',v_exercise.active,
    'qa_status',v_review.qa_status,
    'qa_notes',v_review.qa_notes,
    'reviewed_at',v_review.reviewed_at,
    'programmable',private.is_exercise_programmable(v_exercise.id)
  );
end;
$$;

revoke all on function public.manage_exercise_library_backend(uuid,uuid,text,text) from public;
grant execute on function public.manage_exercise_library_backend(uuid,uuid,text,text) to authenticated;

-- Migration-time assertions. V81 must not silently legitimize legacy drift.
do $$
begin
  if exists (
    select 1
    from public.exercises e
    left join public.exercise_library_reviews r on r.exercise_id=e.id
    where e.active=true
      and coalesce(r.qa_status,'') <> 'approved'
  ) then
    raise exception 'V81 invariant failed: active exercise without approved QA';
  end if;

  if exists (
    select 1
    from public.program_exercises pe
    join public.program_days pd on pd.id=pe.program_day_id
    join public.programs pr on pr.id=pd.program_id
    where pe.active=true
      and pr.status in ('draft'::public.program_status,'active'::public.program_status)
      and not private.is_exercise_programmable(pe.exercise_id)
  ) then
    raise exception 'V81 invariant failed: draft/active program contains a non-programmable exercise';
  end if;
end;
$$;

comment on function public.manage_exercise_library_backend(uuid,uuid,text,text) is
  'V81 guarded exercise-library lifecycle: staging by default, QA before activation, in-use protection and programmable-state receipt.';

commit;
