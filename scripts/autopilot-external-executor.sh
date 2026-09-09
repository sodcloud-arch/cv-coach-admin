#!/usr/bin/env bash
set -euo pipefail

EDGE_URL="${EDGE_URL:-https://fmhcansyxcsqkrivqchr.supabase.co/functions/v1/autopilot-worker-gateway}"
OIDC_AUDIENCE="${OIDC_AUDIENCE:-cv-coach-autopilot}"
OPENAI_MODEL="${OPENAI_MODEL:-gpt-5.6-luna}"
TARGET_PATH="${AUTOPILOT_TARGET_PATH:-index.html}"

get_oidc_token() {
  curl -fsSL \
    -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" \
    "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=${OIDC_AUDIENCE}" \
    | jq -r '.value'
}

call_edge() {
  local token="$1"
  local payload="$2"
  curl -fsSL \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    -d "${payload}" \
    "${EDGE_URL}"
}

claim_external() {
  local token
  token="$(get_oidc_token)"
  call_edge "${token}" '{"op":"claim_external","provider":"OPENAI"}'
}

ai_budget_status() {
  local mission_id="$1" token payload
  token="$(get_oidc_token)"
  payload="$(jq -nc --arg mission_id "${mission_id}" '{op:"ai_budget_status",mission_id:$mission_id}')"
  call_edge "${token}" "${payload}"
}

record_ai_usage() {
  local request_id="$1" mission_id="$2" mission_key="$3" action_id="$4" action_key="$5" response_id="$6" model="$7" input_tokens="$8" cached_tokens="$9" output_tokens="${10}" total_tokens="${11}" latency_ms="${12}" token payload
  token="$(get_oidc_token)"
  payload="$(jq -nc \
    --arg request_id "${request_id}" \
    --arg mission_id "${mission_id}" \
    --arg mission_key "${mission_key}" \
    --arg action_id "${action_id}" \
    --arg action_key "${action_key}" \
    --arg response_id "${response_id}" \
    --arg model "${model}" \
    --argjson input_tokens "${input_tokens}" \
    --argjson cached_input_tokens "${cached_tokens}" \
    --argjson output_tokens "${output_tokens}" \
    --argjson total_tokens "${total_tokens}" \
    --argjson latency_ms "${latency_ms}" \
    '{op:"record_ai_usage",response_id:$response_id,model:$model,input_tokens:$input_tokens,cached_input_tokens:$cached_input_tokens,output_tokens:$output_tokens,total_tokens:$total_tokens,latency_ms:$latency_ms,metadata:{request_id:$request_id,mission_id:$mission_id,mission_key:$mission_key,action_id:$action_id,action_key:$action_key}}')"
  call_edge "${token}" "${payload}"
}

external_retry() {
  local request_id="$1" error="$2" retry_after="${3:-60}" token payload
  token="$(get_oidc_token)"
  payload="$(jq -nc --arg request_id "${request_id}" --arg error "${error}" --argjson retry_after_seconds "${retry_after}" '{op:"external_retry",request_id:$request_id,error:$error,retry_after_seconds:$retry_after_seconds}')"
  call_edge "${token}" "${payload}" >/dev/null
}

external_human_blocker() {
  local request_id="$1" reason="$2" required_action="$3" token payload
  token="$(get_oidc_token)"
  payload="$(jq -nc --arg request_id "${request_id}" --arg reason "${reason}" --arg required_action "${required_action}" '{op:"external_human_blocker",request_id:$request_id,reason:$reason,required_action:$required_action,result:{executor:"github-actions-openai",automatic:true}}')"
  call_edge "${token}" "${payload}" >/dev/null
}

external_succeeded() {
  local request_id="$1" result_json="$2" token payload
  token="$(get_oidc_token)"
  payload="$(jq -nc --arg request_id "${request_id}" --argjson result "${result_json}" '{op:"external_succeeded",request_id:$request_id,result:$result}')"
  call_edge "${token}" "${payload}" >/dev/null
}

proposal_created() {
  local request_id="$1" result_json="$2" token payload
  token="$(get_oidc_token)"
  payload="$(jq -nc --arg request_id "${request_id}" --argjson result "${result_json}" '{op:"proposal_created",request_id:$request_id,result:$result}')"
  call_edge "${token}" "${payload}" >/dev/null
}

response="$(claim_external)"
kind="$(jq -r '.kind // "ERROR"' <<<"${response}")"

