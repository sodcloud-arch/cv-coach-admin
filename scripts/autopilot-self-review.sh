#!/usr/bin/env bash
set -euo pipefail

EDGE_URL="${EDGE_URL:-https://fmhcansyxcsqkrivqchr.supabase.co/functions/v1/autopilot-worker-gateway}"
REVIEW_EDGE_URL="${REVIEW_EDGE_URL:-https://fmhcansyxcsqkrivqchr.supabase.co/functions/v1/autopilot-review-gateway}"
OIDC_AUDIENCE="${OIDC_AUDIENCE:-cv-coach-autopilot}"
TARGET_PATH="${AUTOPILOT_TARGET_PATH:-index.html}"

get_oidc_token() {
  curl -fsSL \
    -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" \
    "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=${OIDC_AUDIENCE}" \
    | jq -r '.value'
}

call_gateway() {
  local url="$1" payload="$2" token
  token="$(get_oidc_token)"
  curl -fsSL \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    -d "${payload}" \
    "${url}"
}

review_context() {
  local request_id="$1" payload
  payload="$(jq -nc --arg request_id "${request_id}" '{op:"review_context",request_id:$request_id}')"
  call_gateway "${REVIEW_EDGE_URL}" "${payload}"
}

budget_status() {
  local mission_id="$1" payload
  payload="$(jq -nc --arg mission_id "${mission_id}" '{op:"ai_budget_status",mission_id:$mission_id}')"
  call_gateway "${EDGE_URL}" "${payload}"
}

record_usage() {
  local request_id="$1" mission_id="$2" mission_key="$3" action_id="$4" action_key="$5" iteration="$6" pr_number="$7" response_id="$8" model="$9" input_tokens="${10}" cached_tokens="${11}" output_tokens="${12}" total_tokens="${13}" latency_ms="${14}" payload
  payload="$(jq -nc \
    --arg request_id "${request_id}" \
    --arg mission_id "${mission_id}" \
    --arg mission_key "${mission_key}" \
    --arg action_id "${action_id}" \
    --arg action_key "${action_key}" \
    --arg iteration "${iteration}" \
    --arg pr_number "${pr_number}" \
    --arg response_id "${response_id}" \
    --arg model "${model}" \
    --argjson input_tokens "${input_tokens}" \
    --argjson cached_input_tokens "${cached_tokens}" \
    --argjson output_tokens "${output_tokens}" \
    --argjson total_tokens "${total_tokens}" \
    --argjson latency_ms "${latency_ms}" \
    '{op:"record_ai_usage",response_id:$response_id,model:$model,input_tokens:$input_tokens,cached_input_tokens:$cached_input_tokens,output_tokens:$output_tokens,total_tokens:$total_tokens,latency_ms:$latency_ms,metadata:{request_id:$request_id,mission_id:$mission_id,mission_key:$mission_key,action_id:$action_id,action_key:$action_key,phase:"self_review",review_iteration:$iteration,pr_number:$pr_number}}')"
  call_gateway "${EDGE_URL}" "${payload}"
}

record_review() {
  local request_id="$1" iteration="$2" decision="$3" risk="$4" summary="$5" findings_json="$6" improvements_json="$7" response_id="$8" usage_json="$9" pr_number="${10}" payload
  payload="$(jq -nc \
    --arg request_id "${request_id}" \
    --argjson iteration "${iteration}" \
    --arg decision "${decision}" \
    --arg risk_level "${risk}" \
    --arg summary "${summary}" \
    --argjson findings "${findings_json}" \
    --argjson improvements "${improvements_json}" \
    --arg response_id "${response_id}" \
    --argjson usage "${usage_json}" \
    --arg pr_number "${pr_number}" \
    '{op:"record_ai_review",request_id:$request_id,iteration:$iteration,decision:$decision,risk_level:$risk_level,summary:$summary,findings:$findings,improvements:$improvements,response_id:$response_id,usage:$usage,metadata:{pr_number:$pr_number}}')"
  call_gateway "${REVIEW_EDGE_URL}" "${payload}"
}

