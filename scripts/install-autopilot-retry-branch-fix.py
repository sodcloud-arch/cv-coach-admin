from pathlib import Path

path=Path('scripts/autopilot-external-executor.sh')
text=path.read_text()

def replace_once(old,new,label):
    global text
    count=text.count(old)
    if count!=1:
        raise SystemExit(f'{label}: expected 1 anchor, found {count}')
    text=text.replace(old,new,1)

replace_once(
'''if [[ ! -f "${TARGET_PATH}" ]]; then
  external_human_blocker "${request_id}" "Target source file ${TARGET_PATH} does not exist." "Restore or identify the canonical CV Coach Admin source before continuing."
  bash scripts/autopilot-worker.sh
  exit 0
fi

source_text="$(cat "${TARGET_PATH}")"''',
'''existing_branch="$(jq -r '._existing_branch // empty' <<<"${request_payload}")"
existing_pr_url="$(jq -r '._existing_pr_url // empty' <<<"${request_payload}")"
if [[ -n "${existing_branch}" ]]; then
  if [[ ! "${existing_branch}" =~ ^autopilot/[A-Za-z0-9._/-]+$ || "${existing_branch}" == *".."* ]]; then
    external_human_blocker "${request_id}" "Stored retry branch is not a safe Autopilot branch." "Inspect the Autopilot request payload before resuming."
    bash scripts/autopilot-worker.sh
    exit 0
  fi
  if ! git fetch origin "${existing_branch}"; then
    external_retry "${request_id}" "Could not fetch existing retry branch ${existing_branch}" 60
    exit 0
  fi
  if ! git checkout -B "${existing_branch}" "origin/${existing_branch}"; then
    external_retry "${request_id}" "Could not checkout existing retry branch ${existing_branch}" 60
    exit 0
  fi
fi

if [[ ! -f "${TARGET_PATH}" ]]; then
  external_human_blocker "${request_id}" "Target source file ${TARGET_PATH} does not exist." "Restore or identify the canonical CV Coach Admin source before continuing."
  bash scripts/autopilot-worker.sh
  exit 0
fi

source_text="$(cat "${TARGET_PATH}")"''',
'retry branch checkout')

replace_once(
'''    short_id="${request_id:0:8}"
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
    commit_sha="$(git rev-parse HEAD)"''',
'''    short_id="${request_id:0:8}"
    if [[ -n "${existing_branch}" ]]; then
      branch="${existing_branch}"
    else
      branch="autopilot/${short_id}-${action_key//[^A-Za-z0-9._-]/-}"
      git checkout -b "${branch}"
    fi
    git config user.name "cv-coach-autopilot[bot]"
    git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
    git add "${TARGET_PATH}"
    if git diff --cached --quiet; then
      external_retry "${request_id}" "Structured PATCH produced no staged change on the current retry branch" 30
      exit 0
    fi
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

    if [[ -n "${existing_pr_url}" ]]; then
      if [[ ! "${existing_pr_url}" =~ ^https://github.com/sodcloud-arch/cv-coach-admin/pull/[0-9]+$ ]]; then
        external_human_blocker "${request_id}" "Stored retry PR URL is not a canonical CV Coach pull request." "Inspect the Autopilot request payload before resuming."
        bash scripts/autopilot-worker.sh
        exit 0
      fi
      pr_url="${existing_pr_url}"
      gh pr edit "${pr_url}" --title "[Autopilot] ${title}" --body "${pr_body}" >/dev/null
    else
      pr_url="$(gh pr create --draft --base main --head "${branch}" --title "[Autopilot] ${title}" --body "${pr_body}")"
    fi
    commit_sha="$(git rev-parse HEAD)"''',
'retry branch commit/push')

required=[
    'existing_branch="$(jq -r \'._existing_branch // empty\'',
    'git checkout -B "${existing_branch}" "origin/${existing_branch}"',
    'if [[ -n "${existing_pr_url}" ]]',
    'gh pr edit "${pr_url}"',
    'Structured PATCH produced no staged change on the current retry branch'
]
missing=[x for x in required if x not in text]
if missing:
    raise SystemExit('missing retry continuity markers: '+', '.join(missing))
path.write_text(text)
