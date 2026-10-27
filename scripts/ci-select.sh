#!/usr/bin/env bash
# Chooses the pipeline action and the stage list. Writes GitHub step outputs:
# action (plan, apply, drift), list (JSON array), any (true/false), base (git sha).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

event="${EVENT:?}"
action="plan"
base=""

write_outputs() {
  local list="$1"
  local any="false"
  if [ "$list" != "[]" ]; then
    any="true"
  fi
  {
    echo "list=${list}"
    echo "any=${any}"
    echo "action=${action}"
    echo "base=${base}"
  } >> "${GITHUB_OUTPUT:?}"
}

case "$event" in
  pull_request)
    action="plan"
    base="${BASE_SHA:?}"
    write_outputs "$(scripts/changed-stages.sh "$base")"
    ;;
  schedule)
    action="drift"
    base="${GITHUB_SHA:?}"
    write_outputs "$(scripts/changed-stages.sh)"
    ;;
  workflow_dispatch)
    action="${INPUT_ACTION:?}"
    if [ "$action" = "apply" ] && [ "${REF:?}" != "refs/heads/main" ]; then
      echo "::error::Apply runs from main, after the feature-branch plan looks right."
      exit 1
    fi
    git fetch --no-tags origin main
    if [ "$action" = "apply" ]; then
      # Parent of this commit is what should already match Google Cloud.
      base="$(git rev-parse HEAD^)"
    else
      base="$(git rev-parse origin/main)"
    fi
    stage="${INPUT_STAGE:-all}"
    if [ -z "$stage" ] || [ "$stage" = "all" ]; then
      write_outputs "$(scripts/changed-stages.sh)"
      exit 0
    fi
    if ! grep -vE '^\s*(#|$)' config/stages.txt | grep -qx "$stage"; then
      echo "::error::Unknown stage: ${stage}"
      exit 1
    fi
    write_outputs "$(jq -nc --arg s "$stage" '[$s]')"
    ;;
  *)
    echo "::error::Unexpected event: ${event}"
    exit 1
    ;;
esac
