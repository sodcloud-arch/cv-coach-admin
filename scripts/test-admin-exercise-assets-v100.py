from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
html=(ROOT/'index.html').read_text(encoding='utf-8')
js=(ROOT/'admin-assets/cv-exercise-assets-v100.js').read_text(encoding='utf-8')
edge=(ROOT/'supabase/functions/generate-ai-program-v100/index.ts').read_text(encoding='utf-8')
asset=(ROOT/'supabase/functions/generate-exercise-asset-v100/index.ts').read_text(encoding='utf-8')
proxy=(ROOT/'supabase/functions/exercise-image-proxy/index.ts').read_text(encoding='utf-8')
sql='\n'.join(p.read_text(encoding='utf-8') for p in sorted((ROOT/'supabase/migrations').glob('*v100*.sql')))

checks={
 'admin marker':'cv-admin-exercise-assets-v100' in html,
 'admin asset':'/admin-assets/cv-exercise-assets-v100.js' in html,
 'ready marker':'CV_ADMIN_EXERCISE_ASSETS_V100_READY' in js,
 'AI wrapper':'/functions/v1/generate-ai-program-v100' in js,
 'control center':'get_exercise_asset_control_center_v100' in js,
 'human review':'review_exercise_asset_v100' in js,
 'generator pending review':"status:'pending_review'" in asset or "status:\"pending_review\"" in asset,
 'asset auto publish off':'auto_publish:false' in asset,
 'program wrapper delegates':'/functions/v1/generate-ai-program' in edge,
 'library gap max 3':'maxItems:3' in edge,
 'gap confidence gate':'necessity_confidence' in edge and '>=0.8' in edge,
 'proxy allowlist':'is_exercise_drive_asset_approved_v100' in proxy,
 'publish preflight':'get_program_asset_preflight_v100' in sql,
 'publisher core preserved':'publish_program_backend_core_v100' in sql,
 'new exercise starts inactive':'active:false' in asset,
 'generated assets require QA':'pending_review' in sql and 'auto_publish' in sql,
}
failed=[name for name,ok in checks.items() if not ok]
for name,ok in checks.items(): print(('OK ' if ok else 'FAIL ')+name)
if failed: raise SystemExit('V100 contract failures: '+', '.join(failed))
print('CV_ADMIN_EXERCISE_ASSETS_V100_CONTRACT_OK')
