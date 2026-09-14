-- CV Coach V90 — CV12 Native Cutover Orchestrator
-- One authenticated, idempotent operation to link a real native client identity
-- to a technically-ready CV12 legacy pilot. No session copying, no program edits.

CREATE TABLE IF NOT EXISTS public.cv12_cutover_audit_v90 (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pilot_id uuid NOT NULL REFERENCES public.coach_intelligence_pilots(id) ON DELETE CASCADE,
  client_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  actor_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  action text NOT NULL CHECK (action IN ('linked','noop_existing_link','rollback')),
  idempotency_key text NOT NULL UNIQUE,
  readiness jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.cv12_cutover_audit_v90 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.cv12_cutover_audit_v90 FROM PUBLIC;
REVOKE ALL ON TABLE public.cv12_cutover_audit_v90 FROM anon;
REVOKE ALL ON TABLE public.cv12_cutover_audit_v90 FROM authenticated;
GRANT ALL ON TABLE public.cv12_cutover_audit_v90 TO service_role;

CREATE OR REPLACE FUNCTION public.execute_cv12_native_cutover_v90(
  p_pilot_id uuid,
  p_client_id uuid,
  p_actor_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_actor_role public.app_role;
  v_client_name text;
  v_client_email text;
  v_pilot public.coach_intelligence_pilots%rowtype;
  v_pre jsonb;
  v_post jsonb;
  v_refresh jsonb;
  v_action text;
  v_audit_id uuid;
BEGIN
  IF auth.uid() IS NULL OR auth.uid()<>p_actor_id THEN
    RAISE EXCEPTION 'Actor authentication mismatch';
  END IF;

  SELECT role INTO v_actor_role
  FROM public.profiles
  WHERE id=p_actor_id
    AND status='active'::public.profile_status;

  IF v_actor_role IS NULL OR v_actor_role NOT IN ('admin'::public.app_role,'coach'::public.app_role) THEN
    RAISE EXCEPTION 'Coach/admin required';
  END IF;

  SELECT concat_ws(' ',p.first_name,p.last_name),u.email
  INTO v_client_name,v_client_email
  FROM public.profiles p
  JOIN auth.users u ON u.id=p.id
  WHERE p.id=p_client_id
    AND p.role='client'::public.app_role
    AND p.status='active'::public.profile_status
    AND u.email IS NOT NULL
  LIMIT 1;

  IF v_client_name IS NULL OR v_client_email IS NULL THEN
    RAISE EXCEPTION 'Real native active client identity required';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.client_profiles cp WHERE cp.client_id=p_client_id
  ) THEN
    RAISE EXCEPTION 'Native client profile required';
  END IF;

  IF v_actor_role='coach'::public.app_role AND NOT EXISTS (
    SELECT 1
    FROM public.coach_clients cc
    WHERE cc.coach_id=p_actor_id
      AND cc.client_id=p_client_id
      AND cc.status='active'::public.coach_client_status
  ) THEN
    RAISE EXCEPTION 'Coach must have an active relationship with client';
  END IF;

  SELECT * INTO v_pilot
  FROM public.coach_intelligence_pilots
  WHERE id=p_pilot_id
    AND source_system='cv12_legacy'
    AND mode='observed_only'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'V90 requires an observed_only cv12_legacy pilot';
  END IF;

  v_pre := public.get_cv12_cutover_readiness_v89(p_pilot_id);

  IF coalesce((v_pre->'readiness'->>'technical_ready_for_native_identity')::boolean,false) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'CV12 pilot is not technically ready for native identity';
  END IF;

  IF v_pilot.client_id IS NULL THEN
    UPDATE public.coach_intelligence_pilots
    SET client_id=p_client_id,
        linked_at=now(),
        status='linked',
        updated_at=now()
    WHERE id=p_pilot_id
      AND client_id IS NULL;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Pilot identity changed during cutover';
    END IF;
    v_action := 'linked';
  ELSIF v_pilot.client_id=p_client_id THEN
    IF v_pilot.linked_at IS NULL THEN
      UPDATE public.coach_intelligence_pilots
      SET linked_at=now(),updated_at=now()
      WHERE id=p_pilot_id AND client_id=p_client_id;
    END IF;
    v_action := 'noop_existing_link';
  ELSE
    RAISE EXCEPTION 'Pilot already linked to another native client';
  END IF;

  v_refresh := public.refresh_cv12_pilot_baseline_v87(p_pilot_id);
  v_post := public.get_cv12_cutover_readiness_v89(p_pilot_id);

  IF coalesce((v_post->'readiness'->>'ready_for_real_cutover')::boolean,false) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'V90 post-cutover readiness verification failed';
  END IF;

  INSERT INTO public.cv12_cutover_audit_v90(
    pilot_id,client_id,actor_id,action,idempotency_key,readiness,updated_at
  ) VALUES (
    p_pilot_id,p_client_id,p_actor_id,v_action,
    'cv12_native_cutover:'||p_pilot_id::text||':'||p_client_id::text,
    v_post,now()
  )
  ON CONFLICT (idempotency_key) DO UPDATE SET
    readiness=excluded.readiness,
    updated_at=now()
  RETURNING id INTO v_audit_id;

  RETURN jsonb_build_object(
    'ok',true,
    'engine_version','CV12_NATIVE_CUTOVER_ORCHESTRATOR_V90',
    'action',v_action,
    'pilot_id',p_pilot_id,
    'client_id',p_client_id,
    'native_identity_verified',true,
    'native_client_name',v_client_name,
    'audit_id',v_audit_id,
    'readiness',v_post,
    'baseline',v_refresh,
    'event_emission_deferred',true,
    'event_reason','No registered consumer owns a CV12 cutover event yet.',
    'guardrails',jsonb_build_object(
      'auto_publish',false,
      'auto_program_edit',false,
      'native_sessions_created',false,
      'native_programs_created',false,
      'legacy_source_preserved',true,
      'synthetic_identity_forbidden',true
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.rollback_cv12_native_cutover_v90(
  p_pilot_id uuid,
  p_expected_client_id uuid,
  p_actor_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_result jsonb;
  v_post jsonb;
  v_audit_id uuid;
BEGIN
  -- V88 performs the authenticated actor/role and expected-client checks.
  v_result := public.unlink_cv12_pilot_native_v88(
    p_pilot_id,
    p_expected_client_id,
    p_actor_id
  );

  v_post := public.get_cv12_cutover_readiness_v89(p_pilot_id);

  IF coalesce((v_post->'readiness'->>'technical_ready_for_native_identity')::boolean,false) IS DISTINCT FROM true
     OR coalesce((v_post->'native_identity'->>'identity_required')::boolean,false) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'V90 rollback verification failed';
  END IF;

  INSERT INTO public.cv12_cutover_audit_v90(
    pilot_id,client_id,actor_id,action,idempotency_key,readiness,updated_at
  ) VALUES (
    p_pilot_id,p_expected_client_id,p_actor_id,'rollback',
    'cv12_native_cutover_rollback:'||p_pilot_id::text||':'||p_expected_client_id::text,
    v_post,now()
  )
  ON CONFLICT (idempotency_key) DO UPDATE SET
    readiness=excluded.readiness,
    updated_at=now()
  RETURNING id INTO v_audit_id;

  RETURN jsonb_build_object(
    'ok',true,
    'engine_version','CV12_NATIVE_CUTOVER_ORCHESTRATOR_V90',
    'action','rollback',
    'pilot_id',p_pilot_id,
    'client_id',p_expected_client_id,
    'audit_id',v_audit_id,
    'unlink_result',v_result,
    'readiness',v_post,
    'legacy_history_preserved',true,
    'native_data_deleted',false,
    'auto_publish',false,
    'auto_program_edit',false
  );
END;
$$;

REVOKE ALL ON FUNCTION public.execute_cv12_native_cutover_v90(uuid,uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.execute_cv12_native_cutover_v90(uuid,uuid,uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.execute_cv12_native_cutover_v90(uuid,uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.execute_cv12_native_cutover_v90(uuid,uuid,uuid) TO service_role;

REVOKE ALL ON FUNCTION public.rollback_cv12_native_cutover_v90(uuid,uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rollback_cv12_native_cutover_v90(uuid,uuid,uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.rollback_cv12_native_cutover_v90(uuid,uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rollback_cv12_native_cutover_v90(uuid,uuid,uuid) TO service_role;
