-- CV Coach V82 — reconcile pending progression queue after final signal upgrade
-- Re-runs the V82 guardrail against system-owned pending suggestions.

update public.progression_suggestions
set updated_at=updated_at
where status='pending'::public.progression_status
  and source_session_id is not null
  and reviewed_by is null;

do $$
begin
  if exists (
    select 1
    from public.progression_suggestions ps
    where ps.status='pending'::public.progression_status
      and ps.source_session_id is not null
      and ps.reviewed_by is null
      and (
        ps.engine_version is distinct from 'PROGRESSION_ENGINE_V82'
        or ps.action not in ('maintain','build_reps','increase_load')
        or ps.evidence_sessions is null
        or ps.confidence_band is null
      )
  ) then
    raise exception 'V82 queue reconciliation failed: unsafe or stale pending suggestion remains';
  end if;
end;
$$;
