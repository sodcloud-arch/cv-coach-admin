-- CV Coach V60 — CV Rank System
-- Adds branded ranks over the existing monotonic CV12 level/XP engine.
-- Existing XP and levels 1-40 are preserved; only labels/classes are reclassified.

alter table public.cv_classes
  add column if not exists rank_key text,
  add column if not exists color_primary text,
  add column if not exists color_secondary text,
  add column if not exists tagline text,
  add column if not exists is_terminal boolean not null default false;

create unique index if not exists cv_classes_rank_key_uidx
  on public.cv_classes(rank_key)
  where rank_key is not null;

-- Reuse the five existing class identities so existing FK references remain valid.
update public.cv_classes
set name='BRONCE', min_level=1, max_level=4,
    description='El comienzo del proceso. Construye una base que puedas sostener.',
    rank_key='bronze', color_primary='#C47A3A', color_secondary='#6E351E',
    tagline='El primer paso también cuenta.', is_terminal=false
where order_index=1;

update public.cv_classes
set name='PLATA', min_level=5, max_level=9,
    description='La repetición empieza a convertirse en constancia.',
    rank_key='silver', color_primary='#D8E0E6', color_secondary='#71808A',
    tagline='La constancia empieza a notarse.', is_terminal=false
where order_index=2;

update public.cv_classes
set name='ORO', min_level=10, max_level=19,
    description='Hábitos sostenidos que ya producen resultados medibles.',
    rank_key='gold', color_primary='#F4B942', color_secondary='#8A5A12',
    tagline='Los hábitos generan resultados.', is_terminal=false
where order_index=3;

update public.cv_classes
set name='DIAMANTE', min_level=20, max_level=29,
    description='Disciplina aplicada con consistencia y progreso real.',
    rank_key='diamond', color_primary='#38BDF8', color_secondary='#DDF7FF',
    tagline='Disciplina en acción.', is_terminal=false
where order_index=4;

update public.cv_classes
set name='MAESTRO', min_level=30, max_level=39,
    description='Control sostenido de entrenamiento, nutrición y hábitos.',
    rank_key='master', color_primary='#A855F7', color_secondary='#5B21B6',
    tagline='Dominas tu proceso.', is_terminal=false
where order_index=5;

insert into public.cv_classes(id,name,order_index,min_level,max_level,description,badge_path,rank_key,color_primary,color_secondary,tagline,is_terminal)
select gen_random_uuid(),'GRAN MAESTRO',6,40,49,
       'Un estándar de ejecución excepcional mantenido en el tiempo.',null,
       'grandmaster','#FF283F','#7F0715','Inspiras con tu ejemplo.',false
where not exists(select 1 from public.cv_classes where order_index=6);

update public.cv_classes
set name='GRAN MAESTRO', min_level=40, max_level=49,
    description='Un estándar de ejecución excepcional mantenido en el tiempo.',
    rank_key='grandmaster', color_primary='#FF283F', color_secondary='#7F0715',
    tagline='Inspiras con tu ejemplo.', is_terminal=false
where order_index=6;

insert into public.cv_classes(id,name,order_index,min_level,max_level,description,badge_path,rank_key,color_primary,color_secondary,tagline,is_terminal)
select gen_random_uuid(),'LEYENDA',7,50,50,
       'El rango máximo de CV Coach: disciplina convertida en estilo de vida.',null,
       'legend','#F5F7FA','#FF2037','Más que un objetivo: un estilo de vida.',true
where not exists(select 1 from public.cv_classes where order_index=7);

update public.cv_classes
set name='LEYENDA', min_level=50, max_level=50,
    description='El rango máximo de CV Coach: disciplina convertida en estilo de vida.',
    rank_key='legend', color_primary='#F5F7FA', color_secondary='#FF2037',
    tagline='Más que un objetivo: un estilo de vida.', is_terminal=true
where order_index=7;

-- Keep the current level curve intact through level 40. Extend it monotonically to 50.
insert into public.cv_levels(level_number,class_id,xp_required_total,name,description,reward_xp,reward_credits)
select v.level_number,c.id,v.xp_required_total,'GRAN MAESTRO',
       'Perfeccionamiento de un estándar avanzado y sostenible.',0,0
from (values
  (41,21860),(42,23040),(43,24260),(44,25520),(45,26820),
  (46,28160),(47,29540),(48,30960),(49,32420)
) as v(level_number,xp_required_total)
join public.cv_classes c on c.rank_key='grandmaster'
on conflict(level_number) do nothing;

