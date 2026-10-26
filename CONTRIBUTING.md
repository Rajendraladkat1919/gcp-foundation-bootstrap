# Contributing

1. `make hooks`. The hooks are mandatory. Do not use `--no-verify`; CI runs the same checks and the PR cannot merge without them.
2. Branch from `main`. You cannot commit to `main` (a hook and the branch ruleset both stop it).
3. Commit messages and PR titles use conventional commits: `feat(1-org): add folder for business unit 1`. Allowed types: `feat fix docs chore refactor ci test revert security`.
4. Commits must be signed.
5. Open a PR. Read the plan comment for every stage you touched, line by line. If the plan shows something you did not intend, fix the code, not the plan.
6. Two approvals are required, one from a code owner. You cannot approve your own change, and a new push dismisses earlier approvals.
7. Merging to `main` starts `tf-apply`. A reviewer of the `production` environment must approve it.

## Rules of thumb

- Prefer a YAML file in `3-workload-projects/data/projects/` over new Terraform.
- Grant roles to groups, never to individual users.
- Never add `roles/owner` or `roles/editor` at folder or organization level. If you believe you need a wide role, add an entry under *Exceptions* in `docs/controls.md` in the same PR, with a reason and an owner.
- Never commit state, plans, keys or `.tfvars.local` files.
- Pin by tag or SHA, never by branch.
- Every variable and output has a description and a type. `tflint` enforces it.
- Run `make docs` after changing variables or outputs, the generated tables must match the code.

## Rollback

Revert the PR. The revert goes through the same pipeline. Resources with `deletion_policy = "PREVENT"` and folders with `deletion_protection` will refuse to be destroyed; lifting that protection is itself a reviewed change.
