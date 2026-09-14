-- CV Coach V84 — rollback-isolated deload draft E2E contract.

begin;

create or replace function public.run_adaptive_draft_e2e_v84(p_run_id text default null)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_client uuid;
  v_actor uuid;
  v_program uuid;
  v_day uuid;
  v_session uuid;
  v_review uuid;
  v_draft uuid;
  v_adapt jsonb;
  v_prepare jsonb;
  v_source_status text;
  v_source_count integer;
  v_draft_count integer;
  v_unit_mismatch integer;
  v_set_mismatch integer;
  v_rir_mismatch integer;
  v_result jsonb;
  i integer;
begin
  if coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;

  begin
    select client_id into v_client
    from public.cv_canary_clients
    where label='production-v76' and enabled=true
    limit 1;
    if v_client is null then raise exception 'V84 draft canary client missing'; end if;

    select id into v_actor
    from public.profiles
    where role='admin'::public.app_role and status='active'::public.profile_status
    order by created_at limit 1;
    if v_actor is null then raise exception 'V84 draft admin actor missing'; end if;

    select id into v_program
    from public.programs
    where client_id=v_client and status='active'::public.program_status
    order by updated_at desc limit 1;
    if v_program is null then raise exception 'V84 draft active canary program missing'; end if;

    if exists(select 1 from public.programs where client_id=v_client and status='draft'::public.program_status) then
      raise exception 'V84 draft canary already has a draft; isolated contract cannot proceed';
    end if;

    select id into v_day from public.program_days where program_id=v_program order by day_number limit 1;
    if v_day is null then raise exception 'V84 draft canary day missing'; end if;

    -- Advance only the synthetic block clock inside this rollback-isolated subtransaction.
    update public.programs set start_date=current_date-interval '42 days' where id=v_program;

    for i in 1..3 loop
      insert into public.workout_sessions(
        client_id,program_id,program_day_id,started_at,finished_at,status,completion_pct,
        duration_seconds,client_effort,fatigue_score,pain_score,difficulty_level,had_pain,session_notes
      ) values(
        v_client,v_program,v_day,
        now()-(10-i)*interval '1 minute',now()-(9-i)*interval '1 minute',
        'completed'::public.workout_session_status,100,60,9,7,0,5,false,
        'CV_V84_DRAFT_E2E '||coalesce(p_run_id,'local')||' #'||i
      ) returning id into v_session;
    end loop;

    v_adapt:=private.compute_training_adaptation_v83(v_client,v_program,now());
    if coalesce((v_adapt->>'deload_recommended')::boolean,false)<>true
       or coalesce(v_adapt->>'state','')<>'deload_recommended' then
      raise exception 'V84 draft E2E failed to create deload evidence: %',v_adapt;
    end if;

    insert into public.training_adaptation_reviews(
      client_id,program_id,source_session_id,state,block_week,recent_sessions,
      progress_signals,stagnation_signals,data_gap_signals,recovery_flags,
      average_completion_pct,deload_recommended,reason_codes,evidence,status
    ) values(
      v_client,v_program,v_session,
      v_adapt->>'state',nullif(v_adapt->>'block_week','')::integer,
      coalesce(nullif(v_adapt->>'recent_sessions','')::integer,0),
      coalesce(nullif(v_adapt->>'progress_signals','')::integer,0),
      coalesce(nullif(v_adapt->>'stagnation_signals','')::integer,0),
      coalesce(nullif(v_adapt->>'data_gap_signals','')::integer,0),
      coalesce(nullif(v_adapt->>'recovery_flags','')::integer,0),
      nullif(v_adapt->>'average_completion_pct','')::numeric,
      true,coalesce(v_adapt->'reason_codes','[]'::jsonb),v_adapt,'pending'
    ) returning id into v_review;

    perform pg_catalog.set_config('request.jwt.claim.sub',v_actor::text,true);
    v_prepare:=public.prepare_adaptive_program_draft_v84(v_actor,v_review,'deload');
    if coalesce(v_prepare->>'status','')<>'prepared' then
      raise exception 'V84 draft E2E prepare failed: %',v_prepare;
    end if;
    v_draft:=(v_prepare->>'program_id')::uuid;

    select status::text into v_source_status from public.programs where id=v_program;
    if v_source_status<>'active' then raise exception 'V84 draft E2E mutated active source status'; end if;

    select count(*) into v_source_count
    from public.program_exercises spe
    join public.program_days spd on spd.id=spe.program_day_id
    where spd.program_id=v_program;

    select count(*) into v_draft_count
    from public.program_exercises dpe
    join public.program_days dpd on dpd.id=dpe.program_day_id
    where dpd.program_id=v_draft;

    select
      count(*) filter(where dpe.prescription_unit is distinct from spe.prescription_unit),
      count(*) filter(where dpe.target_sets is distinct from case when spe.target_sets is null then null else greatest(1,ceil(spe.target_sets*0.60)::integer) end),
      count(*) filter(where dpe.rir_target is null or dpe.rir_target<greatest(coalesce(spe.rir_target,3),3))
    into v_unit_mismatch,v_set_mismatch,v_rir_mismatch
    from public.program_days spd
    join public.program_days dpd on dpd.program_id=v_draft and dpd.day_number=spd.day_number
    join public.program_exercises spe on spe.program_day_id=spd.id
    join public.program_exercises dpe on dpe.program_day_id=dpd.id and dpe.exercise_order=spe.exercise_order and dpe.exercise_id=spe.exercise_id
    where spd.program_id=v_program;

    if v_source_count=0 or v_draft_count<>v_source_count then
      raise exception 'V84 draft E2E clone count mismatch source %, draft %',v_source_count,v_draft_count;
    end if;
    if coalesce(v_unit_mismatch,0)>0 then raise exception 'V84 draft E2E prescription unit mismatch'; end if;
    if coalesce(v_set_mismatch,0)>0 then raise exception 'V84 draft E2E deload set mismatch'; end if;
    if coalesce(v_rir_mismatch,0)>0 then raise exception 'V84 draft E2E deload RIR mismatch'; end if;
    if not exists(select 1 from public.adaptive_program_drafts where draft_program_id=v_draft and mode='deload' and status='prepared') then
      raise exception 'V84 draft E2E tracking row missing';
    end if;

    v_result:=jsonb_build_object(
      'ok',true,
      'contract','CV_V84_ADAPTIVE_DRAFT_E2E_OK',
      'run_id',p_run_id,
      'adaptation_state',v_adapt->>'state',
      'deload_recommended',true,
      'draft_mode','deload',
      'active_source_unchanged',true,
      'prescription_units_preserved',true,
      'volume_reduced',true,
      'rir_floor_applied',true,
      'source_exercises',v_source_count,
      'draft_exercises',v_draft_count,
      'rollback_isolated',true
    );

    raise exception using errcode='CV086',message='rollback_v84_draft_e2e';
  exception when sqlstate 'CV086' then
    return v_result;
  end;
end;
$$;

revoke all on function public.run_adaptive_draft_e2e_v84(text) from public,anon,authenticated;
grant execute on function public.run_adaptive_draft_e2e_v84(text) to service_role;

commit;