insert into public.cv_levels(level_number,class_id,xp_required_total,name,description,reward_xp,reward_credits)
select 50,c.id,33920,'LEYENDA',
       'Máximo rango del CV Rank System. Disciplina convertida en estilo de vida.',0,0
from public.cv_classes c where c.rank_key='legend'
on conflict(level_number) do nothing;

-- Reclassify every level to the approved rank scale without changing its XP threshold.
update public.cv_levels l
set class_id=c.id,
    name=c.name,
    description=c.description
from public.cv_classes c
where l.level_number between c.min_level and c.max_level
  and c.rank_key is not null;

create table if not exists public.client_rank_history(
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.profiles(id) on delete cascade,
  class_id uuid not null references public.cv_classes(id) on delete restrict,
  rank_key text not null,
  rank_name_snapshot text not null,
  level_number integer not null,
  reached_at timestamptz not null default now(),
  trigger_source text not null default 'system',
  created_at timestamptz not null default now(),
  unique(client_id,class_id)
);

alter table public.client_rank_history enable row level security;
grant select on public.client_rank_history to authenticated;

DROP POLICY IF EXISTS client_rank_history_select ON public.client_rank_history;
create policy client_rank_history_select on public.client_rank_history
for select to authenticated
using ((select private.can_view_client(client_rank_history.client_id)));

create or replace function private.track_cv_rank_from_level_history()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_rank public.cv_classes%rowtype;
  v_rank_history_id uuid;
begin
  select * into v_rank
  from public.cv_classes c
  where c.rank_key is not null
    and c.min_level=new.level_number
  order by c.order_index
  limit 1;

  if not found then return new; end if;

  insert into public.client_rank_history(
    client_id,class_id,rank_key,rank_name_snapshot,level_number,reached_at,trigger_source
  ) values(
    new.client_id,v_rank.id,v_rank.rank_key,v_rank.name,new.level_number,new.reached_at,new.trigger_source
  )
  on conflict(client_id,class_id) do nothing
  returning id into v_rank_history_id;

  if v_rank_history_id is not null and v_rank.order_index>1 then
    insert into public.notifications(user_id,type,title,body,action_url,metadata)
    values(
      new.client_id,
      'rank_up',
      '¡Nuevo rango!',
      'Alcanzaste Rango '||v_rank.name||'.',
      '/',
      jsonb_build_object(
        'rank_key',v_rank.rank_key,
        'rank_name',v_rank.name,
        'level_number',new.level_number,
        'rank_history_id',v_rank_history_id
      )
    );
  end if;

  return new;
end;
$function$;

DROP TRIGGER IF EXISTS trg_client_level_history_rank_v60 ON public.client_level_history;
create trigger trg_client_level_history_rank_v60
after insert on public.client_level_history
for each row execute function private.track_cv_rank_from_level_history();

-- Backfill rank history silently for levels already reached before V60.
insert into public.client_rank_history(
  client_id,class_id,rank_key,rank_name_snapshot,level_number,reached_at,trigger_source
)
select s.client_id,c.id,c.rank_key,c.name,c.min_level,
       coalesce((
         select min(h.reached_at)
         from public.client_level_history h
         where h.client_id=s.client_id and h.level_number>=c.min_level
       ),s.updated_at,now()),
       'v60_backfill'
from public.client_cv_state s
join public.cv_classes c on c.rank_key is not null and c.min_level<=s.current_level
on conflict(client_id,class_id) do nothing;

