#!/usr/bin/env bash
# Prints a JSON array of the stages a change touches, in apply order.
# Usage: changed-stages.sh [BASE_REF]   (no BASE_REF = every stage)
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

base="${1:-}"
changed=""
run_all=false
if [[ -z "$base" ]]; then
  run_all=true
else
  changed="$(git diff --name-only "$base" HEAD)"
  if grep -qE '^(modules/|config/stages\.txt|\.github/(workflows|actions)/|\.terraform-version)' <<<"$changed"; then
    run_all=true
  fi
fi

# A new workload YAML also touches Stage 0 because Stage 0 owns all WIF bindings
# and State bucket IAM. Re-apply Stage 0 when YAML files are added or removed.
if [[ "$run_all" == false ]] && grep -qE '^4-workload-projects/data/projects/.*\.yaml$' <<<"$changed"; then
  changed="0-core-projects/dummy"$'\n'"$changed"
fi

selected=""
while IFS= read -r stage; do
  [[ -z "$stage" || "$stage" == \#* ]] && continue
  if [[ "$run_all" == true ]] || grep -q "^${stage}/" <<<"$changed"; then
    selected+="${stage}"$'\n'
  fi
done <config/stages.txt

printf '%s' "$selected" | jq -R -s -c 'split("\n") | map(select(length > 0))'