review_human_blocker() {
  local request_id="$1" reason="$2" required_action="$3" pr_url="$4" iteration="$5" risk="$6" payload
  payload="$(jq -nc \
    --arg request_id "${request_id}" \
    --arg reason "${reason}" \
    --arg required_action "${required_action}" \
    --arg pr_url "${pr_url}" \
    --argjson iteration "${iteration}" \
    --arg risk_level "${risk}" \
    '{op:"review_human_blocker",request_id:$request_id,reason:$reason,required_action:$required_action,result:{pr_url:$pr_url,review_iteration:$iteration,risk_level:$risk_level}}')"
  call_gateway "${REVIEW_EDGE_URL}" "${payload}"
}

review_resolved() {
  local request_id="$1" pr_url="$2" pr_number="$3" merge_sha="$4" iteration="$5" risk="$6" payload
  payload="$(jq -nc \
    --arg request_id "${request_id}" \
    --arg pr_url "${pr_url}" \
    --arg pr_number "${pr_number}" \
    --arg merge_commit_sha "${merge_sha}" \
    --argjson iteration "${iteration}" \
    --arg risk_level "${risk}" \
    '{op:"review_resolved",request_id:$request_id,approved:true,result:{pr_url:$pr_url,pr_number:$pr_number,merge_commit_sha:$merge_commit_sha,review_source:"ai_self_review",review_iteration:$iteration,risk_level:$risk_level,self_improved:true}}')"
  call_gateway "${EDGE_URL}" "${payload}"
}

