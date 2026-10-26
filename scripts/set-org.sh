#!/usr/bin/env bash
# Replaces the ORG placeholder (GitHub organization) in module sources, CODEOWNERS and docs.
# Usage: scripts/set-org.sh <github-org>
set -euo pipefail

org="${1:?usage: $0 <github-org>}"
if [[ ! "$org" =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]]; then
  echo "invalid organization name: $org" >&2
  exit 1
fi

root="$(git rev-parse --show-toplevel)"
cd "$root"
git ls-files -z -- '*.tf' '*.md' '*.yml' '*.yaml' 'CODEOWNERS' '.github/CODEOWNERS' |
  xargs -0 perl -pi -e "s#github\\.com/ORG/#github.com/${org}/#g; s#\\@ORG/#\\@${org}/#g"
echo "Replaced ORG with ${org}. Review with: git diff"
