# 0002: OIDC only, separate plan and apply identities

Status: accepted

## Context

Terraform in CI needs powerful credentials. Long-lived keys leak. A pull request is attacker-controlled code until it is reviewed.

## Decision

GitHub OIDC through a workload identity pool. Per repository two service accounts: **plan** (read-only, reachable from any ref of the repository) and **apply** (write, reachable only from `refs/heads/main`). PR plans run with `-lock=false` against a bucket where the plan identity only has `objectViewer`. Service account keys are blocked by organization policy.

## Consequences

- A malicious PR can at most read what the plan identity can read.
- Apply needs both the `main` ref and the `production` environment approval.
- Forked PRs are never planned.