validate_worktree() {
  if [[ ! -f "${TARGET_PATH}" ]]; then
    echo "Self-review validation: missing ${TARGET_PATH}" >&2
    return 1
  fi

  if ! grep -q '<!doctype html>' "${TARGET_PATH}" || ! grep -q '<title>CV Coach' "${TARGET_PATH}" || ! grep -q '</html>' "${TARGET_PATH}"; then
    echo "Self-review validation: canonical HTML markers missing" >&2
    return 1
  fi

  python3 - "${TARGET_PATH}" <<'PY'
import pathlib, re, subprocess, sys
path = pathlib.Path(sys.argv[1])
current = path.read_text()
base_sha = subprocess.check_output(["git", "merge-base", "origin/main", "HEAD"], text=True).strip()
base = subprocess.check_output(["git", "show", f"{base_sha}:{path.as_posix()}"], text=True)
pat = re.compile(r"const BASE='([^']+)',KEY='([^']+)'")
a = pat.search(base)
b = pat.search(current)
if not a or not b or a.groups() != b.groups():
    raise SystemExit("Supabase public client identity changed")
scripts = re.findall(r'<script>(.*?)</script>', current, flags=re.S|re.I)
if not scripts:
    raise SystemExit("no inline script found")
pathlib.Path('/tmp/cv-autopilot-review-inline.js').write_text('\n'.join(scripts))
PY

  node --check /tmp/cv-autopilot-review-inline.js
  git diff --check -- "${TARGET_PATH}"

  local unexpected
  unexpected="$(git diff --name-only "$(git merge-base origin/main HEAD)" -- | grep -v "^${TARGET_PATH//./\.}$" || true)"
  if [[ -n "${unexpected}" ]]; then
    echo "Self-review validation: unexpected changed files: ${unexpected}" >&2
    return 1
  fi

  local full_diff
  full_diff="$(git diff "$(git merge-base origin/main HEAD)" -- "${TARGET_PATH}")"
  if grep -Eiq 'sk-[A-Za-z0-9_-]{20,}|sb_secret_[A-Za-z0-9_-]{20,}|service[_-]?role|SUPABASE_SERVICE_ROLE_KEY|OPENAI_API_KEY[[:space:]]*[=:]|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|eval\(|new Function\(' <<<"${full_diff}"; then
    echo "Self-review validation: forbidden privileged/secret pattern" >&2
    return 1
  fi
}

find_review_pr() {
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
}

if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  echo "Autopilot self-review: OPENAI_API_KEY unavailable; no review performed."
  exit 0
fi

pr_json="$(find_review_pr)"
if [[ -z "${pr_json}" ]]; then
  echo "Autopilot self-review: IDLE (no open Autopilot Draft PR)."
  exit 0
fi

pr_number="$(jq -r '.number' <<<"${pr_json}")"
pr_url="$(jq -r '.url' <<<"${pr_json}")"
pr_title="$(jq -r '.title' <<<"${pr_json}")"
pr_body="$(jq -r '.body // ""' <<<"${pr_json}")"
head_ref="$(jq -r '.headRefName' <<<"${pr_json}")"
is_draft="$(jq -r '.isDraft' <<<"${pr_json}")"
request_id="$(printf '%s\n' "${pr_body}" | sed -n 's/^AUTOPILOT_EXTERNAL_REQUEST_ID: //p' | head -n 1)"

if [[ -z "${request_id}" ]]; then
  echo "Autopilot self-review: PR ${pr_number} has no request marker; skipping."
  exit 0
fi

ctx_response="$(review_context "${request_id}")"
if [[ "$(jq -r '.kind // empty' <<<"${ctx_response}")" != "AI_REVIEW_CONTEXT" ]]; then
  echo "Autopilot self-review: unable to load review context: ${ctx_response}" >&2
  exit 1
fi
ctx="$(jq -c '.result' <<<"${ctx_response}")"

if [[ "$(jq -r '.request_status' <<<"${ctx}")" != "WAITING_REVIEW" ]]; then
  echo "Autopilot self-review: request is not WAITING_REVIEW; skipping."
  exit 0
fi

if [[ "$(jq -r '.self_review_enabled' <<<"${ctx}")" != "true" ]]; then
  echo "Autopilot self-review: disabled by policy."
  exit 0
fi

mission_id="$(jq -r '.mission_id' <<<"${ctx}")"
mission_key="$(jq -r '.mission_key' <<<"${ctx}")"
action_id="$(jq -r '.action_id' <<<"${ctx}")"
action_key="$(jq -r '.action_key' <<<"${ctx}")"
action_title="$(jq -r '.action_title' <<<"${ctx}")"
action_instructions="$(jq -r '.action_instructions // ""' <<<"${ctx}")"
request_payload="$(jq -c '.request_payload' <<<"${ctx}")"
action_payload="$(jq -c '.action_payload' <<<"${ctx}")"
review_count="$(jq -r '.review_count // 0' <<<"${ctx}")"
max_improvements="$(jq -r '.max_self_review_iterations // 2' <<<"${ctx}")"
auto_merge="$(jq -r '.auto_merge_low_risk' <<<"${ctx}")"
model="$(jq -r '.model // "gpt-5.6-luna"' <<<"${ctx}")"
policy_max_tokens="$(jq -r '.max_output_tokens // 2500' <<<"${ctx}")"
review_max_tokens=4000
if (( policy_max_tokens < review_max_tokens )); then review_max_tokens="${policy_max_tokens}"; fi

context_text="${action_title} ${action_instructions} ${request_payload} ${action_payload}"
sensitive=false
if grep -Eiq '(password|contraseñ|credential|credencial|api[ _-]?key|payment|pago|billing|factur|delete|borrar|eliminar|drop table|rls|permission|permiso|service[_-]?role|security|seguridad|migration|migración|production data|datos de producción|github[ _-]?secret|crear.{0,40}(secret|secreto)|modificar.{0,40}(secret|secreto)|rotar.{0,40}(secret|secreto)|eliminar.{0,40}(secret|secreto))' <<<"${context_text}"; then
  sensitive=true
fi

git fetch origin main "${head_ref}"
git checkout -B "${head_ref}" FETCH_HEAD
# FETCH_HEAD points to the last fetched ref; explicitly reset from remote PR head.
git fetch origin "${head_ref}"
git reset --hard FETCH_HEAD

git config user.name "cv-coach-autopilot[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

schema='{
  "type":"object",
  "additionalProperties":false,
  "required":["decision","risk_level","summary","findings","improvements","replacements","human_action"],
  "properties":{
    "decision":{"type":"string","enum":["APPROVE","IMPROVE","HUMAN_ESCALATION"]},
    "risk_level":{"type":"string","enum":["LOW","MEDIUM","HIGH"]},
    "summary":{"type":"string","maxLength":1200},
    "findings":{"type":"array","maxItems":12,"items":{"type":"string","maxLength":800}},
    "improvements":{"type":"array","maxItems":12,"items":{"type":"string","maxLength":800}},
    "replacements":{"type":"array","maxItems":20,"items":{"type":"object","additionalProperties":false,"required":["old_text","new_text"],"properties":{"old_text":{"type":"string","minLength":1,"maxLength":12000},"new_text":{"type":"string","maxLength":16000}}}},
    "human_action":{"type":"string","maxLength":1600}
  }
}'

