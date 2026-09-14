from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]

def read(path):
    p=ROOT/path
    if not p.exists(): raise SystemExit(f'V84 required file missing: {path}')
    return p.read_text(encoding='utf-8')

def require(text,marker,label):
    if marker not in text: raise SystemExit(f'V84 contract failed: {label}: {marker!r}')

migration=read('supabase/migrations/202609140330_adaptive_programming_os_v84.sql')
admin=read('admin-assets/cv-adaptive-programming-admin-v84.js')
patch=read('scripts/upgrade_admin_adaptive_programming_v84.py')
edge=read('supabase/functions/cv-adaptive-canary-v84/index.ts')
e2e=read('scripts/test-adaptive-programming-e2e-v84.mjs')
canary=read('.github/workflows/production-canary-v76.yml')
deploy=read('.github/workflows/deploy-cv-coach-admin-production.yml')

for marker,label in [
    ('adaptive_program_drafts','adaptive draft persistence'),
    ('prepare_adaptive_program_draft_v84','adaptive draft RPC'),
    ('CLONE_PROGRAM_V84_PRESERVES_UNIT','time-unit clone fix'),
    ('prescription_unit','time/reps preservation'),
    ('get_adaptive_programming_center_v84','adaptive center RPC'),
    ('get_client_training_trends_v84','longitudinal trends RPC'),
    ('run_adaptive_programming_e2e_v84','isolated E2E RPC'),
    ("errcode='CV084'",'subtransaction rollback sentinel'),
    ('CV_V84_ADAPTIVE_PROGRAMMING_E2E_OK','E2E success contract'),
    ("'auto_publish',false",'no auto publish invariant'),
    ("v_mode='deload'",'deterministic deload mode'),
    ("v_mode='next_mesocycle'",'next mesocycle mode'),
]: require(migration,marker,label)

for marker,label in [
    ('CV_ADMIN_ADAPTIVE_PROGRAMMING_V84_READY','Admin V84 ready marker'),
    ('get_adaptive_programming_center_v84','Admin adaptive center'),
    ('get_client_training_trends_v84','Admin trends'),
    ('prepare_adaptive_program_draft_v84','Admin draft preparation'),
    ('PREPARAR DELOAD','deload CTA'),
    ('PREPARAR SIGUIENTE BLOQUE','next-block CTA'),
    ('TENDENCIAS V84','longitudinal CTA'),
]: require(admin,marker,label)

require(patch,'cv-admin-adaptive-programming-v84','Admin patch marker')
require(patch,'openTrainingTrendsV84','Ficha 360 trends hook')
require(edge,'token.actions.githubusercontent.com','GitHub OIDC issuer')
require(edge,'run_adaptive_programming_e2e_v84','service E2E RPC')
require(edge,'CV_V84_ADAPTIVE_PROGRAMMING_E2E_OK','edge success contract')
require(e2e,'suggested_duration_seconds:35','time progression assertion')
require(e2e,'rollback_isolated:true','rollback assertion')
require(canary,'Run adaptive programming E2E V84','production canary V84 step')
require(deploy,'upgrade_admin_adaptive_programming_v84.py','production Admin V84 build')
require(deploy,'PUBLIC_ADMIN_V84_OK','public Admin V84 verifier')
print('CV_V84_CONTRACTS_OK')
