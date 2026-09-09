from pathlib import Path

path = Path('scripts/autopilot-self-review.sh')
text = path.read_text()
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
path.write_text(text[:start] + new_block + text[end:])
