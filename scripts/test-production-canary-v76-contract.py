from pathlib import Path

root = Path(__file__).resolve().parents[1]
workflow = (root / '.github/workflows/production-canary-v76.yml').read_text()
script = (root / 'scripts/test-production-canary-v76.mjs').read_text()
edge = (root / 'supabase/functions/cv-canary-auth-v76/index.ts').read_text()
migration = (root / 'supabase/migrations/202609121845_production_canary_v76.sql').read_text()
ordered_baseline = (root / 'supabase/migrations/202609121915_production_canary_v76_ordered_baseline.sql').read_text()

required_workflow = [
    'CV Coach Production Canary V76',
    'workflow_run:',
    "cron: '17 */6 * * *'",
    'id-token: write',
    'scripts/test-production-canary-v76.mjs',
]
required_script = [
    'cv-canary-auth-v76',
    'ACTIONS_ID_TOKEN_REQUEST_TOKEN',
    'cv-coach-production-canary-v76',
    'verifyOtp',
    'startWorkoutFromCurrentView',
    'button[onclick*="startWorkout"]',
    '#cvw_0_0',
    '#cvr_0_0',
    '.cvSetCheck',
    '#cvFeedbackFinish',
    'CV_CANARY_V76_COACH_VISIBILITY_OK',
    'CV_CANARY_V76_CLEANUP_OK',
    'CV_PRODUCTION_CANARY_V76_OK',
]
required_edge = [
    'createRemoteJWKSet',
    'jwtVerify',
    'workflow_ref',
    'production-canary-v76.yml@',
    'generateLink',
    'cv_canary_runs',
    'state_drift_before_cleanup',
    'coach_ficha_visible',
    'coach_report_visible',
    'restoreBaseline',
]
required_migration = [
    'cv_canary_clients',
    'cv_canary_runs',
    'private.is_cv_canary_client',
    'private.workout_outbox_on_insert',
    'private.workout_outbox_on_finish',
    'private.recalculate_cv_score_trigger',
    'private.invalidate_superseded_progressions_trigger',
    "lower(btrim(coalesce(first_name,'')))='cliente'",
    "lower(btrim(coalesce(last_name,'')))='prueba'",
]
required_ordered_baseline = [
    'alter table public.cv_canary_runs',
    'alter column baseline type json',
    'using baseline::json',
]

for label, content, needles in [
    ('workflow', workflow, required_workflow),
    ('script', script, required_script),
    ('edge', edge, required_edge),
    ('migration', migration, required_migration),
    ('ordered_baseline', ordered_baseline, required_ordered_baseline),
]:
    missing = [needle for needle in needles if needle not in content]
    assert not missing, f'{label} missing: {missing}'

assert 'password' not in script.lower(), 'canary script must not carry a password'
assert 'cliente.prueba@' not in script.lower(), 'canary script must not carry QA email'
assert 'cliente.prueba@' not in edge.lower(), 'edge function must resolve QA email server-side'
assert 'SUPABASE_SERVICE_ROLE_KEY' not in script, 'service-role key must stay server-side'
assert 'ABRIR ENTRENAMIENTO' not in script, 'canary must not assume an obsolete intermediate copy step'
assert 'workflow_dispatch:' in workflow
assert 'schedule:' in workflow

print('CV_PRODUCTION_CANARY_V76_CONTRACT_OK')