review_system='You are the independent self-review layer for CV Coach Autopilot. Your job is to critique work produced by another AI and improve it before Camilo is asked to review anything. Do not rubber-stamp. Compare the current branch against the original task. Look for correctness bugs, regressions, incomplete behavior, UX issues, security risks, accidental scope expansion, maintainability problems and simpler solutions. If a meaningful safe improvement is possible within the requested scope, choose IMPROVE and provide the smallest exact old_text→new_text replacements copied verbatim from CURRENT BRANCH index.html. If the proposal is already strong, complete, low-risk and needs no meaningful improvement, choose APPROVE with LOW risk and no replacements. MEDIUM risk should normally be improved until LOW; if it cannot be reduced safely, choose HUMAN_ESCALATION. HIGH risk always requires HUMAN_ESCALATION. HUMAN_ESCALATION is only for genuinely human decisions or sensitive operations such as credentials, payments, legal decisions, destructive data changes, access-control changes, irreversible production actions, or unresolved ambiguity. Never output or request secrets. Never weaken authentication or security controls. Do not broaden product scope during review. Do not claim tests ran; the deterministic runner validates after your response.'

body_file="$(mktemp)"
response_file="$(mktemp)"
review_file="$(mktemp)"
source_file="$(mktemp)"
diff_file="$(mktemp)"
review_input_file="$(mktemp)"
trap 'rm -f "${body_file}" "${response_file}" "${review_file}" "${source_file}" "${diff_file}" "${review_input_file}" /tmp/cv-autopilot-review-inline.js "${TARGET_PATH}.self-review-backup"' EXIT

iteration="$((review_count + 1))"
max_review_passes="$((max_improvements + 1))"