if [[ "${kind}" == "EXTERNAL_IDLE" ]]; then
  echo "Autopilot external executor: IDLE"
  exit 0
fi

if [[ "${kind}" != "EXTERNAL_REQUEST" ]]; then
  echo "Unexpected claim response: ${response}" >&2
  exit 1
fi

request_id="$(jq -r '.request.request_id' <<<"${response}")"
mission_id="$(jq -r '.request.mission_id' <<<"${response}")"
action_id="$(jq -r '.request.action_id' <<<"${response}")"
mission_key="$(jq -r '.request.mission_key' <<<"${response}")"
action_key="$(jq -r '.request.action_key' <<<"${response}")"
action_type="$(jq -r '.request.action_type' <<<"${response}")"
title="$(jq -r '.request.title' <<<"${response}")"
instructions="$(jq -r '.request.instructions' <<<"${response}")"
request_payload="$(jq -c '.request.request_payload' <<<"${response}")"
action_payload="$(jq -c '.request.action_payload' <<<"${response}")"

payload_target="$(jq -r '.file // .target_path // empty' <<<"${action_payload}")"
if [[ -n "${payload_target}" ]]; then
  if [[ "${payload_target}" == /* || "${payload_target}" == *".."* || ! "${payload_target}" =~ ^[A-Za-z0-9._/-]+$ ]]; then
    external_human_blocker "${request_id}" "Action payload contains an unsafe target path." "Use a canonical repository-relative file path without parent traversal."
    bash scripts/autopilot-worker.sh
    exit 0
  fi
  TARGET_PATH="${payload_target}"
fi

echo "Autopilot external request claimed: ${mission_key}/${action_key} (${request_id}) target=${TARGET_PATH}"

if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  external_human_blocker \
    "${request_id}" \
    "OPENAI_API_KEY is not configured for the CV Coach Autopilot executor." \
    "In GitHub open Settings → Secrets and variables → Actions → New repository secret. Create OPENAI_API_KEY with the OpenAI API key. Do not paste the key into ChatGPT. Then close this blocker Issue to resume automatically."
  echo "Autopilot external executor: HUMAN_BLOCKER (missing OPENAI_API_KEY)"
  bash scripts/autopilot-worker.sh
  exit 0
fi

budget="$(ai_budget_status "${mission_id}")"
if [[ "$(jq -r '.kind // empty' <<<"${budget}")" != "AI_BUDGET_STATUS" ]]; then
  external_human_blocker "${request_id}" "AI budget guard could not be verified before the OpenAI call." "Review the Autopilot AI budget gateway before resuming."
  bash scripts/autopilot-worker.sh
  exit 0
fi

allowed="$(jq -r '.result.allowed' <<<"${budget}")"
budget_reason="$(jq -r '.result.reason' <<<"${budget}")"
OPENAI_MODEL="$(jq -r '.result.model // "gpt-5.6-luna"' <<<"${budget}")"
MAX_OUTPUT_TOKENS="$(jq -r '.result.max_output_tokens // 2500' <<<"${budget}")"

if [[ "${allowed}" != "true" ]]; then
  spent="$(jq -r '.result.spent_today_usd' <<<"${budget}")"
  daily_budget="$(jq -r '.result.daily_budget_usd' <<<"${budget}")"
  external_human_blocker \
    "${request_id}" \
    "Autopilot AI budget guard stopped the request: ${budget_reason}. Spent today: USD ${spent}; daily budget: USD ${daily_budget}." \
    "Wait for the daily budget window to reset, or intentionally raise the Autopilot AI policy in Supabase before closing this blocker."
  echo "Autopilot external executor: HUMAN_BLOCKER (${budget_reason})"
  bash scripts/autopilot-worker.sh
  exit 0
fi

if [[ ! -f "${TARGET_PATH}" ]]; then
  external_human_blocker "${request_id}" "Target source file ${TARGET_PATH} does not exist." "Restore or identify the canonical CV Coach Admin source before continuing."
  bash scripts/autopilot-worker.sh
  exit 0
fi

source_text="$(cat "${TARGET_PATH}")"
if (( ${#source_text} > 300000 )); then
  external_human_blocker "${request_id}" "Target source is larger than the safe Autopilot context limit." "Split or modularize the source before automated AI editing."
  bash scripts/autopilot-worker.sh
  exit 0
fi

schema='{
  "type":"object",
  "additionalProperties":false,
  "required":["decision","summary","reason","replacements","validation_notes","human_action"],
  "properties":{
    "decision":{"type":"string","enum":["PATCH","NO_CHANGE","HUMAN_BLOCKER"]},
    "summary":{"type":"string","maxLength":1200},
    "reason":{"type":"string","maxLength":2000},
    "replacements":{"type":"array","maxItems":20,"items":{"type":"object","additionalProperties":false,"required":["old_text","new_text"],"properties":{"old_text":{"type":"string","minLength":1,"maxLength":12000},"new_text":{"type":"string","maxLength":16000}}}},
    "validation_notes":{"type":"array","maxItems":12,"items":{"type":"string","maxLength":800}},
    "human_action":{"type":"string","maxLength":1600}
  }
}'

system_instructions='You are the constrained technical proposal layer for CV Coach Autopilot. SEARCH BEFORE CREATE. Preserve existing behavior and production data. You do not have GitHub credentials and must never request, reveal, infer, or output secrets. The only code target is the canonical repository-relative TARGET_PATH selected from the trusted action payload; do not edit any other file. If a safe exact-text patch cannot be produced, return HUMAN_BLOCKER or NO_CHANGE. For PATCH, return only the smallest exact old_text→new_text substitutions required. Every old_text must be copied verbatim from the provided source and be specific enough to occur exactly once. Never modify authentication to weaken access control, never insert API secrets, service-role keys, passwords, remote scripts, eval, Function constructors, or credential exfiltration. Do not claim tests ran; the deterministic runner performs validation after your proposal.'

input_text="$(jq -nr \
  --arg mission_key "${mission_key}" \
  --arg action_key "${action_key}" \
  --arg action_type "${action_type}" \
  --arg title "${title}" \
  --arg instructions "${instructions}" \
  --arg request_payload "${request_payload}" \
  --arg action_payload "${action_payload}" \
  --rawfile source "${TARGET_PATH}" \
  '"MISSION: "+$mission_key+"\nACTION: "+$action_key+" ("+$action_type+")\nTITLE: "+$title+"\nINSTRUCTIONS:\n"+$instructions+"\nREQUEST PAYLOAD:\n"+$request_payload+"\nACTION PAYLOAD:\n"+$action_payload+"\n\nCURRENT TARGET SOURCE:\n"+$source')"

input_file="$(mktemp)"
printf '%s' "${input_text}" > "${input_file}"
body_file="$(mktemp)"
response_file="$(mktemp)"
proposal_file="$(mktemp)"
trap 'rm -f "${input_file}" "${body_file}" "${response_file}" "${proposal_file}" /tmp/cv-autopilot-inline.js' EXIT

jq -n \
  --arg model "${OPENAI_MODEL}" \
  --arg instructions "${system_instructions}" \
  --rawfile input "${input_file}" \
  --argjson max_output_tokens "${MAX_OUTPUT_TOKENS}" \
  --argjson schema "${schema}" \
  '{model:$model,instructions:$instructions,input:$input,store:false,max_output_tokens:$max_output_tokens,text:{format:{type:"json_schema",name:"cv_autopilot_patch_v1",strict:true,schema:$schema}}}' \
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
  api_error="$(jq -r '.error.message // "OpenAI request failed"' "${response_file}" 2>/dev/null || echo 'OpenAI request failed')"
  external_retry "${request_id}" "OpenAI HTTP ${http_code}: ${api_error}" 300
  echo "Autopilot external executor: RETRY (${http_code})"
  exit 0
fi

response_id="$(jq -r '.id // empty' "${response_file}")"
input_tokens="$(jq -r '.usage.input_tokens // 0' "${response_file}")"
cached_tokens="$(jq -r '.usage.input_tokens_details.cached_tokens // 0' "${response_file}")"
output_tokens="$(jq -r '.usage.output_tokens // 0' "${response_file}")"
total_tokens="$(jq -r '.usage.total_tokens // 0' "${response_file}")"

usage_ack="$(record_ai_usage "${request_id}" "${mission_id}" "${mission_key}" "${action_id}" "${action_key}" "${response_id}" "${OPENAI_MODEL}" "${input_tokens}" "${cached_tokens}" "${output_tokens}" "${total_tokens}" "${latency_ms}")" || {
  external_human_blocker "${request_id}" "OpenAI responded, but AI usage telemetry could not be persisted safely." "Repair the Autopilot AI usage telemetry before resuming to avoid uncontrolled spend."
  bash scripts/autopilot-worker.sh
  exit 0
}
if [[ "$(jq -r '.kind // empty' <<<"${usage_ack}")" != "AI_USAGE_RECORDED" ]]; then
  external_human_blocker "${request_id}" "OpenAI responded, but AI usage telemetry was not acknowledged." "Repair the Autopilot AI usage telemetry before resuming to avoid uncontrolled spend."
  bash scripts/autopilot-worker.sh
  exit 0
fi

jq -r '[.output[]?.content[]? | select(.type=="output_text") | .text][0] // .output_text // empty' "${response_file}" > "${proposal_file}"

if [[ ! -s "${proposal_file}" ]] || ! jq -e . "${proposal_file}" >/dev/null 2>&1; then
  external_retry "${request_id}" "OpenAI returned no valid structured output" 30
  echo "Autopilot external executor: RETRY (invalid structured output)"
  exit 0
fi

decision="$(jq -r '.decision' "${proposal_file}")"
summary="$(jq -r '.summary' "${proposal_file}")"
reason="$(jq -r '.reason' "${proposal_file}")"
human_action="$(jq -r '.human_action' "${proposal_file}")"

usage_json="$(jq -nc \
  --arg response_id "${response_id}" \
  --arg model "${OPENAI_MODEL}" \
  --argjson input_tokens "${input_tokens}" \
  --argjson cached_tokens "${cached_tokens}" \
  --argjson output_tokens "${output_tokens}" \
  --argjson total_tokens "${total_tokens}" \
  --argjson latency_ms "${latency_ms}" \
  '{response_id:$response_id,model:$model,input_tokens:$input_tokens,cached_input_tokens:$cached_tokens,output_tokens:$output_tokens,total_tokens:$total_tokens,latency_ms:$latency_ms}')"

case "${decision}" in
  HUMAN_BLOCKER)
    external_human_blocker "${request_id}" "${reason}" "${human_action:-Human review required by intelligent executor.}"
    bash scripts/autopilot-worker.sh
    echo "Autopilot external executor: HUMAN_BLOCKER"
    ;;

  NO_CHANGE)
    result="$(jq -nc --arg summary "${summary}" --arg reason "${reason}" --argjson usage "${usage_json}" '{decision:"NO_CHANGE",summary:$summary,reason:$reason,usage:$usage,executor:"github-actions-openai"}')"
    external_succeeded "${request_id}" "${result}"
    echo "Autopilot external executor: SUCCEEDED (NO_CHANGE)"
    ;;

  PATCH)
    replacement_count="$(jq '.replacements | length' "${proposal_file}")"
    if (( replacement_count < 1 || replacement_count > 20 )); then
      external_retry "${request_id}" "PATCH contained invalid replacement count: ${replacement_count}" 15
      exit 0
    fi

    cp "${TARGET_PATH}" "${TARGET_PATH}.autopilot-backup"
    if ! python3 - "${TARGET_PATH}" "${proposal_file}" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
proposal = json.loads(pathlib.Path(sys.argv[2]).read_text())
text = path.read_text()
for i, repl in enumerate(proposal["replacements"], 1):
    old = repl["old_text"]
    new = repl["new_text"]
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"replacement {i}: old_text occurs {count} times, expected exactly 1")
    text = text.replace(old, new, 1)
path.write_text(text)
PY
    then
      mv "${TARGET_PATH}.autopilot-backup" "${TARGET_PATH}"
      external_retry "${request_id}" "Deterministic replacement validation failed" 15
      exit 0
    fi

    original_size="$(wc -c < "${TARGET_PATH}.autopilot-backup")"
    new_size="$(wc -c < "${TARGET_PATH}")"
    max_size="$((original_size + original_size/2 + 20000))"
    if (( new_size > max_size )); then
      mv "${TARGET_PATH}.autopilot-backup" "${TARGET_PATH}"
      external_retry "${request_id}" "Patch rejected: resulting file grew beyond safety threshold" 30
      exit 0
    fi

    target_kind="text"
    case "${TARGET_PATH}" in
      *.html|*.htm) target_kind="html" ;;
      *.sh) target_kind="shell" ;;
      *.js|*.mjs|*.cjs) target_kind="javascript" ;;
      *.json|*.webmanifest) target_kind="json" ;;
    esac

    validation_error=""
    case "${target_kind}" in
      html)
        if ! grep -q '<!doctype html>' "${TARGET_PATH}" || ! grep -q '<title>CV Coach' "${TARGET_PATH}" || ! grep -q '</html>' "${TARGET_PATH}"; then
          validation_error="Patch rejected: canonical HTML markers missing"
        elif ! python3 - "${TARGET_PATH}" <<'PYHTML'
import pathlib, re, sys
text = pathlib.Path(sys.argv[1]).read_text()
scripts = re.findall(r'<script>(.*?)</script>', text, flags=re.S|re.I)
if not scripts:
    raise SystemExit('no inline script found')
pathlib.Path('/tmp/cv-autopilot-inline.js').write_text('\n'.join(scripts))
PYHTML
        then
          validation_error="Patch rejected: inline JavaScript extraction failed"
        elif ! node --check /tmp/cv-autopilot-inline.js; then
          validation_error="Patch rejected: inline JavaScript syntax invalid"
        fi
        ;;
      shell)
        if ! bash -n "${TARGET_PATH}"; then
          validation_error="Patch rejected: shell syntax invalid"
        fi
        ;;
      javascript)
        if ! node --check "${TARGET_PATH}"; then
          validation_error="Patch rejected: JavaScript syntax invalid"
        fi
        ;;
      json)
        if ! jq -e . "${TARGET_PATH}" >/dev/null; then
          validation_error="Patch rejected: JSON syntax invalid"
        fi
        ;;
      text)
        ;;
    esac

    if [[ -n "${validation_error}" ]]; then
      mv "${TARGET_PATH}.autopilot-backup" "${TARGET_PATH}"
      external_retry "${request_id}" "${validation_error}" 30
      exit 0
    fi

    if ! git diff --check -- "${TARGET_PATH}"; then
      mv "${TARGET_PATH}.autopilot-backup" "${TARGET_PATH}"
      external_retry "${request_id}" "Patch rejected: git diff check failed" 30
      exit 0
    fi

    diff_text="$(git diff -- "${TARGET_PATH}")"
    if grep -Eiq 'sk-[A-Za-z0-9_-]{20,}|service[_-]?role|SUPABASE_SERVICE_ROLE_KEY|OPENAI_API_KEY[[:space:]]*[=:]|eval\(|new Function\(' <<<"${diff_text}"; then
      mv "${TARGET_PATH}.autopilot-backup" "${TARGET_PATH}"
      external_human_blocker "${request_id}" "Security validation rejected the proposed patch." "Review the rejected change manually. The Autopilot detected a forbidden secret/privileged-code pattern."
      bash scripts/autopilot-worker.sh
      exit 0
    fi

    rm -f "${TARGET_PATH}.autopilot-backup"

    short_id="${request_id:0:8}"
    branch="autopilot/${short_id}-${action_key//[^A-Za-z0-9._-]/-}"
    git config user.name "cv-coach-autopilot[bot]"
    git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
    git checkout -b "${branch}"
    git add "${TARGET_PATH}"
    git commit -m "autopilot: ${title}"
    git push origin "HEAD:${branch}"

    pr_body="$(cat <<EOF
## CV Coach Autopilot proposal

${summary}

### Validation
- Exact-text replacement uniqueness: passed
- Target-type structural validation: passed
- Target-type syntax validation: passed
- `git diff --check`: passed
- Secret / privileged-code pattern scan: passed

### Safety
- OpenAI did not receive GitHub credentials.
- OpenAI did not write to the repository.
- This change is a **draft PR** and has not modified production.

AUTOPILOT_EXTERNAL_REQUEST_ID: ${request_id}
EOF
)"

    pr_url="$(gh pr create --draft --base main --head "${branch}" --title "[Autopilot] ${title}" --body "${pr_body}")"
    commit_sha="$(git rev-parse HEAD)"

    result="$(jq -nc \
      --arg decision "PATCH" \
      --arg summary "${summary}" \
      --arg reason "${reason}" \
      --arg pr_url "${pr_url}" \
      --arg branch "${branch}" \
      --arg commit_sha "${commit_sha}" \
      --argjson usage "${usage_json}" \
      '{decision:$decision,summary:$summary,reason:$reason,pr_url:$pr_url,branch:$branch,commit_sha:$commit_sha,usage:$usage,executor:"github-actions-openai",validation:{exact_replacements:true,target_syntax_check:true,diff_check:true,secret_scan:true}}')"
    proposal_created "${request_id}" "${result}"
    echo "Autopilot external executor: WAITING_REVIEW ${pr_url}"
    ;;

  *)
    external_retry "${request_id}" "Unknown structured decision: ${decision}" 30
    ;;
esac
