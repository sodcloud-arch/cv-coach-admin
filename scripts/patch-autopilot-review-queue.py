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
old = "if grep -Eiq '(password|contraseñ|credential|credencial|secret|secreto|api[ _-]?key|payment|pago|billing|factur|delete|borrar|eliminar|drop table|rls|permission|permiso|service[_-]?role|security|seguridad|migration|migración|production data|datos de producción)' <<<\"${context_text}\"; then"
new = "if grep -Eiq '(password|contraseñ|credential|credencial|api[ _-]?key|payment|pago|billing|factur|delete|borrar|eliminar|drop table|rls|permission|permiso|service[_-]?role|security|seguridad|migration|migración|production data|datos de producción|github[ _-]?secret|crear.{0,40}(secret|secreto)|modificar.{0,40}(secret|secreto)|rotar.{0,40}(secret|secreto)|eliminar.{0,40}(secret|secreto))' <<<\"${context_text}\"; then"
if old in text:
    text = text.replace(old, new, 1)
elif new not in text:
    raise SystemExit('sensitive-context detector pattern not found')

path.write_text(text)
