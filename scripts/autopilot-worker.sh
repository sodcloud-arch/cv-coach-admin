#!/usr/bin/env bash
set -euo pipefail
# AUTOPILOT_SHELL_VALIDATION_SMOKE_V2: type-aware shell validation verified.

EDGE_URL="${EDGE_URL:-https://fmhcansyxcsqkrivqchr.supabase.co/functions/v1/autopilot-worker-gateway}"
OIDC_AUDIENCE="${OIDC_AUDIENCE:-cv-coach-autopilot}"
MAX_CYCLES="${MAX_CYCLES:-20}"

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

resolve_blocker_if_requested() {
  if [[ -z "${RESOLVE_BLOCKER_ID:-}" ]]; then
    return 0
  fi

  local token payload response
  token="$(get_oidc_token)"
  payload="$(jq -nc \
    --arg blocker_id "${RESOLVE_BLOCKER_ID}" \
    --arg note "${RESOLUTION_NOTE:-Resolved from GitHub issue close}" \
    '{op:"resolve_blocker", blocker_id:$blocker_id, resolution_note:$note}')"

  # GitHub can retain an old blocker Issue after the backend already resolved it.
  # Treat that resume signal as idempotent: a rejected/already-resolved resolution
  # must not abort the worker before it gets a chance to tick the current queue.
  if ! response="$(call_edge "${token}" "${payload}" 2>&1)"; then
    echo "Autopilot blocker resolution: non-fatal stale/already-resolved signal (${RESOLVE_BLOCKER_ID})."
    echo "Gateway response: ${response}" >&2
    return 0
  fi

  echo "Autopilot blocker resolution: ${response}"
}

