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

# The identity stage names every workload repository in the pool condition and
# lets that repository impersonate dev-terraform-execute. A new YAML re-applies it.
yaml_touches_identity=false
if [[ "$run_all" == false ]] && grep -qE '^4-workload-projects/data/projects/.*\.yaml$' <<<"$changed"; then
  yaml_touches_identity=true
fi

selected=""
while IFS= read -r stage; do
  [[ -z "$stage" || "$stage" == \#* ]] && continue
  if [[ "$run_all" == true ]] || grep -q "^${stage}/" <<<"$changed" || { [[ "$stage" == "3-cicd-identity" ]] && [[ "$yaml_touches_identity" == true ]]; }; then
    selected+="${stage}"$'\n'
  fi
done <config/stages.txt

printf '%s' "$selected" | jq -R -s -c 'split("\n") | map(select(length > 0))'
