#!/usr/bin/env bash
# Clones gcp-terraform-module where stage directories expect it:
# <stage>/../../gcp-terraform-module.
set -euo pipefail

token="${MODULES_TOKEN:?}"
owner="${GITHUB_REPOSITORY_OWNER:?}"
workspace="${GITHUB_WORKSPACE:?}"

echo "::add-mask::${token}"
dest="$(dirname "$(dirname "$workspace")")/gcp-terraform-module"
if [ -d "${dest}/.git" ]; then
  exit 0
fi
# -c keeps the token out of the cloned repo's remote URL.
basic="$(printf 'x-access-token:%s' "$token" | base64 | tr -d '\n')"
git -c "http.https://github.com/.extraheader=AUTHORIZATION: basic ${basic}" \
  clone --depth 1 "https://github.com/${owner}/gcp-terraform-module.git" "$dest"