create or replace function public.get_client_rank_state_backend(
  p_actor_id uuid,
  p_client_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_actor_role text;
  v_client uuid;
  v_state public.client_cv_state%rowtype;
  v_rank public.cv_classes%rowtype;
  v_next_rank public.cv_classes%rowtype;
  v_level public.cv_levels%rowtype;
  v_next_level public.cv_levels%rowtype;
  v_rank_start_xp integer:=0;
  v_next_rank_xp integer;
  v_level_progress numeric:=100;
  v_rank_progress numeric:=100;
  v_pillars jsonb:='{}'::jsonb;
begin
  if p_actor_id is null then raise exception 'actor_id is required'; end if;
  if auth.uid() is not null and auth.uid()<>p_actor_id then raise exception 'actor mismatch'; end if;

  select p.role::text into v_actor_role
  from public.profiles p
  where p.id=p_actor_id and p.status::text='active';
  if v_actor_role is null then raise exception 'actor is not an active CV Coach user'; end if;

  v_client:=coalesce(p_client_id,p_actor_id);
  if p_actor_id<>v_client then
    if v_actor_role='admin' then null;
    elsif v_actor_role='coach' and exists(
      select 1 from public.coach_clients cc
      where cc.coach_id=p_actor_id and cc.client_id=v_client and cc.status::text='active'
    ) then null;
    else raise exception 'actor is not authorized for this client'; end if;
  elsif v_actor_role<>'client' then
    raise exception 'self rank state requires a client account or explicit client_id';
  end if;

  select * into v_state from public.client_cv_state s where s.client_id=v_client;
  if not found then
    return jsonb_build_object('client_id',v_client,'current_level',1,'total_xp',0,'rank',null);
  end if;

  select * into v_rank from public.cv_classes c
  where c.rank_key is not null and v_state.current_level between c.min_level and c.max_level
  order by c.order_index limit 1;

  select * into v_next_rank from public.cv_classes c
  where c.rank_key is not null and c.order_index>v_rank.order_index
  order by c.order_index limit 1;

  select * into v_level from public.cv_levels l where l.level_number=v_state.current_level;
  select * into v_next_level from public.cv_levels l where l.level_number=v_state.current_level+1;

  if v_next_level.level_number is not null then
    v_level_progress:=least(100,greatest(0,
      100.0*(v_state.total_xp-v_level.xp_required_total)::numeric /
      greatest(1,v_next_level.xp_required_total-v_level.xp_required_total)::numeric
    ));
  end if;

  select coalesce(l.xp_required_total,0) into v_rank_start_xp
  from public.cv_levels l where l.level_number=v_rank.min_level;

  if v_next_rank.id is not null then
    select l.xp_required_total into v_next_rank_xp
    from public.cv_levels l where l.level_number=v_next_rank.min_level;
    v_rank_progress:=least(100,greatest(0,
      100.0*(v_state.total_xp-v_rank_start_xp)::numeric /
      greatest(1,v_next_rank_xp-v_rank_start_xp)::numeric
    ));
  end if;

  select coalesce(jsonb_object_agg(x.pillar,x.amount),'{}'::jsonb) into v_pillars
  from (
    select coalesce(nullif(xl.pillar,''),'other') pillar,
           coalesce(sum(xl.amount) filter(where xl.reversed_at is null),0)::integer amount
    from public.xp_ledger xl
    where xl.client_id=v_client
    group by coalesce(nullif(xl.pillar,''),'other')
  ) x;

  return jsonb_build_object(
    'client_id',v_client,
    'current_level',v_state.current_level,
    'total_xp',v_state.total_xp,
    'credit_balance',v_state.credit_balance,
    'cv_score',v_state.current_cv_score,
    'dynamic_state',v_state.dynamic_state,
    'rank',jsonb_build_object(
      'key',v_rank.rank_key,'name',v_rank.name,'order',v_rank.order_index,
      'min_level',v_rank.min_level,'max_level',v_rank.max_level,
      'color_primary',v_rank.color_primary,'color_secondary',v_rank.color_secondary,
      'tagline',v_rank.tagline,'description',v_rank.description,'terminal',v_rank.is_terminal
    ),
    'next_rank',case when v_next_rank.id is null then null else jsonb_build_object(
      'key',v_next_rank.rank_key,'name',v_next_rank.name,'min_level',v_next_rank.min_level,
      'color_primary',v_next_rank.color_primary,'color_secondary',v_next_rank.color_secondary,
      'tagline',v_next_rank.tagline
    ) end,
    'level_start_xp',coalesce(v_level.xp_required_total,0),
    'next_level_xp',v_next_level.xp_required_total,
    'xp_to_next_level',case when v_next_level.level_number is null then 0 else greatest(0,v_next_level.xp_required_total-v_state.total_xp) end,
    'level_progress_pct',round(v_level_progress,1),
    'next_rank_xp',v_next_rank_xp,
    'xp_to_next_rank',case when v_next_rank.id is null then 0 else greatest(0,v_next_rank_xp-v_state.total_xp) end,
    'levels_to_next_rank',case when v_next_rank.id is null then 0 else greatest(0,v_next_rank.min_level-v_state.current_level) end,
    'rank_progress_pct',round(v_rank_progress,1),
    'pillar_xp',v_pillars,
    'rank_reached_at',(select rh.reached_at from public.client_rank_history rh where rh.client_id=v_client and rh.class_id=v_rank.id limit 1)
  );
end;
$function$;

grant execute on function public.get_client_rank_state_backend(uuid,uuid) to authenticated;

-- Stable rank history should remain monotonic and read-only to the client surface.
comment on table public.client_rank_history is 'V60 monotonic CV Rank history derived from verified level history.';
comment on function public.get_client_rank_state_backend(uuid,uuid) is 'V60 authorized rank/XP projection for client and coach UI.';
