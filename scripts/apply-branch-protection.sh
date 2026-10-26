#!/usr/bin/env bash
# Creates or updates the branch ruleset and the `production` environment.
# Needs: gh CLI authenticated as a repository admin.
# Usage: scripts/apply-branch-protection.sh OWNER/REPO REVIEWER_TEAM_SLUG
set -euo pipefail

repo="${1:?usage: $0 OWNER/REPO REVIEWER_TEAM_SLUG}"
team="${2:?usage: $0 OWNER/REPO REVIEWER_TEAM_SLUG}"
owner="${repo%%/*}"
root="$(git rev-parse --show-toplevel)"

existing="$(gh api "repos/${repo}/rulesets" --jq '.[] | select(.name=="main-protection") | .id' || true)"
if [[ -n "$existing" ]]; then
  gh api -X PUT "repos/${repo}/rulesets/${existing}" --input "${root}/.github/rulesets/main.json" >/dev/null
  echo "updated ruleset ${existing}"
else
  gh api -X POST "repos/${repo}/rulesets" --input "${root}/.github/rulesets/main.json" >/dev/null
  echo "created ruleset"
fi

team_id="$(gh api "orgs/${owner}/teams/${team}" --jq .id)"
gh api -X PUT "repos/${repo}/environments/production" \
  --input - >/dev/null <<JSON
{
  "wait_timer": 0,
  "prevent_self_review": true,
  "reviewers": [{ "type": "Team", "id": ${team_id} }],
  "deployment_branch_policy": { "protected_branches": true, "custom_branch_policies": false }
}
JSON
echo "environment 'production' requires review by ${team}, main only"
