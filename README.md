# gcp-foundation-bootstrap

Trust level: **High**. This repository can create projects, change organization policy and grant IAM at the organization. Every change goes through a pull request, two reviewers (one a code owner) and a human approval before apply.

It builds the part of the Google Cloud foundation that everything else stands on:

| Stage | Creates | Why it is separate |
|---|---|---|
| [`0-core-projects`](0-core-projects/) | Org-root shell projects (`<prefix>-pr-iac-core`, `<prefix>-pr-billing`, `<prefix>-pr-logging`), CMEK key, Terraform state buckets, `dev-terraform-execute`, `sa-billing-reader` and `sa-logging-reader` | These sit on the organization, not in a folder. Everything else depends on them. Applied by hand once, then by CI. |
| [`1-org`](1-org/) | Folder hierarchy, organization policies, org audit logging and sink, VPC flow-log sink, group access | Highest blast radius, smallest and slowest-changing code. |
| [`2-network-projects`](2-network-projects/) | Shell only, under Infrastructure / Network: `<prefix>-pr-net-core`, `<prefix>-prod-net-spoke`, `<prefix>-non-prod-net-spoke` | Applied right after the folders. With prefix `demo` the ids are `demo-pr-net-core`, `demo-prod-net-spoke`, `demo-non-prod-net-spoke`. VPCs stay in `gcp-infrastructure-lz`. |
| [`3-cicd-identity`](3-cicd-identity/) | GitHub OIDC workload identity pool and provider, repository to service account bindings | Controls who can run Terraform at all. Workload repositories and `cicd-runners` may mint a token from the same pool. |
| [`4-workload-projects`](4-workload-projects/) | One project per YAML file under `4-workload-projects/data/projects/`, with `dev-terraform-execute` granted on that project, a CMEK key and a state bucket | The only stage that changes often. A new project is one reviewed YAML file. |

Module code comes from `gcp-terraform-module` (vendored Cloud Foundation Fabric **v59.1.0**), pinned by tag.

## How a change flows

```text
feature branch ─▶ terraform workflow, in order:
                  fmt, tflint, validate, checkov, drift, plan
             ──▶ 2 approvals, one from a code owner, signed commits, linear history
main, manual  ─▶ Actions → terraform → apply
                  (repeats those stages, then apply after the production approval)
every night   ─▶ drift (opens an issue when Google Cloud differs from main)
```

See [docs/architecture.md](docs/architecture.md) for the diagrams and [docs/controls.md](docs/controls.md) for what is enforced and what is not.

## Requirements

| Tool | Version | Notes |
|---|---|---|
| Terraform | `1.16.6` (see `.terraform-version`) | Providers `google` and `google-beta` `~> 8.5` |
| pre-commit | `>= 3.7` | **Mandatory.** `make hooks` |
| tflint | `>= 0.60` | Google ruleset is installed by `tflint --init` |
| terraform-docs | `>= 0.24` | `brew install terraform-docs` |
| checkov | `3.3.30` | `pipx install checkov==3.3.30` |
| Go | current | pre-commit builds gitleaks and actionlint with it |
| gh | current | Only for `make protect` |

## Getting started

1. Read [docs/runbook-bootstrap.md](docs/runbook-bootstrap.md). The first apply is manual and needs elevated human access once.
2. `make set-org ORG=<github-org>` replaces the `ORG` placeholder in module sources and CODEOWNERS.
3. Copy each stage's `terraform.tfvars.example` to `terraform.tfvars` and replace `REPLACE_ME` and `000000000000`. Do not commit `terraform.tfvars`.
4. `make hooks` before your first commit. Commits that fail the hooks are rejected locally, and CI runs the same hooks.
5. `make validate` checks every stage offline against a sibling checkout of `gcp-terraform-module`.

## GitHub configuration (set after stage 3 is applied)

| Kind | Name | Value |
|---|---|---|
| Variable | `WIF_PROVIDER` | Output `workload_identity_provider_name` of stage 3 (`3-cicd-identity`) |
| Variable | `TF_SA` | Output `automation_service_accounts.execute` of stage 0. Drift, plan and apply use this account |
| Variable | `TF_STATE_BUCKET` | Output `state_buckets.bootstrap` of stage 0 |
| Variable (optional) | `RUNNER_LABELS` | JSON list, for example `["self-hosted","cicd-runners"]`. Default `["ubuntu-24.04"]` |
| Secret | `MODULES_READ_TOKEN` | Read-only credential for `gcp-terraform-module` (GitHub App installation token or fine-grained PAT, `contents: read` on that one repository) |
| Environment | `production` | Required reviewers, deployment from `main` only. `make protect` creates it. |

None of these is a long-lived Google credential. Authentication is OIDC only.

## Repository layout

```text
.github/             workflows, composite action, CODEOWNERS, rulesets, templates, dependabot
0-core-projects/     stage: core projects, state, CMEK, automation identities
1-org/               stage: folders, org policy, audit logging, group access
2-network-projects/  stage: hub and Shared VPC host projects under the Network folder
3-cicd-identity/     stage: GitHub OIDC
4-workload-projects/ stage: workload projects from YAML (data/projects/*.yaml)
config/stages.txt    apply order, read by the workflows
docs/                architecture, runbook, controls, ADRs
scripts/             changed-stages, offline validation, branch protection, set-org
```
