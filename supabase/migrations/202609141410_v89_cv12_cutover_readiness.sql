-- CV Coach V89 — CV12 Cutover Readiness
-- Goals:
-- 1) close only semantically safe legacy exercise mappings;
-- 2) explicitly preserve unresolved legacy variants instead of coercing them;
-- 3) expose a machine-readable cutover readiness contract;
-- 4) preserve V87/V88 safety: no auto publish, no program edit, no legacy deletion.

DO $$
DECLARE
  v_press_mancuernas_id uuid;
BEGIN
  SELECT id INTO v_press_mancuernas_id
  FROM public.exercises
  WHERE slug='press-militar-mancuernas'
    AND active=true
  LIMIT 1;

  IF v_press_mancuernas_id IS NULL THEN
    RAISE EXCEPTION 'V89 requires active canonical exercise press-militar-mancuernas';
  END IF;

  INSERT INTO public.legacy_cv12_exercise_aliases_v87(
    legacy_name, exercise_id, mapping_status, confidence, note, updated_at
  ) VALUES (
    'Press de hombros con mancuernas',
    v_press_mancuernas_id,
    'linked',
    0.98,
    'V89 safe semantic match: dumbbell shoulder press -> canonical dumbbell military press.',
    now()
  )
  ON CONFLICT (legacy_name) DO UPDATE SET
    exercise_id=excluded.exercise_id,
    mapping_status='linked',
    confidence=excluded.confidence,
    note=excluded.note,
    updated_at=now();

  -- Explicitly preserve the three variants that do not yet have a safe
  -- canonical equivalent. These rows prevent future syncs from coercing them
  -- to a mechanically similar but semantically different exercise.
  INSERT INTO public.legacy_cv12_exercise_aliases_v87(
    legacy_name, exercise_id, mapping_status, confidence, note, updated_at
  ) VALUES
    ('Crunch en colchoneta', null, 'unmapped', 1.00,
      'V89 intentional gap: floor crunch is not equivalent to cable crunch.', now()),
    ('Curl de bíceps con mancuernas', null, 'unmapped', 1.00,
      'V89 intentional gap: generic dumbbell curl is not equivalent to incline, hammer, cable or barbell curl.', now()),
    ('Elevación lateral de pierna en colchoneta', null, 'unmapped', 1.00,
      'V89 intentional gap: side-lying hip abduction is not equivalent to machine hip abduction or shoulder lateral raise.', now())
  ON CONFLICT (legacy_name) DO UPDATE SET
    exercise_id=excluded.exercise_id,
    mapping_status=excluded.mapping_status,
    confidence=excluded.confidence,
    note=excluded.note,
    updated_at=now();

  UPDATE public.legacy_cv12_exercise_logs_v87
  SET exercise_id=v_press_mancuernas_id,
      mapping_status='linked',
      updated_at=now()
  WHERE lower(exercise_name)=lower('Press de hombros con mancuernas')
    AND mapping_status<>'linked';
END
$$;

CREATE OR REPLACE FUNCTION public.get_cv12_cutover_readiness_v89(p_pilot_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_pilot public.coach_intelligence_pilots%rowtype;
  v_legacy_sessions integer := 0;
  v_total_logs integer := 0;
  v_linked_logs integer := 0;
  v_unresolved_logs integer := 0;
  v_unresolved_names jsonb := '[]'::jsonb;
  v_sessions_completed integer := 0;
  v_evidence_exercises integer := 0;
  v_sync_state text := 'unknown';
  v_technical_ready boolean := false;
  v_real_cutover_ready boolean := false;
  v_longitudinal_ai_ready boolean := false;
BEGIN
  SELECT * INTO v_pilot
  FROM public.coach_intelligence_pilots
  WHERE id=p_pilot_id
    AND source_system='cv12_legacy'
    AND mode='observed_only';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'V89 requires an observed_only cv12_legacy pilot';
  END IF;

  SELECT count(*) INTO v_legacy_sessions
  FROM public.legacy_cv12_sessions_v87
  WHERE pilot_id=p_pilot_id;

  SELECT count(*),
         count(*) FILTER (WHERE mapping_status='linked'),
         count(*) FILTER (WHERE mapping_status<>'linked')
  INTO v_total_logs, v_linked_logs, v_unresolved_logs
  FROM public.legacy_cv12_exercise_logs_v87
  WHERE pilot_id=p_pilot_id;

  SELECT coalesce(jsonb_agg(x.exercise_name ORDER BY x.exercise_name),'[]'::jsonb)
  INTO v_unresolved_names
  FROM (
    SELECT DISTINCT exercise_name
    FROM public.legacy_cv12_exercise_logs_v87
    WHERE pilot_id=p_pilot_id
      AND mapping_status<>'linked'
  ) x;

  v_sessions_completed := coalesce(nullif(v_pilot.baseline_snapshot->>'sessions_completed','')::integer,0);
  v_evidence_exercises := coalesce(nullif(v_pilot.baseline_snapshot->>'evidence_exercises','')::integer,0);
  v_sync_state := coalesce(v_pilot.baseline_snapshot->>'v87_sync_state','unknown');

  -- Technical readiness means the source is synced and legacy history exists.
  -- It does not require a native identity yet.
  v_technical_ready := (v_sync_state='synced' AND v_legacy_sessions>0);

  -- Real cutover additionally requires a real native identity link.
  v_real_cutover_ready := (v_technical_ready AND v_pilot.client_id IS NOT NULL AND v_pilot.linked_at IS NOT NULL);

  -- Keep the V85 evidence threshold independent from account cutover.
  v_longitudinal_ai_ready := (v_sessions_completed>=3 AND v_evidence_exercises>=2);

  RETURN jsonb_build_object(
    'ok',true,
    'engine_version','CV12_CUTOVER_READINESS_V89',
    'pilot_id',p_pilot_id,
    'source_system',v_pilot.source_system,
    'mode',v_pilot.mode,
    'sync_state',v_sync_state,
    'native_identity',jsonb_build_object(
      'client_id',v_pilot.client_id,
      'linked_at',v_pilot.linked_at,
      'identity_required',v_pilot.client_id IS NULL
    ),
    'legacy_history',jsonb_build_object(
      'sessions',v_legacy_sessions,
      'exercise_logs',v_total_logs,
      'linked_exercise_logs',v_linked_logs,
      'unresolved_exercise_logs',v_unresolved_logs,
      'unresolved_exercise_names',v_unresolved_names,
      'preserved',true,
      'read_only_bridge',true
    ),
    'readiness',jsonb_build_object(
      'technical_ready_for_native_identity',v_technical_ready,
      'ready_for_real_cutover',v_real_cutover_ready,
      'longitudinal_ai_ready',v_longitudinal_ai_ready,
      'sessions_completed',v_sessions_completed,
      'evidence_exercises',v_evidence_exercises
    ),
    'warnings',jsonb_build_object(
      'unresolved_exercise_mappings',v_unresolved_logs,
      'unresolved_mappings_block_account_cutover',false,
      'baseline_insufficient_for_longitudinal_ai',NOT v_longitudinal_ai_ready
    ),
    'guardrails',jsonb_build_object(
      'auto_publish',false,
      'auto_program_edit',false,
      'legacy_source_preserved',true,
      'synthetic_identity_forbidden',true
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_cv12_cutover_readiness_v89(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_cv12_cutover_readiness_v89(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.get_cv12_cutover_readiness_v89(uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.get_cv12_cutover_readiness_v89(uuid) TO service_role;
