from pathlib import Path

# Idempotent installer: workflow permissions may already be applied directly.
worker_path = Path('.github/workflows/cv-autopilot-worker.yml')
review_path = Path('scripts/autopilot-self-review.sh')

worker = worker_path.read_text()
old_perm = '''    permissions:
      contents: write
      id-token: write
      issues: write
      pull-requests: write'''
new_perm = '''    permissions:
      contents: write
      actions: write
      id-token: write
      issues: write
      pull-requests: write'''
if 'actions: write' not in worker:
    count = worker.count(old_perm)
    if count != 3:
        raise SystemExit(f'expected 3 self-review job permission blocks, found {count}')
    worker = worker.replace(old_perm, new_perm)
worker_path.write_text(worker)

review = review_path.read_text()
if 'dispatch_production_deploy()' not in review:
    insert_at = review.index('\n\nvalidate_worktree()')
    helper = r'''

dispatch_production_deploy() {
  local attempt
  for attempt in 1 2 3; do
    if gh workflow run deploy-cv-coach-admin-production.yml --ref main; then
      echo "Autopilot self-review: production deploy dispatched."
      return 0
    fi
    sleep "$((attempt * 3))"
  done
  return 1
}'''
    review = review[:insert_at] + helper + review[insert_at:]

old_merge_tail = '''    merge_sha="$(gh pr view "${pr_number}" --json mergeCommit --jq '.mergeCommit.oid // ""' 2>/dev/null || true)"
    review_resolved "${request_id}" "${pr_url}" "${pr_number}" "${merge_sha}" "${iteration}" "LOW" >/dev/null'''
new_merge_tail = '''    merge_sha="$(gh pr view "${pr_number}" --json mergeCommit --jq '.mergeCommit.oid // ""' 2>/dev/null || true)"
    if ! dispatch_production_deploy; then
      review_human_blocker "${request_id}" "LOW-risk PR merged successfully, but production deployment dispatch failed after 3 attempts." "Inspect GitHub Actions permission or production deploy workflow availability; source is already merged but not confirmed deployed." "${pr_url}" "${iteration}" "MEDIUM" >/dev/null
      git checkout main >/dev/null 2>&1 || true
      bash scripts/autopilot-worker.sh
      exit 0
    fi
    review_resolved "${request_id}" "${pr_url}" "${pr_number}" "${merge_sha}" "${iteration}" "LOW" >/dev/null'''
if old_merge_tail in review:
    review = review.replace(old_merge_tail, new_merge_tail, 1)
elif new_merge_tail not in review:
    raise SystemExit('merge success tail not found')
review_path.write_text(review)
