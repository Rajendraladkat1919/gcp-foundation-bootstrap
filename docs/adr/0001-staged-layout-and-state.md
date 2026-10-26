# 0001: Four stages, one state each

Status: accepted

## Context

Organization policy, projects, identity and workload projects change at very different speeds and carry very different blast radii. One state file would put the riskiest change behind the same lock as the most frequent one.

## Decision

Four stage directories (`0-core-projects`, `1-org`, `2-cicd-identity`, `3-workload-projects`), each with its own state prefix in one CMEK-encrypted bucket. The order is in `config/stages.txt`. Stages talk to each other through outputs read with `terraform_remote_state`, and through `modules/naming` for names that must never diverge.

## Consequences

- A failed apply in one stage does not block the others.
- Output names are an API (see architecture, cross-repository contract).
- The first apply of stage 0 needs local state, covered in the runbook.
