-- CV Coach V66 — one-shot cinematic rank transition delivery
-- Adds a receipt layer over the immutable V61 transition ledger so Level Up /
-- Rank Up celebrations can be shown exactly once per client across devices.

create table if not exists public.cv_rank_transition_receipts_v66(
  transition_id uuid primary key references public.cv_rank_transitions_v61(id) on delete cascade,
  client_id uuid not null references public.profiles(id) on delete cascade,
  seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique(client_id, transition_id)
);

create index if not exists cv_rank_transition_receipts_v66_client_idx
  on public.cv_rank_transition_receipts_v66(client_id, seen_at desc);

alter table public.cv_rank_transition_receipts_v66 enable row level security;
revoke all on public.cv_rank_transition_receipts_v66 from anon, authenticated;

create or replace function public.get_pending_rank_transition_v66(p_actor_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_role text;
  v_status text;
  v_t public.cv_rank_transitions_v61%rowtype;
  v_from public.cv_rank_rules_v61%rowtype;
  v_to public.cv_rank_rules_v61%rowtype;
begin
  if p_actor_id is null then raise exception 'actor_id is required'; end if;
  if auth.uid() is not null and auth.uid()<>p_actor_id then raise exception 'actor mismatch'; end if;

  select p.role::text,p.status::text into v_role,v_status
  from public.profiles p where p.id=p_actor_id;
  if v_role is distinct from 'client' or v_status is distinct from 'active' then
    raise exception 'active client required';
  end if;

  select t.* into v_t
  from public.cv_rank_transitions_v61 t
  where t.client_id=p_actor_id
    and t.direction in ('level_up','rank_up','legend_unlock')
    and t.created_at>=now()-interval '90 days'
    and not exists(
      select 1 from public.cv_rank_transition_receipts_v66 r
      where r.transition_id=t.id and r.client_id=p_actor_id
    )
  order by t.created_at asc
  limit 1;

  if not found then return jsonb_build_object('pending',false); end if;

  select * into v_from from public.cv_rank_rules_v61 where rank_key=v_t.from_rank_key;
  select * into v_to from public.cv_rank_rules_v61 where rank_key=v_t.to_rank_key;

  return jsonb_build_object(
    'pending',true,
    'transition_id',v_t.id,
    'direction',v_t.direction,
    'from_level',v_t.from_level,
    'to_level',v_t.to_level,
    'week_start',v_t.week_start,
    'created_at',v_t.created_at,
    'metadata',coalesce(v_t.metadata,'{}'::jsonb),
    'from_rank',case when v_from.rank_key is null then null else jsonb_build_object(
      'rank_key',v_from.rank_key,'rank_name',v_from.rank_name,'color_primary',v_from.color_primary,
      'color_secondary',v_from.color_secondary,'badge_path',v_from.badge_path,'tagline',v_from.tagline
    ) end,
    'to_rank',case when v_to.rank_key is null then null else jsonb_build_object(
      'rank_key',v_to.rank_key,'rank_name',v_to.rank_name,'color_primary',v_to.color_primary,
      'color_secondary',v_to.color_secondary,'badge_path',v_to.badge_path,'tagline',v_to.tagline
    ) end
  );
end;
$function$;

create or replace function public.ack_rank_transition_v66(p_actor_id uuid,p_transition_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_role text;
  v_status text;
begin
  if p_actor_id is null or p_transition_id is null then raise exception 'actor_id and transition_id are required'; end if;
  if auth.uid() is not null and auth.uid()<>p_actor_id then raise exception 'actor mismatch'; end if;

  select p.role::text,p.status::text into v_role,v_status
  from public.profiles p where p.id=p_actor_id;
  if v_role is distinct from 'client' or v_status is distinct from 'active' then
    raise exception 'active client required';
  end if;
  if not exists(select 1 from public.cv_rank_transitions_v61 t where t.id=p_transition_id and t.client_id=p_actor_id) then
    raise exception 'transition not found for actor';
  end if;

  insert into public.cv_rank_transition_receipts_v66(transition_id,client_id)
  values(p_transition_id,p_actor_id)
  on conflict(transition_id) do nothing;

  return jsonb_build_object('ok',true,'transition_id',p_transition_id);
end;
$function$;

grant execute on function public.get_pending_rank_transition_v66(uuid) to authenticated;
grant execute on function public.ack_rank_transition_v66(uuid,uuid) to authenticated;

comment on table public.cv_rank_transition_receipts_v66 is 'V66 one-shot delivery receipts for cinematic client rank transitions.';
comment on function public.get_pending_rank_transition_v66(uuid) is 'Returns the oldest unseen upward V61 transition for the authenticated client.';
comment on function public.ack_rank_transition_v66(uuid,uuid) is 'Acknowledges a cinematic rank transition after the client explicitly continues.';