while (( iteration <= max_review_passes )); do
  budget="$(budget_status "${mission_id}")"
  if [[ "$(jq -r '.kind // empty' <<<"${budget}")" != "AI_BUDGET_STATUS" || "$(jq -r '.result.allowed // false' <<<"${budget}")" != "true" ]]; then
    reason="Autopilot self-review stopped because the AI budget guard does not allow another review call."
    review_human_blocker "${request_id}" "${reason}" "Wait for the budget window to reset or intentionally adjust the Autopilot AI policy before closing the blocker." "${pr_url}" "${iteration}" "MEDIUM" >/dev/null
    git checkout main >/dev/null 2>&1 || true
    bash scripts/autopilot-worker.sh
    exit 0
  fi

  cat "${TARGET_PATH}" > "${source_file}"
  git diff --no-ext-diff --unified=0 origin/main...HEAD -- "${TARGET_PATH}" > "${diff_file}"
  jq -nr \
    --arg mission_key "${mission_key}" \
    --arg action_key "${action_key}" \
    --arg action_title "${action_title}" \
    --arg instructions "${action_instructions}" \
    --arg request_payload "${request_payload}" \
    --arg action_payload "${action_payload}" \
    --arg pr_title "${pr_title}" \
    --rawfile diff "${diff_file}" \
    --rawfile source "${source_file}" \
    '"MISSION: "+$mission_key+"\nACTION: "+$action_key+"\nTITLE: "+$action_title+"\nORIGINAL INSTRUCTIONS:\n"+$instructions+"\nREQUEST PAYLOAD:\n"+$request_payload+"\nACTION PAYLOAD:\n"+$action_payload+"\nPR TITLE: "+$pr_title+"\n\nCURRENT DIFF VS MAIN:\n"+$diff+"\n\nCURRENT BRANCH index.html:\n"+$source' \
    > "${review_input_file}"

  jq -n \
    --arg model "${model}" \
    --arg instructions "${review_system}" \
    --rawfile input "${review_input_file}" \
    --argjson max_output_tokens "${review_max_tokens}" \
    --argjson schema "${schema}" \
    '{model:$model,instructions:$instructions,input:$input,store:false,max_output_tokens:$max_output_tokens,text:{format:{type:"json_schema",name:"cv_autopilot_self_review_v1",strict:true,schema:$schema}}}' \
    > "${body_file}"

  started_ms="$(date +%s%3N)"
  http_code="$(curl -sS -o "${response_file}" -w '%{http_code}' \
    https://api.openai.com/v1/responses \
    -H "Authorization: Bearer ${OPENAI_API_KEY}" \
    -H "Content-Type: application/json" \
    -d @"${body_file}")"
  finished_ms="$(date +%s%3N)"
  latency_ms="$((finished_ms-started_ms))"

  if [[ ! "${http_code}" =~ ^2 ]]; then
    echo "Autopilot self-review: OpenAI HTTP ${http_code}; leaving Draft PR for watchdog retry." >&2
    exit 0
  fi

  response_id="$(jq -r '.id // empty' "${response_file}")"
  input_tokens="$(jq -r '.usage.input_tokens // 0' "${response_file}")"
  cached_tokens="$(jq -r '.usage.input_tokens_details.cached_tokens // 0' "${response_file}")"
  output_tokens="$(jq -r '.usage.output_tokens // 0' "${response_file}")"
  total_tokens="$(jq -r '.usage.total_tokens // 0' "${response_file}")"

  usage_ack="$(record_usage "${request_id}" "${mission_id}" "${mission_key}" "${action_id}" "${action_key}" "${iteration}" "${pr_number}" "${response_id}" "${model}" "${input_tokens}" "${cached_tokens}" "${output_tokens}" "${total_tokens}" "${latency_ms}")"
  if [[ "$(jq -r '.kind // empty' <<<"${usage_ack}")" != "AI_USAGE_RECORDED" ]]; then
    review_human_blocker "${request_id}" "Self-review usage could not be audited safely." "Repair AI usage telemetry before resuming this Draft PR." "${pr_url}" "${iteration}" "MEDIUM" >/dev/null
    git checkout main >/dev/null 2>&1 || true
    bash scripts/autopilot-worker.sh
    exit 0
  fi

  jq -r '[.output[]?.content[]? | select(.type=="output_text") | .text][0] // .output_text // empty' "${response_file}" > "${review_file}"
  if [[ ! -s "${review_file}" ]] || ! jq -e . "${review_file}" >/dev/null 2>&1; then
    echo "Autopilot self-review: invalid structured output; leaving PR for next watchdog pass." >&2
    exit 0
  fi

  decision="$(jq -r '.decision' "${review_file}")"
  risk="$(jq -r '.risk_level' "${review_file}")"
  summary="$(jq -r '.summary' "${review_file}")"
  findings_json="$(jq -c '.findings' "${review_file}")"
  improvements_json="$(jq -c '.improvements' "${review_file}")"
  human_action="$(jq -r '.human_action // ""' "${review_file}")"
  usage_json="$(jq -nc --arg model "${model}" --argjson input_tokens "${input_tokens}" --argjson cached_tokens "${cached_tokens}" --argjson output_tokens "${output_tokens}" --argjson total_tokens "${total_tokens}" --argjson latency_ms "${latency_ms}" '{model:$model,input_tokens:$input_tokens,cached_input_tokens:$cached_tokens,output_tokens:$output_tokens,total_tokens:$total_tokens,latency_ms:$latency_ms}')"

  record_review "${request_id}" "${iteration}" "${decision}" "${risk}" "${summary}" "${findings_json}" "${improvements_json}" "${response_id}" "${usage_json}" "${pr_number}" >/dev/null

  if [[ "${decision}" == "HUMAN_ESCALATION" || "${risk}" == "HIGH" ]]; then
    reason="AI self-review escalated this Draft PR: ${summary}"
    review_human_blocker "${request_id}" "${reason}" "${human_action:-Review the Draft PR and decide how to proceed.}" "${pr_url}" "${iteration}" "${risk}" >/dev/null
    git checkout main >/dev/null 2>&1 || true
    bash scripts/autopilot-worker.sh
    echo "Autopilot self-review: HUMAN_BLOCKER"
    exit 0
  fi

  if [[ "${decision}" == "APPROVE" ]]; then
    if [[ "${risk}" != "LOW" || "${sensitive}" == "true" || "${auto_merge}" != "true" ]]; then
      reason="AI self-review reached approval but automatic merge is not permitted for this risk/context. ${summary}"
      review_human_blocker "${request_id}" "${reason}" "Review the Draft PR. It was self-reviewed but policy requires a human decision for this context." "${pr_url}" "${iteration}" "${risk}" >/dev/null
      git checkout main >/dev/null 2>&1 || true
      bash scripts/autopilot-worker.sh
      echo "Autopilot self-review: HUMAN_BLOCKER (policy gate)"
      exit 0
    fi

    if ! validate_worktree; then
      review_human_blocker "${request_id}" "Deterministic validation failed after AI self-review approval." "Inspect the Draft PR validation failure before resuming." "${pr_url}" "${iteration}" "MEDIUM" >/dev/null
      git checkout main >/dev/null 2>&1 || true
      bash scripts/autopilot-worker.sh
      exit 0
    fi

    if [[ "${is_draft}" == "true" ]]; then gh pr ready "${pr_number}" >/dev/null; fi
    if ! gh pr merge "${pr_number}" --squash --delete-branch; then
      review_human_blocker "${request_id}" "AI self-review approved a LOW-risk change, but GitHub blocked the automatic merge." "Inspect required checks or branch protection for PR #${pr_number}, then close the generated blocker." "${pr_url}" "${iteration}" "LOW" >/dev/null
      git checkout main >/dev/null 2>&1 || true
      bash scripts/autopilot-worker.sh
      exit 0
    fi

    merge_sha="$(gh pr view "${pr_number}" --json mergeCommit --jq '.mergeCommit.oid // ""' 2>/dev/null || true)"
    review_resolved "${request_id}" "${pr_url}" "${pr_number}" "${merge_sha}" "${iteration}" "LOW" >/dev/null
    git checkout main >/dev/null 2>&1 || true
    git pull --ff-only origin main >/dev/null 2>&1 || true
    bash scripts/autopilot-worker.sh
    echo "Autopilot self-review: AUTO_APPROVED_AND_MERGED PR #${pr_number}"
    exit 0
  fi

  if [[ "${decision}" != "IMPROVE" ]]; then
    echo "Autopilot self-review: unknown decision ${decision}" >&2
    exit 1
  fi

  if (( iteration > max_improvements )); then
    review_human_blocker "${request_id}" "Self-review did not converge to a LOW-risk approval within ${max_improvements} improvement cycles." "Review the Draft PR or provide direction; the bounded self-improvement loop intentionally stopped." "${pr_url}" "${iteration}" "${risk}" >/dev/null
    git checkout main >/dev/null 2>&1 || true
    bash scripts/autopilot-worker.sh
    exit 0
  fi

  replacement_count="$(jq '.replacements | length' "${review_file}")"
  if (( replacement_count < 1 || replacement_count > 20 )); then
    review_human_blocker "${request_id}" "Self-review requested IMPROVE but did not provide a valid bounded patch." "Review the Draft PR or rerun after adjusting the task." "${pr_url}" "${iteration}" "MEDIUM" >/dev/null
    git checkout main >/dev/null 2>&1 || true
    bash scripts/autopilot-worker.sh
    exit 0
  fi

  if jq -r '.replacements[].new_text' "${review_file}" | grep -Eiq 'sk-[A-Za-z0-9_-]{20,}|sb_secret_[A-Za-z0-9_-]{20,}|service[_-]?role|SUPABASE_SERVICE_ROLE_KEY|OPENAI_API_KEY[[:space:]]*[=:]|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|eval\(|new Function\('; then
    review_human_blocker "${request_id}" "Self-review improvement was rejected by the privileged-code/secret guard." "Inspect the proposed improvement before resuming." "${pr_url}" "${iteration}" "HIGH" >/dev/null
    git checkout main >/dev/null 2>&1 || true
    bash scripts/autopilot-worker.sh
    exit 0
  fi

  cp "${TARGET_PATH}" "${TARGET_PATH}.self-review-backup"
  if ! python3 - "${TARGET_PATH}" "${review_file}" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
