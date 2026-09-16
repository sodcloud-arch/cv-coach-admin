create table if not exists public.push_preferences_v101 (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  enabled boolean not null default true,
  training_reminders boolean not null default true,
  program_updates boolean not null default true,
  progress_updates boolean not null default true,
  coach_updates boolean not null default true,
  system_updates boolean not null default true,
  quiet_hours_start time without time zone not null default time '21:00',
  quiet_hours_end time without time zone not null default time '08:00',
  timezone text not null default 'America/Santiago',
  workout_reminder_time time without time zone,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.push_subscriptions_v101 (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth_secret text not null,
  expiration_time bigint,
  user_agent text,
  device_label text,
  platform text,
  enabled boolean not null default true,
  last_seen_at timestamptz not null default now(),
  disabled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint push_subscription_endpoint_len_v101 check (char_length(endpoint) between 20 and 4096),
  constraint push_subscription_p256dh_len_v101 check (char_length(p256dh) between 40 and 512),
  constraint push_subscription_auth_len_v101 check (char_length(auth_secret) between 8 and 256)
);

create index if not exists idx_push_subscriptions_v101_user_active on public.push_subscriptions_v101(user_id,enabled);

alter table public.push_preferences_v101 enable row level security;
alter table public.push_subscriptions_v101 enable row level security;
revoke all on table public.push_preferences_v101 from anon, authenticated;
revoke all on table public.push_subscriptions_v101 from anon, authenticated;
grant select,insert,update,delete on table public.push_preferences_v101 to service_role;
grant select,insert,update,delete on table public.push_subscriptions_v101 to service_role;

create table if not exists private.push_dispatch_queue_v101 (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null unique references public.notifications(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  category text not null,
  status text not null default 'queued' check (status in ('queued','processing','sent','partial','failed','skipped')),
  attempts integer not null default 0 check (attempts between 0 and 20),
  next_attempt_at timestamptz not null default now(),
  locked_at timestamptz,
  sent_at timestamptz,
  skipped_reason text,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_push_dispatch_queue_v101_due on private.push_dispatch_queue_v101(status,next_attempt_at,created_at);
create index if not exists idx_push_dispatch_queue_v101_user on private.push_dispatch_queue_v101(user_id,created_at desc);

create table if not exists private.push_delivery_attempts_v101 (
  id uuid primary key default gen_random_uuid(),
  queue_id uuid not null references private.push_dispatch_queue_v101(id) on delete cascade,
  notification_id uuid not null references public.notifications(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  subscription_id uuid references public.push_subscriptions_v101(id) on delete set null,
  delivery_status text not null check (delivery_status in ('sent','failed','expired','skipped')),
  http_status integer,
  error_message text,
  created_at timestamptz not null default now()
);

create index if not exists idx_push_delivery_attempts_v101_notification on private.push_delivery_attempts_v101(notification_id,created_at desc);

create or replace function private.push_category_v101(p_type text)
returns text
language sql
immutable
set search_path=''
as $$
  select case lower(coalesce(p_type,''))
    when 'weekly_checkin_due' then 'training_reminders'
    when 'workout_reminder' then 'training_reminders'
    when 'program_published' then 'program_updates'
    when 'onboarding_approved' then 'program_updates'
    when 'onboarding_changes_requested' then 'coach_updates'
    when 'coach_message' then 'coach_updates'
    when 'adaptive_mission' then 'progress_updates'
    when 'mission_completed' then 'progress_updates'
    when 'achievement_unlocked' then 'progress_updates'
    when 'personal_record' then 'progress_updates'
    when 'level_up' then 'progress_updates'
    when 'rank_up' then 'progress_updates'
    when 'rank_down' then 'progress_updates'
    else 'system_updates'
  end;
$$;

create or replace function private.enqueue_notification_push_v101()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if coalesce((new.metadata->>'push_disabled')::boolean,false) then return new; end if;
  insert into private.push_dispatch_queue_v101(notification_id,user_id,category,status,next_attempt_at)
  values(new.id,new.user_id,private.push_category_v101(new.type),'queued',now())
  on conflict(notification_id) do nothing;
  return new;
end;
$$;

drop trigger if exists trg_notifications_push_v101 on public.notifications;
create trigger trg_notifications_push_v101
after insert on public.notifications
for each row execute function private.enqueue_notification_push_v101();

create or replace function public.get_push_center_v101(p_actor_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_uid uuid:=auth.uid();
  v_role text:=coalesce(auth.role(),'');
  v_public_key text;
  v_pref public.push_preferences_v101%rowtype;
  v_active integer:=0;
  v_total integer:=0;
  v_recent jsonb:='[]'::jsonb;
begin
  if p_actor_id is null then raise exception 'actor_id is required'; end if;
  if v_role<>'service_role' and (v_uid is null or v_uid<>p_actor_id) then raise exception 'actor identity mismatch'; end if;
  if not exists(select 1 from public.profiles p where p.id=p_actor_id and p.status::text='active') then raise exception 'active profile required'; end if;

  select decrypted_secret into v_public_key from vault.decrypted_secrets where name='cv_push_vapid_public_v101' order by created_at desc limit 1;
  select * into v_pref from public.push_preferences_v101 where user_id=p_actor_id;
  select count(*)::int,count(*) filter(where enabled)::int into v_total,v_active from public.push_subscriptions_v101 where user_id=p_actor_id;
  select coalesce(jsonb_agg(x order by x.created_at desc),'[]'::jsonb) into v_recent
  from (
    select q.notification_id,q.category,q.status,q.attempts,q.sent_at,q.skipped_reason,q.last_error,q.created_at
    from private.push_dispatch_queue_v101 q
    where q.user_id=p_actor_id
    order by q.created_at desc
    limit 10
  ) x;

  return jsonb_build_object(
    'version','PUSH_NOTIFICATIONS_OS_V101',
    'configured',coalesce(v_public_key,'')<>'',
    'vapid_public_key',v_public_key,
    'subscriptions',jsonb_build_object('total',v_total,'active',v_active),
    'preferences',jsonb_build_object(
      'enabled',coalesce(v_pref.enabled,true),
      'training_reminders',coalesce(v_pref.training_reminders,true),
      'program_updates',coalesce(v_pref.program_updates,true),
      'progress_updates',coalesce(v_pref.progress_updates,true),
      'coach_updates',coalesce(v_pref.coach_updates,true),
      'system_updates',coalesce(v_pref.system_updates,true),
      'quiet_hours_start',coalesce(v_pref.quiet_hours_start,time '21:00'),
      'quiet_hours_end',coalesce(v_pref.quiet_hours_end,time '08:00'),
      'timezone',coalesce(nullif(v_pref.timezone,''),(select coalesce(nullif(cp.timezone,''),'America/Santiago') from public.client_profiles cp where cp.client_id=p_actor_id),'America/Santiago'),
      'workout_reminder_time',v_pref.workout_reminder_time
    ),
    'recent_delivery',v_recent,
    'guardrails',jsonb_build_object('permission_requires_user_gesture',true,'quiet_hours_respected',true,'multi_device',true,'in_app_notification_is_source_of_truth',true,'auto_subscribe',false)
  );
end;
$$;

revoke all on function public.get_push_center_v101(uuid) from public;
grant execute on function public.get_push_center_v101(uuid) to authenticated,service_role;

create or replace function public.register_push_subscription_v101(
  p_actor_id uuid,
  p_endpoint text,
  p_p256dh text,
  p_auth_secret text,
  p_expiration_time bigint default null,
  p_user_agent text default null,
  p_device_label text default null,
  p_platform text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid:=auth.uid(); v_role text:=coalesce(auth.role(),''); v_id uuid; v_timezone text;
begin
  if p_actor_id is null then raise exception 'actor_id is required'; end if;
  if v_role<>'service_role' and (v_uid is null or v_uid<>p_actor_id) then raise exception 'actor identity mismatch'; end if;
  if not exists(select 1 from public.profiles p where p.id=p_actor_id and p.status::text='active') then raise exception 'active profile required'; end if;
  if char_length(btrim(coalesce(p_endpoint,''))) not between 20 and 4096 then raise exception 'invalid endpoint'; end if;
  if char_length(btrim(coalesce(p_p256dh,''))) not between 40 and 512 then raise exception 'invalid p256dh'; end if;
  if char_length(btrim(coalesce(p_auth_secret,''))) not between 8 and 256 then raise exception 'invalid auth secret'; end if;

  insert into public.push_subscriptions_v101(user_id,endpoint,p256dh,auth_secret,expiration_time,user_agent,device_label,platform,enabled,last_seen_at,disabled_at,updated_at)
  values(p_actor_id,btrim(p_endpoint),btrim(p_p256dh),btrim(p_auth_secret),p_expiration_time,left(p_user_agent,1000),left(p_device_label,160),left(p_platform,120),true,now(),null,now())
  on conflict(endpoint) do update set user_id=excluded.user_id,p256dh=excluded.p256dh,auth_secret=excluded.auth_secret,expiration_time=excluded.expiration_time,user_agent=excluded.user_agent,device_label=excluded.device_label,platform=excluded.platform,enabled=true,last_seen_at=now(),disabled_at=null,updated_at=now()
  returning id into v_id;

  select coalesce(nullif(cp.timezone,''),'America/Santiago') into v_timezone from public.client_profiles cp where cp.client_id=p_actor_id;
  insert into public.push_preferences_v101(user_id,enabled,timezone,updated_at)
  values(p_actor_id,true,coalesce(v_timezone,'America/Santiago'),now())
  on conflict(user_id) do update set enabled=true,updated_at=now();

  return jsonb_build_object('subscription_id',v_id,'registered',true,'enabled',true,'auto_send',true);
end;
$$;

revoke all on function public.register_push_subscription_v101(uuid,text,text,text,bigint,text,text,text) from public;
grant execute on function public.register_push_subscription_v101(uuid,text,text,text,bigint,text,text,text) to authenticated,service_role;

create or replace function public.disable_push_subscription_v101(p_actor_id uuid,p_endpoint text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_uid uuid:=auth.uid(); v_role text:=coalesce(auth.role(),''); v_count integer:=0;
begin
  if p_actor_id is null then raise exception 'actor_id is required'; end if;
  if v_role<>'service_role' and (v_uid is null or v_uid<>p_actor_id) then raise exception 'actor identity mismatch'; end if;
  update public.push_subscriptions_v101 set enabled=false,disabled_at=now(),updated_at=now() where user_id=p_actor_id and endpoint=btrim(coalesce(p_endpoint,'')) and enabled=true;
  get diagnostics v_count=row_count;
  return jsonb_build_object('disabled',v_count>0,'count',v_count);
end;
$$;
revoke all on function public.disable_push_subscription_v101(uuid,text) from public;
grant execute on function public.disable_push_subscription_v101(uuid,text) to authenticated,service_role;

create or replace function public.set_push_preferences_v101(
  p_actor_id uuid,
  p_enabled boolean,
  p_training_reminders boolean,
  p_program_updates boolean,
  p_progress_updates boolean,
  p_coach_updates boolean,
  p_system_updates boolean,
  p_quiet_hours_start time without time zone,
  p_quiet_hours_end time without time zone,
  p_timezone text,
  p_workout_reminder_time time without time zone default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_uid uuid:=auth.uid(); v_role text:=coalesce(auth.role(),''); v_tz text:=coalesce(nullif(btrim(p_timezone),''),'America/Santiago');
begin
  if p_actor_id is null then raise exception 'actor_id is required'; end if;
  if v_role<>'service_role' and (v_uid is null or v_uid<>p_actor_id) then raise exception 'actor identity mismatch'; end if;
  begin perform now() at time zone v_tz; exception when others then raise exception 'invalid timezone'; end;
  insert into public.push_preferences_v101(user_id,enabled,training_reminders,program_updates,progress_updates,coach_updates,system_updates,quiet_hours_start,quiet_hours_end,timezone,workout_reminder_time,updated_at)
  values(p_actor_id,coalesce(p_enabled,true),coalesce(p_training_reminders,true),coalesce(p_program_updates,true),coalesce(p_progress_updates,true),coalesce(p_coach_updates,true),coalesce(p_system_updates,true),coalesce(p_quiet_hours_start,time '21:00'),coalesce(p_quiet_hours_end,time '08:00'),v_tz,p_workout_reminder_time,now())
  on conflict(user_id) do update set enabled=excluded.enabled,training_reminders=excluded.training_reminders,program_updates=excluded.program_updates,progress_updates=excluded.progress_updates,coach_updates=excluded.coach_updates,system_updates=excluded.system_updates,quiet_hours_start=excluded.quiet_hours_start,quiet_hours_end=excluded.quiet_hours_end,timezone=excluded.timezone,workout_reminder_time=excluded.workout_reminder_time,updated_at=now();
  return jsonb_build_object('saved',true,'enabled',coalesce(p_enabled,true),'workout_reminder_time',p_workout_reminder_time,'auto_subscribe',false);
end;
$$;
revoke all on function public.set_push_preferences_v101(uuid,boolean,boolean,boolean,boolean,boolean,boolean,time,time,text,time) from public;
grant execute on function public.set_push_preferences_v101(uuid,boolean,boolean,boolean,boolean,boolean,boolean,time,time,text,time) to authenticated,service_role;

create or replace function public.enqueue_push_test_v101(p_actor_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_uid uuid:=auth.uid(); v_role text:=coalesce(auth.role(),''); v_notification uuid; v_existing uuid;
begin
  if p_actor_id is null then raise exception 'actor_id is required'; end if;
  if v_role<>'service_role' and (v_uid is null or v_uid<>p_actor_id) then raise exception 'actor identity mismatch'; end if;
  select n.id into v_existing from public.notifications n where n.user_id=p_actor_id and n.type='push_test' and n.created_at>now()-interval '20 seconds' order by n.created_at desc limit 1;
  if v_existing is not null then return jsonb_build_object('notification_id',v_existing,'idempotent',true); end if;
  insert into public.notifications(user_id,type,title,body,action_url,metadata)
  values(p_actor_id,'push_test','CV Coach · notificaciones activadas','Esta es una notificación de prueba. Tu dispositivo ya puede recibir avisos de CV Coach.','/',jsonb_build_object('source','push_v101_test','bypass_quiet_hours',true))
  returning id into v_notification;
  return jsonb_build_object('notification_id',v_notification,'idempotent',false);
end;
$$;
revoke all on function public.enqueue_push_test_v101(uuid) from public;
grant execute on function public.enqueue_push_test_v101(uuid) to authenticated,service_role;

create or replace function public.get_push_dispatch_config_v101()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare v_role text:=coalesce(auth.role(),''); v_public text; v_private text; v_token text;
begin
  if v_role<>'service_role' then raise exception 'service_role required'; end if;
  select decrypted_secret into v_public from vault.decrypted_secrets where name='cv_push_vapid_public_v101' order by created_at desc limit 1;
  select decrypted_secret into v_private from vault.decrypted_secrets where name='cv_push_vapid_private_v101' order by created_at desc limit 1;
  select decrypted_secret into v_token from vault.decrypted_secrets where name='cv_push_dispatch_token_v101' order by created_at desc limit 1;
  return jsonb_build_object('configured',coalesce(v_public,'')<>'' and coalesce(v_private,'')<>'' and coalesce(v_token,'')<>'','public_key',v_public,'private_key',v_private,'dispatch_token',v_token,'subject','https://cv-coach-roan.vercel.app');
end;
$$;
revoke all on function public.get_push_dispatch_config_v101() from public;
grant execute on function public.get_push_dispatch_config_v101() to service_role;

create or replace function public.claim_push_dispatch_v101(p_limit integer default 25)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_role text:=coalesce(auth.role(),''); v_rows jsonb;
begin
  if v_role<>'service_role' then raise exception 'service_role required'; end if;
  with picked as (
    select q.id from private.push_dispatch_queue_v101 q
    where q.status='queued' and q.next_attempt_at<=now() and q.attempts<5
    order by q.created_at asc
    for update skip locked
    limit greatest(1,least(coalesce(p_limit,25),100))
  ), claimed as (
    update private.push_dispatch_queue_v101 q set status='processing',attempts=q.attempts+1,locked_at=now(),updated_at=now(),last_error=null
    from picked p where q.id=p.id returning q.*
  )
  select coalesce(jsonb_agg(jsonb_build_object('queue_id',c.id,'notification_id',c.notification_id,'user_id',c.user_id,'category',c.category,'attempts',c.attempts,'type',n.type,'title',n.title,'body',n.body,'action_url',n.action_url,'metadata',n.metadata,'created_at',n.created_at) order by c.created_at),'[]'::jsonb)
  into v_rows from claimed c join public.notifications n on n.id=c.notification_id;
  return v_rows;
end;
$$;
revoke all on function public.claim_push_dispatch_v101(integer) from public;
grant execute on function public.claim_push_dispatch_v101(integer) to service_role;

create or replace function public.claim_push_notification_v101(p_notification_id uuid,p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_role text:=coalesce(auth.role(),''); v_row jsonb;
begin
  if v_role<>'service_role' then raise exception 'service_role required'; end if;
  with claimed as (
    update private.push_dispatch_queue_v101 q set status='processing',attempts=q.attempts+1,locked_at=now(),updated_at=now(),last_error=null
    where q.notification_id=p_notification_id and q.user_id=p_user_id and q.status in ('queued','failed') and q.attempts<5
    returning q.*
  )
  select jsonb_build_object('queue_id',c.id,'notification_id',c.notification_id,'user_id',c.user_id,'category',c.category,'attempts',c.attempts,'type',n.type,'title',n.title,'body',n.body,'action_url',n.action_url,'metadata',n.metadata,'created_at',n.created_at)
  into v_row from claimed c join public.notifications n on n.id=c.notification_id;
  return v_row;
end;
$$;
revoke all on function public.claim_push_notification_v101(uuid,uuid) from public;
grant execute on function public.claim_push_notification_v101(uuid,uuid) to service_role;

create or replace function public.defer_push_dispatch_v101(p_queue_id uuid,p_seconds integer,p_reason text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_role text:=coalesce(auth.role(),'');
begin
  if v_role<>'service_role' then raise exception 'service_role required'; end if;
  update private.push_dispatch_queue_v101 set status='queued',next_attempt_at=now()+make_interval(secs=>greatest(60,least(coalesce(p_seconds,600),86400))),locked_at=null,last_error=left(coalesce(p_reason,'deferred'),1000),updated_at=now() where id=p_queue_id and status='processing';
  return jsonb_build_object('queue_id',p_queue_id,'deferred',true);
end;
$$;
revoke all on function public.defer_push_dispatch_v101(uuid,integer,text) from public;
grant execute on function public.defer_push_dispatch_v101(uuid,integer,text) to service_role;

create or replace function public.finish_push_dispatch_v101(p_queue_id uuid,p_outcome text,p_results jsonb default '[]'::jsonb,p_error text default null)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_role text:=coalesce(auth.role(),''); v_queue private.push_dispatch_queue_v101%rowtype; v_item jsonb; v_sub uuid; v_http integer; v_status text; v_final text:=lower(coalesce(p_outcome,''));
begin
  if v_role<>'service_role' then raise exception 'service_role required'; end if;
  if v_final not in ('sent','partial','failed','skipped') then raise exception 'invalid outcome'; end if;
  select * into v_queue from private.push_dispatch_queue_v101 where id=p_queue_id for update;
  if v_queue.id is null then raise exception 'queue item not found'; end if;
  for v_item in select value from jsonb_array_elements(coalesce(p_results,'[]'::jsonb)) loop
    begin v_sub:=(v_item->>'subscription_id')::uuid; exception when others then v_sub:=null; end;
    begin v_http:=nullif(v_item->>'http_status','')::integer; exception when others then v_http:=null; end;
    v_status:=case when v_item->>'status'='sent' then 'sent' when v_http in (404,410) then 'expired' when v_item->>'status'='skipped' then 'skipped' else 'failed' end;
    insert into private.push_delivery_attempts_v101(queue_id,notification_id,user_id,subscription_id,delivery_status,http_status,error_message)
    values(v_queue.id,v_queue.notification_id,v_queue.user_id,v_sub,v_status,v_http,left(v_item->>'error',2000));
    if v_sub is not null and v_http in (404,410) then update public.push_subscriptions_v101 set enabled=false,disabled_at=now(),updated_at=now() where id=v_sub; end if;
  end loop;

  if v_final='failed' and v_queue.attempts<5 then
    update private.push_dispatch_queue_v101 set status='queued',next_attempt_at=now()+make_interval(mins=>least(60,power(2,greatest(0,v_queue.attempts-1))::int)),locked_at=null,last_error=left(coalesce(p_error,'push dispatch failed'),4000),updated_at=now() where id=v_queue.id;
  else
    update private.push_dispatch_queue_v101 set status=v_final,locked_at=null,sent_at=case when v_final in ('sent','partial') then now() else sent_at end,skipped_reason=case when v_final='skipped' then left(coalesce(p_error,'skipped'),1000) else skipped_reason end,last_error=case when v_final in ('failed','partial') then left(coalesce(p_error,'push dispatch issue'),4000) else null end,updated_at=now() where id=v_queue.id;
  end if;
  return jsonb_build_object('queue_id',v_queue.id,'outcome',v_final,'attempts',v_queue.attempts);
end;
$$;
revoke all on function public.finish_push_dispatch_v101(uuid,text,jsonb,text) from public;
grant execute on function public.finish_push_dispatch_v101(uuid,text,jsonb,text) to service_role;

create or replace function private.invoke_push_dispatch_v101()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_token text; v_request_id bigint;
begin
  select decrypted_secret into v_token from vault.decrypted_secrets where name='cv_push_dispatch_token_v101' order by created_at desc limit 1;
  if coalesce(v_token,'')='' then return jsonb_build_object('invoked',false,'reason','DISPATCH_TOKEN_NOT_CONFIGURED'); end if;
  select net.http_post(
    url:='https://fmhcansyxcsqkrivqchr.supabase.co/functions/v1/push-dispatch-v101',
    body:=jsonb_build_object('action','dispatch','dispatch_token',v_token,'limit',25),
    params:='{}'::jsonb,
    headers:='{"Content-Type":"application/json"}'::jsonb,
    timeout_milliseconds:=15000
  ) into v_request_id;
  return jsonb_build_object('invoked',v_request_id is not null,'request_id',v_request_id);
end;
$$;

create or replace function private.enqueue_workout_reminders_v101()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare r record; v_local timestamp; v_today date; v_time time; v_dow integer; v_day_match boolean; v_inserted integer:=0;
begin
  for r in
    select p.id user_id,pref.timezone,pref.workout_reminder_time,
           (select response_value::text from public.onboarding_responses o where o.client_id=p.id and o.question_key='preferred_training_days' order by o.created_at desc limit 1) preferred_days
    from public.profiles p join public.push_preferences_v101 pref on pref.user_id=p.id
    where p.role::text='client' and p.status::text='active' and pref.enabled=true and pref.training_reminders=true and pref.workout_reminder_time is not null
      and exists(select 1 from public.push_subscriptions_v101 s where s.user_id=p.id and s.enabled=true)
      and exists(select 1 from public.programs pr where pr.client_id=p.id and pr.status::text='active')
  loop
    begin v_local:=now() at time zone coalesce(nullif(r.timezone,''),'America/Santiago'); exception when others then v_local:=now() at time zone 'America/Santiago'; end;
    v_today:=v_local::date; v_time:=v_local::time; v_dow:=extract(isodow from v_local)::int;
    if v_time<r.workout_reminder_time or v_time>=r.workout_reminder_time+interval '10 minutes' then continue; end if;
    v_day_match:=case v_dow
      when 1 then lower(coalesce(r.preferred_days,'')) like '%lunes%'
      when 2 then lower(coalesce(r.preferred_days,'')) like '%martes%'
      when 3 then lower(coalesce(r.preferred_days,'')) like '%miércoles%' or lower(coalesce(r.preferred_days,'')) like '%miercoles%'
      when 4 then lower(coalesce(r.preferred_days,'')) like '%jueves%'
      when 5 then lower(coalesce(r.preferred_days,'')) like '%viernes%'
      when 6 then lower(coalesce(r.preferred_days,'')) like '%sábado%' or lower(coalesce(r.preferred_days,'')) like '%sabado%'
      when 7 then lower(coalesce(r.preferred_days,'')) like '%domingo%'
      else false end;
    if not v_day_match then continue; end if;
    if exists(select 1 from public.workout_sessions ws where ws.client_id=r.user_id and ws.status::text in ('completed','partial') and (coalesce(ws.finished_at,ws.started_at,ws.created_at) at time zone coalesce(nullif(r.timezone,''),'America/Santiago'))::date=v_today) then continue; end if;
    if exists(select 1 from public.notifications n where n.user_id=r.user_id and n.type='workout_reminder' and n.metadata->>'local_date'=v_today::text) then continue; end if;
    insert into public.notifications(user_id,type,title,body,action_url,metadata)
    values(r.user_id,'workout_reminder','Tu entrenamiento de hoy','Tienes una sesión programada para hoy. Abre CV Coach cuando estés listo para comenzar.','/routine',jsonb_build_object('source','push_v101_workout_reminder','local_date',v_today,'timezone',r.timezone));
    v_inserted:=v_inserted+1;
  end loop;
  return jsonb_build_object('inserted',v_inserted,'version','PUSH_NOTIFICATIONS_OS_V101');
end;
$$;

create or replace function private.recover_stale_push_dispatch_v101()
returns integer
language plpgsql
security definer
set search_path=''
as $$
declare v_count integer;
begin
  update private.push_dispatch_queue_v101 set status=case when attempts>=5 then 'failed' else 'queued' end,next_attempt_at=case when attempts>=5 then next_attempt_at else now() end,locked_at=null,last_error=coalesce(last_error,'Recovered stale processing lock'),updated_at=now() where status='processing' and locked_at<now()-interval '5 minutes';
  get diagnostics v_count=row_count;
  return v_count;
end;
$$;

do $$
declare v_job bigint;
begin
  select jobid into v_job from cron.job where jobname='cv_push_dispatch_v101' limit 1;
  if v_job is not null then perform cron.unschedule(v_job); end if;
  perform cron.schedule('cv_push_dispatch_v101','* * * * *','select private.recover_stale_push_dispatch_v101(); select private.invoke_push_dispatch_v101();');
  select jobid into v_job from cron.job where jobname='cv_workout_reminders_v101' limit 1;
  if v_job is not null then perform cron.unschedule(v_job); end if;
  perform cron.schedule('cv_workout_reminders_v101','*/5 * * * *','select private.enqueue_workout_reminders_v101();');
end $$;
