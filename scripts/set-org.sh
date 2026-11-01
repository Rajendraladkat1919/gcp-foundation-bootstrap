#!/usr/bin/env bash
# Replaces the ORG placeholder in CODEOWNERS and workflow files with the actual
# GitHub organisation name. Modules now source directly from the public CFF repo
# so there are no module-source placeholders to replace.
# Usage: scripts/set-org.sh <github-org>
set -euo pipefail

org="${1:?usage: $0 <github-org>}"
if [[ ! "$org" =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]]; then
  echo "invalid organization name: $org" >&2
  exit 1
fi

root="$(git rev-parse --show-toplevel)"
cd "$root"
git ls-files -z -- '*.md' '*.yml' '*.yaml' 'CODEOWNERS' '.github/CODEOWNERS' |
  xargs -0 perl -pi -e "s#\\@ORG/#\\@${org}/#g"
echo "Replaced ORG with ${org} in CODEOWNERS and docs. Review with: git diff"
