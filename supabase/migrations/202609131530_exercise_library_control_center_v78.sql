-- CV Coach V78 — Exercise Library Control Center
-- QA persistido + activación/desactivación protegida por backend.

create table if not exists public.exercise_library_reviews (
  exercise_id uuid primary key references public.exercises(id) on delete cascade,
  qa_status text not null default 'pending' check (qa_status in ('pending','approved','blocked')),
  qa_notes text null check (qa_notes is null or char_length(qa_notes) <= 1000),
  reviewed_by uuid null references public.profiles(id),
  reviewed_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.exercise_library_reviews enable row level security;

drop policy if exists exercise_library_reviews_read_staff on public.exercise_library_reviews;
create policy exercise_library_reviews_read_staff
on public.exercise_library_reviews for select to authenticated
using (exists (
  select 1 from public.profiles p
  where p.id = auth.uid()
    and p.role in ('admin'::public.app_role,'coach'::public.app_role)
));

revoke insert, update, delete on public.exercise_library_reviews from anon, authenticated;
grant select on public.exercise_library_reviews to authenticated;

insert into public.exercise_library_reviews (exercise_id, qa_status, qa_notes, reviewed_by, reviewed_at)
select e.id,
  case
    when e.slug in ('extension-triceps-unilateral-polea','prensa-horizontal','curl-femoral-unilateral-maquina') then 'blocked'
    when e.active then 'approved'
    else 'pending'
  end,
  case
    when e.slug = 'extension-triceps-unilateral-polea' then 'V77 QA: la imagen generada representa una extensión sobre cabeza y no la variante unilateral en polea prevista.'
    when e.slug = 'prensa-horizontal' then 'V77 QA: la imagen generada representa una prensa inclinada/45° y no una prensa horizontal.'
    when e.slug = 'curl-femoral-unilateral-maquina' then 'V77 QA: la imagen generada representa extensión de rodilla y no flexión femoral unilateral.'
    when e.active then 'Baseline del catálogo activo previo a V78.'
    else null
  end,
  case when e.active or e.slug in ('extension-triceps-unilateral-polea','prensa-horizontal','curl-femoral-unilateral-maquina')
       then (select p.id from public.profiles p where p.role='admin'::public.app_role order by p.created_at limit 1)
       else null end,
  case when e.active or e.slug in ('extension-triceps-unilateral-polea','prensa-horizontal','curl-femoral-unilateral-maquina') then now() else null end
from public.exercises e
on conflict (exercise_id) do nothing;

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
    update public.exercise_library_reviews set qa_status='approved',qa_notes=v_note,reviewed_by=auth.uid(),reviewed_at=now(),updated_at=now() where exercise_id=p_exercise_id;
  elsif p_action='block' then
    if v_note is null then raise exception 'A blocking note is required'; end if;
    update public.exercise_library_reviews set qa_status='blocked',qa_notes=v_note,reviewed_by=auth.uid(),reviewed_at=now(),updated_at=now() where exercise_id=p_exercise_id;
    update public.exercises set active=false,updated_at=now() where id=p_exercise_id;
  elsif p_action='reset_qa' then
    update public.exercise_library_reviews set qa_status='pending',qa_notes=v_note,reviewed_by=null,reviewed_at=null,updated_at=now() where exercise_id=p_exercise_id;
    update public.exercises set active=false,updated_at=now() where id=p_exercise_id;
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
  return jsonb_build_object('exercise_id',v_exercise.id,'active',v_exercise.active,'qa_status',v_review.qa_status,'qa_notes',v_review.qa_notes,'reviewed_at',v_review.reviewed_at);
end;
$$;

revoke all on function public.manage_exercise_library_backend(uuid,uuid,text,text) from public;
grant execute on function public.manage_exercise_library_backend(uuid,uuid,text,text) to authenticated;

comment on table public.exercise_library_reviews is 'V78 staff QA state for the exercise library control center.';
comment on function public.manage_exercise_library_backend(uuid,uuid,text,text) is 'V78 admin-only guarded QA and activation lifecycle for exercises.';
