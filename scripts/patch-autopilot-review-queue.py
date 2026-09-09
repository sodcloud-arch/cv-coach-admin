from pathlib import Path

path = Path('scripts/autopilot-self-review.sh')
text = path.read_text()

# 1) Review queue recovery: skip stale/non-reviewable PRs instead of stopping at the oldest.
if 'skipping stale/non-reviewable PR' not in text:
    start = text.index('find_review_pr() {')
    end_marker = '\n}\n\nif [[ -z "${OPENAI_API_KEY:-}" ]]'
    end = text.index(end_marker, start) + len('\n}')
    new_block = r'''find_review_pr() {
  local pr body request_id ctx kind status
  while IFS= read -r pr; do
    [[ -z "${pr}" ]] && continue
    body="$(jq -r '.body // ""' <<<"${pr}")"
    request_id="$(printf '%s\n' "${body}" | sed -n 's/^AUTOPILOT_EXTERNAL_REQUEST_ID: //p' | head -n 1)"
    [[ -z "${request_id}" ]] && continue
    ctx="$(review_context "${request_id}" 2>/dev/null || true)"
    kind="$(jq -r '.kind // empty' <<<"${ctx}" 2>/dev/null || true)"
    status="$(jq -r '.result.request_status // empty' <<<"${ctx}" 2>/dev/null || true)"
    if [[ "${kind}" == "AI_REVIEW_CONTEXT" && "${status}" == "WAITING_REVIEW" ]]; then
      printf '%s\n' "${pr}"
      return 0
    fi
    echo "Autopilot self-review: skipping stale/non-reviewable PR #$(jq -r '.number' <<<"${pr}") request_status=${status:-unknown}" >&2
  done < <(gh pr list --state open --limit 30 \
    --json number,url,title,body,isDraft,headRefName,baseRefName,createdAt \
    | jq -c '[.[] | select(.baseRefName=="main" and (.headRefName|startswith("autopilot/")) and (((.body // "")|contains("AUTOPILOT_EXTERNAL_REQUEST_ID:"))))] | sort_by(.createdAt)[]')
  return 0
}'''
    text = text[:start] + new_block + text[end:]

# 2) Sensitive-context precision: validation text such as "secret scan" must not force human review.
old_sensitive = "if grep -Eiq '(password|contraseñ|credential|credencial|secret|secreto|api[ _-]?key|payment|pago|billing|factur|delete|borrar|eliminar|drop table|rls|permission|permiso|service[_-]?role|security|seguridad|migration|migración|production data|datos de producción)' <<<\"${context_text}\"; then"
new_sensitive = "if grep -Eiq '(password|contraseñ|credential|credencial|api[ _-]?key|payment|pago|billing|factur|delete|borrar|eliminar|drop table|rls|permission|permiso|service[_-]?role|security|seguridad|migration|migración|production data|datos de producción|github[ _-]?secret|crear.{0,40}(secret|secreto)|modificar.{0,40}(secret|secreto)|rotar.{0,40}(secret|secreto)|eliminar.{0,40}(secret|secreto))' <<<\"${context_text}\"; then"
if old_sensitive in text:
    text = text.replace(old_sensitive, new_sensitive, 1)
elif new_sensitive not in text:
    raise SystemExit('sensitive-context detector pattern not found')

# 3) Review batches are bounded per watchdog run, not by absolute historic iteration count.
old_iter = 'iteration="$((review_count + 1))"\nmax_review_passes="$((max_improvements + 1))"'
new_iter = 'iteration="$((review_count + 1))"\nrun_improvements=0\nmax_review_passes="$((iteration + max_improvements))"'
if old_iter in text:
    text = text.replace(old_iter, new_iter, 1)
elif new_iter not in text:
    raise SystemExit('review iteration initializer not found')

# 4) Budget exhaustion is a deferred checkpoint, not a human decision.
budget_start = '  if [[ "$(jq -r \' .kind // empty\''
# Locate structurally instead of depending on whitespace/escaping in jq.
needle = '  if [[ "$(jq -r \' .kind // empty\''
if 'Autopilot self-review: budget checkpoint; watchdog will retry later.' not in text:
    marker = '  budget="$(budget_status "${mission_id}")"\n'
    pos = text.index(marker) + len(marker)
    end_marker = '\n\n  cat "${TARGET_PATH}" > "${source_file}"'
    end = text.index(end_marker, pos)
    block = '''  if [[ "$(jq -r '.kind // empty' <<<"${budget}")" != "AI_BUDGET_STATUS" || "$(jq -r '.result.allowed // false' <<<"${budget}")" != "true" ]]; then
    echo "Autopilot self-review: budget checkpoint; watchdog will retry later."
    git checkout main >/dev/null 2>&1 || true
    exit 0
  fi'''
    text = text[:pos] + block + text[end:]

# 5) Hitting the per-run improvement cap must checkpoint, never create HUMAN_BLOCKER by itself.
if 'per-run improvement checkpoint reached' not in text:
    start = text.index('  if (( iteration > max_improvements )); then')
    end = text.index('\n\n  replacement_count=', start)
    block = '''  if (( run_improvements >= max_improvements )); then
    echo "Autopilot self-review: per-run improvement checkpoint reached; next watchdog will continue."
    git checkout main >/dev/null 2>&1 || true
    exit 0
  fi'''
    text = text[:start] + block + text[end:]

# 6) After applying the last allowed improvement in this run, checkpoint for the next watchdog.
old_tail = '''  iteration="$((iteration + 1))"
done

review_human_blocker "${request_id}" "Self-review reached its bounded iteration limit without a final LOW-risk approval." "Review the Draft PR or provide direction; the system stopped to prevent an infinite improvement loop." "${pr_url}" "${iteration}" "MEDIUM" >/dev/null
git checkout main >/dev/null 2>&1 || true
bash scripts/autopilot-worker.sh'''
new_tail = '''  run_improvements="$((run_improvements + 1))"
  iteration="$((iteration + 1))"
  if (( run_improvements >= max_improvements )); then
    echo "Autopilot self-review: improvement batch complete; leaving WAITING_REVIEW for next watchdog."
    git checkout main >/dev/null 2>&1 || true
    exit 0
  fi
done

git checkout main >/dev/null 2>&1 || true
echo "Autopilot self-review: bounded review batch complete; next watchdog will continue if needed."
exit 0'''
if old_tail in text:
    text = text.replace(old_tail, new_tail, 1)
elif new_tail not in text:
    raise SystemExit('review loop tail pattern not found')

path.write_text(text)