review = json.loads(pathlib.Path(sys.argv[2]).read_text())
text = path.read_text()
for i, repl in enumerate(review["replacements"], 1):
    old = repl["old_text"]
    new = repl["new_text"]
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"review replacement {i}: old_text occurs {count} times, expected 1")
    text = text.replace(old, new, 1)
path.write_text(text)
PY
  then
    mv "${TARGET_PATH}.self-review-backup" "${TARGET_PATH}"
    review_human_blocker "${request_id}" "Self-review exact replacement validation failed." "Inspect the Draft PR or let the next task provide more specific context." "${pr_url}" "${iteration}" "MEDIUM" >/dev/null
    git checkout main >/dev/null 2>&1 || true
    bash scripts/autopilot-worker.sh
    exit 0
  fi

  if ! validate_worktree; then
    mv "${TARGET_PATH}.self-review-backup" "${TARGET_PATH}"
    review_human_blocker "${request_id}" "Self-review improvement failed deterministic validation and was rolled back." "Inspect the Draft PR and validation context before resuming." "${pr_url}" "${iteration}" "MEDIUM" >/dev/null
    git checkout main >/dev/null 2>&1 || true
    bash scripts/autopilot-worker.sh
    exit 0
  fi
  rm -f "${TARGET_PATH}.self-review-backup"

  git add "${TARGET_PATH}"
  if git diff --cached --quiet; then
    review_human_blocker "${request_id}" "Self-review claimed an improvement but produced no actual source change." "Review the Draft PR or rerun with clearer instructions." "${pr_url}" "${iteration}" "MEDIUM" >/dev/null
    git checkout main >/dev/null 2>&1 || true
    bash scripts/autopilot-worker.sh
    exit 0
  fi

  git commit -m "autopilot: self-review improvement ${iteration} - ${action_title}"
  git push origin "HEAD:${head_ref}"

  improvements_text="$(jq -r '.improvements[]? | "- " + .' "${review_file}")"
  gh pr comment "${pr_number}" --body "🤖 **Autopilot self-review — mejora ${iteration}**\n\n${summary}\n\n${improvements_text}\n\nLa rama fue corregida y será revisada nuevamente de forma automática." >/dev/null || true

  iteration="$((iteration + 1))"
done

review_human_blocker "${request_id}" "Self-review reached its bounded iteration limit without a final LOW-risk approval." "Review the Draft PR or provide direction; the system stopped to prevent an infinite improvement loop." "${pr_url}" "${iteration}" "MEDIUM" >/dev/null
git checkout main >/dev/null 2>&1 || true
bash scripts/autopilot-worker.sh
