-- CV Coach V75 · historical workout duration consistency
-- Repairs only terminal sessions that already have authoritative start/finish timestamps.
-- No duration is guessed: it is derived from persisted timestamps.

update public.workout_sessions
set duration_seconds = greatest(
  0,
  extract(epoch from (finished_at - started_at))::integer
),
updated_at = now()
where status::text in ('completed','partial','abandoned')
  and duration_seconds is null
  and started_at is not null
  and finished_at is not null;

do $$
begin
  if exists (
    select 1
    from public.workout_sessions
    where status::text in ('completed','partial','abandoned')
      and duration_seconds is null
      and started_at is not null
      and finished_at is not null
  ) then
    raise exception 'CV Coach V75 duration backfill incomplete';
  end if;
end
$$;
