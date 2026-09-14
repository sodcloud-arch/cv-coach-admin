-- CV Coach V91 — CV12 Cutover Control API
-- Read-only operator RPCs for the admin panel. Sensitive link execution stays in V90.

CREATE OR REPLACE FUNCTION public.get_cv12_cutover_control_v91(p_pilot_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_role public.app_role;
  v_items jsonb := '[]'::jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  SELECT role INTO v_role FROM public.profiles WHERE id=v_uid AND status='active'::public.profile_status;
  IF v_role IS NULL OR v_role NOT IN ('admin'::public.app_role,'coach'::public.app_role) THEN
    RAISE EXCEPTION 'Coach/admin required';
  END IF;

  SELECT coalesce(jsonb_agg(item ORDER BY subject_label),'[]'::jsonb)
  INTO v_items
  FROM (
    SELECT p.subject_label,
           jsonb_build_object(
             'pilot_id',p.id,
             'subject_label',p.subject_label,
             'coach_id',p.coach_id,
             'client_id',p.client_id,
             'source_system',p.source_system,
             'mode',p.mode,
             'status',p.status,
             'started_at',p.started_at,
             'linked_at',p.linked_at,
             'updated_at',p.updated_at,
             'readiness',public.get_cv12_cutover_readiness_v89(p.id),
             'next_action',case
               when coalesce((public.get_cv12_cutover_readiness_v89(p.id)->'readiness'->>'technical_ready_for_native_identity')::boolean,false)=false then 'repair_legacy_sync'
               when coalesce((public.get_cv12_cutover_readiness_v89(p.id)->'native_identity'->>'identity_required')::boolean,false)=true then 'provide_real_client_email'
               when coalesce((public.get_cv12_cutover_readiness_v89(p.id)->'readiness'->>'ready_for_real_cutover')::boolean,false)=true
                    and coalesce((public.get_cv12_cutover_readiness_v89(p.id)->'readiness'->>'longitudinal_ai_ready')::boolean,false)=false then 'collect_more_training_evidence'
               when coalesce((public.get_cv12_cutover_readiness_v89(p.id)->'readiness'->>'ready_for_real_cutover')::boolean,false)=true then 'cutover_complete'
               else 'review'
             end
           ) AS item
    FROM public.coach_intelligence_pilots p
    WHERE p.source_system='cv12_legacy'
      AND p.mode='observed_only'
      AND (p_pilot_id IS NULL OR p.id=p_pilot_id)
      AND (v_role='admin'::public.app_role OR p.coach_id=v_uid)
  ) q;

  RETURN jsonb_build_object(
    'ok',true,
    'engine_version','CV12_CUTOVER_CONTROL_API_V91',
    'actor_role',v_role,
    'items',v_items,
    'count',jsonb_array_length(v_items),
    'execution_rpc','execute_cv12_native_cutover_v90',
    'rollback_rpc','rollback_cv12_native_cutover_v90'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_cv12_native_client_v91(p_email text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_role public.app_role;
  v_email text := lower(btrim(coalesce(p_email,'')));
  v_client_id uuid;
  v_client_name text;
  v_profile_status public.profile_status;
  v_onboarding public.onboarding_status;
  v_relationship public.coach_client_status;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  SELECT role INTO v_role FROM public.profiles WHERE id=v_uid AND status='active'::public.profile_status;
  IF v_role IS NULL OR v_role NOT IN ('admin'::public.app_role,'coach'::public.app_role) THEN
    RAISE EXCEPTION 'Coach/admin required';
  END IF;
  IF v_email='' OR position('@' in v_email)<=1 THEN RAISE EXCEPTION 'Valid email required'; END IF;

  SELECT p.id,concat_ws(' ',p.first_name,p.last_name),p.status,cp.onboarding_status
  INTO v_client_id,v_client_name,v_profile_status,v_onboarding
  FROM auth.users u
  JOIN public.profiles p ON p.id=u.id AND p.role='client'::public.app_role
  LEFT JOIN public.client_profiles cp ON cp.client_id=p.id
  WHERE lower(u.email)=v_email
  LIMIT 1;

  IF v_client_id IS NULL THEN
    RETURN jsonb_build_object(
      'ok',true,
      'engine_version','CV12_CUTOVER_CONTROL_API_V91',
      'resolution','identity_not_found',
      'email',v_email,
      'client_id',null,
      'ready_for_v90',false,
      'next_action','provision_real_client_identity'
    );
  END IF;

  IF v_role='coach'::public.app_role THEN
    SELECT cc.status INTO v_relationship
    FROM public.coach_clients cc
    WHERE cc.coach_id=v_uid AND cc.client_id=v_client_id
    ORDER BY cc.assigned_at DESC LIMIT 1;
  ELSE
    v_relationship := 'active'::public.coach_client_status;
  END IF;

  RETURN jsonb_build_object(
    'ok',true,
    'engine_version','CV12_CUTOVER_CONTROL_API_V91',
    'resolution','identity_found',
    'email',v_email,
    'client_id',v_client_id,
    'client_name',v_client_name,
    'profile_status',v_profile_status,
    'onboarding_status',v_onboarding,
    'coach_relationship_status',v_relationship,
    'ready_for_v90',(
      v_profile_status='active'::public.profile_status
      and v_onboarding is not null
      and (v_role='admin'::public.app_role or v_relationship='active'::public.coach_client_status)
    ),
    'next_action',case
      when v_profile_status<>'active'::public.profile_status then 'activate_client_profile'
      when v_onboarding is null then 'create_client_profile'
      when v_role='coach'::public.app_role and v_relationship is distinct from 'active'::public.coach_client_status then 'assign_client_to_coach'
      else 'execute_v90'
    end
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_cv12_cutover_control_v91(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_cv12_cutover_control_v91(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_cv12_cutover_control_v91(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_cv12_cutover_control_v91(uuid) TO service_role;

REVOKE ALL ON FUNCTION public.resolve_cv12_native_client_v91(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.resolve_cv12_native_client_v91(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.resolve_cv12_native_client_v91(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_cv12_native_client_v91(text) TO service_role;