reconcile_resolved_blocker_issues() {
  local token payload response kind blocker_id notification_ref issue_number issue_json issue_state issue_title issue_body

  token="$(get_oidc_token)"
  payload='{"op":"resolved_blocker_notifications","limit":200}'
  if ! response="$(call_edge "${token}" "${payload}" 2>&1)"; then
    echo "Autopilot blocker reconciliation: non-fatal gateway failure." >&2
    echo "Gateway response: ${response}" >&2
    return 0
  fi

  kind="$(jq -r '.kind // "ERROR"' <<<"${response}")"
  if [[ "${kind}" != "RESOLVED_BLOCKER_NOTIFICATIONS" ]]; then
    echo "Autopilot blocker reconciliation: unexpected response kind ${kind}; skipping." >&2
    return 0
  fi

  while IFS=$'\t' read -r blocker_id notification_ref; do
    [[ -n "${blocker_id}" && -n "${notification_ref}" ]] || continue

    if [[ ! "${notification_ref}" =~ ^https://github\.com/${GITHUB_REPOSITORY}/issues/([0-9]+)$ ]]; then
      echo "Autopilot blocker reconciliation: ignored non-canonical notification ref ${notification_ref}."
      continue
    fi
    issue_number="${BASH_REMATCH[1]}"

    if ! issue_json="$(gh issue view "${issue_number}" --repo "${GITHUB_REPOSITORY}" --json state,title,body 2>/dev/null)"; then
      echo "Autopilot blocker reconciliation: issue #${issue_number} is unavailable; skipping."
      continue
    fi

    issue_state="$(jq -r '.state // "UNKNOWN"' <<<"${issue_json}")"
    [[ "${issue_state}" == "OPEN" ]] || continue

    issue_title="$(jq -r '.title // ""' <<<"${issue_json}")"
    issue_body="$(jq -r '.body // ""' <<<"${issue_json}")"
    if [[ "${issue_title}" != "🔴 CV Coach Autopilot — "* ]]; then
      echo "Autopilot blocker reconciliation: issue #${issue_number} is not an Autopilot blocker; skipping."
      continue
    fi
    if ! grep -Fqx "AUTOPILOT_BLOCKER_ID: ${blocker_id}" <<<"${issue_body}"; then
      echo "Autopilot blocker reconciliation: blocker marker mismatch in issue #${issue_number}; skipping."
      continue
    fi

    if gh issue close "${issue_number}" \
      --repo "${GITHUB_REPOSITORY}" \
      --reason completed \
      --comment "Autopilot housekeeping: el backend ya registra este blocker como RESOLVED y su misión/acción como completadas. Cierre automático; no requiere intervención de Camilo."; then
      echo "Autopilot blocker reconciliation: closed stale issue #${issue_number}."
    else
      echo "Autopilot blocker reconciliation: could not close issue #${issue_number}; continuing." >&2
    fi
  done < <(jq -r '.blockers[]? | [.blocker_id, .notification_ref] | @tsv' <<<"${response}")
}

notify_blocker() {
  local response="$1"
  local blocker_id mission_id mission_key mission_title action_id action_key reason required_action issue_body issue_url token ack_payload ack_response

  blocker_id="$(jq -r '.blocker.blocker_id' <<<"${response}")"
  mission_id="$(jq -r '.blocker.mission_id' <<<"${response}")"
  mission_key="$(jq -r '.blocker.mission_key' <<<"${response}")"
  mission_title="$(jq -r '.blocker.mission_title' <<<"${response}")"
  action_id="$(jq -r '.blocker.action_id' <<<"${response}")"
  action_key="$(jq -r '.blocker.action_key' <<<"${response}")"
  reason="$(jq -r '.blocker.reason' <<<"${response}")"
  required_action="$(jq -r '.blocker.required_action' <<<"${response}")"

  issue_body="$(cat <<EOF
CV Coach Autopilot encontró un bloqueo que requiere intervención humana.

**Misión:** ${mission_title} (${mission_key})
**Acción:** ${action_key}
**Qué pasó:** ${reason}
**Qué debe hacer Camilo:** ${required_action}

Cuando esté resuelto, cierra este Issue. El cierre reanudará automáticamente la misión desde su checkpoint.

AUTOPILOT_BLOCKER_ID: ${blocker_id}
AUTOPILOT_MISSION_ID: ${mission_id}
AUTOPILOT_ACTION_ID: ${action_id}
EOF
)"

  if ! issue_url="$(gh issue create \
    --repo "${GITHUB_REPOSITORY}" \
    --title "🔴 CV Coach Autopilot — ${mission_key}" \
    --body "${issue_body}")"; then
    token="$(get_oidc_token)"
    ack_payload="$(jq -nc --arg blocker_id "${blocker_id}" --arg error "GitHub Issue creation failed" '{op:"blocker_notification_failed", blocker_id:$blocker_id, error:$error}')"
    call_edge "${token}" "${ack_payload}" || true
    return 1
  fi

  echo "Human blocker issue: ${issue_url}"
  token="$(get_oidc_token)"
  ack_payload="$(jq -nc --arg blocker_id "${blocker_id}" --arg ref "${issue_url}" '{op:"blocker_notified", blocker_id:$blocker_id, notification_ref:$ref}')"
  ack_response="$(call_edge "${token}" "${ack_payload}")"
  echo "Blocker notification ACK: ${ack_response}"
}

run_loop() {
  local i token response kind
  for i in $(seq 1 "${MAX_CYCLES}"); do
    token="$(get_oidc_token)"
    response="$(call_edge "${token}" '{"op":"tick"}')"
    kind="$(jq -r '.kind // "ERROR"' <<<"${response}")"
    echo "Autopilot cycle ${i}: ${kind}"

    case "${kind}" in
      ACTION_SUCCEEDED)
        continue
        ;;
      BLOCKER)
        notify_blocker "${response}"
        break
        ;;
      ACTION_EXTERNAL_WAIT)
        echo "${response}"
        break
        ;;
      ACTION_DEFERRED)
        echo "${response}"
        break
        ;;
      IDLE)
        break
        ;;
      *)
        echo "Unexpected Autopilot response: ${response}" >&2
        exit 1
        ;;
    esac
  done
}

resolve_blocker_if_requested
reconcile_resolved_blocker_issues
run_loop
