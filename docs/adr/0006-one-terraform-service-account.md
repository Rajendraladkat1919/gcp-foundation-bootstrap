# 0006: One Terraform service account

Status: accepted

Supersedes the separate plan and apply service accounts in ADR 0002. OIDC and the ban on service account keys in that ADR still stand. Also supersedes the identity names in the consequences of ADR 0005.

## Context

Four service accounts in the iac-core project, plus a deployer and a planner in every workload project, split one job across many identities. Operating them means a plan account and an apply account per repository, and a new pair of accounts for every workload project.

## Decision

`dev-terraform-execute` in the iac-core project is the only service account that runs Terraform. Stage 0 creates it. Stage 1 grants its folder roles. Stage 3 lets the bootstrap repository, the landing-zone repository and every workload repository impersonate it. Stage 4 grants it the workload project roles and state-bucket access, and does not create a service account. `sa-billing-reader` and `sa-logging-reader` stay.

The GitHub variable `TF_SA` is this account. A feature-branch pull request runs fmt, tflint, validate, checkov, drift, then plan. Apply is a manual run from `main` behind the GitHub `production` environment. Destroy is not a workflow action. A pull request that can impersonate the account can write, because the account itself is not read-only. Drift and plan still run with `-lock=false`.

## Consequences

- The next apply of stages 0, 1, 3 and 4 deletes the four `sa-tf-*` accounts and the per-project `sa-wlp-deployer` and `sa-wlp-planner` accounts.
- `gcp-infrastructure-lz` reads `projects.*.terraform_executor_email` for Shared VPC network users.
- EX-1, EX-2, EX-3 and EX-6 in [controls.md](../controls.md) name this account.
