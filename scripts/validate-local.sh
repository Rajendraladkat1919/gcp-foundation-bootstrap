#!/usr/bin/env bash
# Validate every stage without network access to the private modules repository.
# Copies this repository to a temp dir, points the module sources at a local
# checkout of gcp-terraform-module, then runs init -backend=false and validate.
#
# Usage: scripts/validate-local.sh [PATH_TO_gcp-terraform-module]
set -euo pipefail

repo="$(git rev-parse --show-toplevel)"
modules="${1:-${repo}/../gcp-terraform-module}"
modules="$(cd "$modules" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

rsync -a --exclude '.git' --exclude '.terraform' "$repo/" "$work/"

# git::https://github.com/ORG/gcp-terraform-module.git//modules/x?ref=vN -> /abs/path/modules/x
find "$work" -name '*.tf' -print0 | xargs -0 perl -pi -e \
  "s#git::https://github\\.com/[^/]+/gcp-terraform-module\\.git//modules/([a-z0-9-]+)\\?ref=[^\"]+#${modules}/modules/\$1#g"

status=0
while IFS= read -r stage; do
  [[ -z "$stage" || "$stage" == \#* ]] && continue
  echo "=== ${stage}"
  (
    cd "$work/$stage"
    terraform init -backend=false -input=false -no-color >/dev/null
    terraform validate -no-color
  ) || status=1
done <"$repo/config/stages.txt"
exit "$status"
