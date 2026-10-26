# gcp-foundation-bootstrap

Trust level: **High**. This repository can create projects, change organization policy and grant IAM at the organization. Every change goes through a pull request, two reviewers (one a code owner) and a human approval before apply.

It builds the part of the Google Cloud foundation that everything else stands on:

| Stage | Creates | Why it is separate |
|---|---|---|
| [`0-core-projects`](0-core-projects/) | Org-level core projects (`iac-core`, `billing`, `logging`), CMEK key, Terraform state buckets, the four automation service accounts | Everything else depends on these. Applied by hand once, then by CI. |
| [`1-org`](1-org/) | Folder hierarchy, organization policies, org audit logging and sink, VPC flow-log sink, group access | Highest blast radius, smallest and slowest-changing code. |
| [`2-cicd-identity`](2-cicd-identity/) | GitHub OIDC workload identity pool and provider, repository to service account bindings | Controls who can run Terraform at all. Workload repositories and `cicd-runners` may mint a token from the same pool. |
| [`3-workload-projects`](3-workload-projects/) | One project per YAML file under `3-workload-projects/data/projects/`, with a deployer identity, a planner identity, a CMEK key and a state bucket | The only stage that changes often. A new project is one reviewed YAML file. |

Networking (hub, spokes, Shared VPC) lives in the sibling repository `gcp-infrastructure-lz`. Module code comes from `gcp-terraform-module` (vendored Cloud Foundation Fabric **v59.1.0**), pinned by tag.

## How a change flows

```text
pull request ──▶ pre-commit (fmt, validate, tflint, checkov, gitleaks, docs, actionlint)
             ──▶ tf-plan   (read-only identity, plan commented on the PR, policy scan of the plan)
             ──▶ 2 approvals, one from a code owner, signed commits, linear history
merge to main ─▶ tf-apply  (production environment approval, then apply stages in order)
every night   ─▶ drift-detect (plan only, opens an issue when reality differs from code)
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
3. Edit the `terraform.tfvars` of each stage (look for `REPLACE_ME` and `000000000000`).
4. `make hooks` before your first commit. Commits that fail the hooks are rejected locally, and CI runs the same hooks.
5. `make validate` checks every stage offline against a sibling checkout of `gcp-terraform-module`.

## GitHub configuration (set after stage 2 is applied)

| Kind | Name | Value |
|---|---|---|
| Variable | `WIF_PROVIDER` | Output `workload_identity_provider_name` of stage 2 |
| Variable | `TF_PLAN_SA` | Output `automation_service_accounts.bootstrap_plan` of stage 0 |
| Variable | `TF_APPLY_SA` | Output `automation_service_accounts.bootstrap_apply` of stage 0 |
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
2-cicd-identity/     stage: GitHub OIDC
3-workload-projects/ stage: workload projects from YAML (data/projects/*.yaml)
modules/naming/      names shared by every stage and by gcp-infrastructure-lz
config/stages.txt    apply order, read by the workflows
docs/                architecture, runbook, controls, ADRs
scripts/             changed-stages, offline validation, branch protection, set-org
```
