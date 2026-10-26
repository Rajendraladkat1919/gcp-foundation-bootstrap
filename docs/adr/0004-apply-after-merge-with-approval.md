# 0004: Apply on merge, behind an environment approval

Status: accepted

## Context

Applying the saved plan from the PR keeps "what was reviewed is what runs", but it goes stale as soon as anything else changes state, and cross-stage `terraform_remote_state` reads make a stack of saved plans unreliable.

## Decision

On merge, the apply job waits for the `production` environment approval, then for each affected stage in order runs `init`, `validate`, a fresh `plan` and `apply` of that plan. The PR plan is the review artifact, the nightly drift check is the safety net, and serial `concurrency` prevents overlapping applies.

## Consequences

- The apply-time plan can differ from the PR plan if the world changed in between. The approval happens before that plan is computed, so the approver must compare the PR plan comment with what the run is about to do. The plan is written to the job log before every apply.
- Re-running the job is safe: apply is idempotent.
