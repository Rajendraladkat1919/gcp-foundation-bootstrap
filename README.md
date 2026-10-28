# gcp-foundation-bootstrap

Trust level: **High**. This repository can create projects, change organization policy and grant IAM at the organization. Every change goes through a pull request, two reviewers (one a code owner) and a human approval before apply.

It builds the part of the Google Cloud foundation that everything else stands on:

| Stage | Creates | Why it is separate |
|---|---|---|
| [`0-core-projects`](0-core-projects/) | 3 org-root projects (`pr-iac-core`, `pr-billing`, `pr-logging`), CMEK key, state buckets, **5 scoped Terraform SAs**, GitHub OIDC WIF pool + provider, `sa-billing-reader`, `sa-logging-reader` | These sit on the organization, not in a folder. Identity must exist before anything else runs. Applied by hand once, then by CI. |
| [`1-org`](1-org/) | Folder hierarchy, 29 organization policies, org audit logging (4 sinks + XSIAM), 10 config-change alerts, 6 custom IAM roles, Okta group bindings | Highest blast radius, smallest and slowest-changing code. |
| [`2-network-projects`](2-network-projects/) | Three shell projects under `Infrastructure/Network`: `net-core-hub`, `net-shared-prod`, `net-shared-nonprod`. Grants infra SAs on each project. | Applied right after folders. VPCs, firewall, NAT and NCC stay in `gcp-infrastructure-lz`. |
| [`4-workload-projects`](4-workload-projects/) | One project per YAML file under `data/projects/`, with per-environment workload SA granted, a CMEK key and a state bucket | The only stage that changes often. A new project is one reviewed YAML file. |

Module code comes from `gcp-terraform-module` (Cloud Foundation Fabric **v59.1.0**), pinned by tag.

## Identity architecture

Five service accounts, all in `pr-iac-core`, each scoped to one GitHub repository and one environment. No SA keys — OIDC only. See [ADR 0007](docs/adr/0007-five-scoped-service-accounts.md).

```
sa-tf-bootstrap       ← gcp-foundation-bootstrap (this repo, any env)
sa-tf-infra-prod      ← gcp-infrastructure-lz   (environment=production only)
sa-tf-infra-nonprod   ← gcp-infrastructure-lz   (environment=nonprod only)
sa-tf-workload-prod   ← gcp-workload             (environment=production only)
sa-tf-workload-nonprod← gcp-workload             (environment=nonprod only)
```

A pull request plan job declares `environment: nonprod` in the workflow. The WIF IAM condition enforces that it can only impersonate the nonprod SA — mathematically preventing a PR from obtaining production credentials regardless of workflow logic.

## How a change flows

```text
feature branch ─▶ terraform workflow, in order:
                  fmt, tflint, validate, checkov, drift, plan
             ──▶ 2 approvals, one from a code owner, signed commits, linear history
main, manual  ─▶ Actions → terraform → apply
                  (repeats those stages, then apply after the production approval)
every night   ─▶ drift (opens an issue when Google Cloud differs from main)
```

See [docs/architecture.md](docs/architecture.md) for diagrams and [docs/controls.md](docs/controls.md) for what is enforced and what is not.

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
3. Copy each stage's `terraform.tfvars.example` to `terraform.tfvars` and fill in real values. Do not commit `terraform.tfvars`.
4. `make hooks` before your first commit. Commits that fail the hooks are rejected locally, and CI runs the same hooks.
5. `make validate` checks every stage offline against a sibling checkout of `gcp-terraform-module`.

## GitHub configuration (set after Stage 0 is applied)

| Kind | Name | Value |
|---|---|---|
| Variable | `WIF_PROVIDER` | Output `wif_provider` of Stage 0 (`0-core-projects`) |
| Variable | `TF_SA_BOOTSTRAP` | Output `automation_service_accounts.bootstrap` of Stage 0 — used by this repo's pipeline |
| Variable | `TF_STATE_BUCKET` | Output `state_buckets.bootstrap` of Stage 0 |
| Variable (optional) | `RUNNER_LABELS` | JSON list, e.g. `["self-hosted","cicd-runners"]`. Default `["ubuntu-24.04"]` |
| Secret | `MODULES_READ_TOKEN` | Read-only credential for `gcp-terraform-module` (`contents: read` on that repository only) |
| Environment | `nonprod` | No approval gate. Used by plan and drift jobs. |
| Environment | `production` | Required reviewers, deployment from `main` only. `make protect` creates it. |

**For other repositories** — set these GitHub variables after Stage 2 and Stage 4 are applied:

| Repo | Variable | Source |
|---|---|---|
| `gcp-infrastructure-lz` | `TF_SA` (prod jobs) | Stage 2 output `infra_sa_emails.prod` |
| `gcp-infrastructure-lz` | `TF_SA` (nonprod jobs) | Stage 2 output `infra_sa_emails.nonprod` |
| `gcp-workload` | `TF_SA` (prod jobs) | Stage 4 output `projects[*].workload_sa_email` (prod entries) |
| `gcp-workload` | `TF_SA` (nonprod jobs) | Stage 4 output `projects[*].workload_sa_email` (nonprod entries) |

None of these is a long-lived Google credential. Authentication is OIDC only.

## Repository layout

```text
.github/             workflows, composite action, CODEOWNERS, rulesets, templates, dependabot
0-core-projects/     stage 0: core projects, state, CMEK, 5 Terraform SAs, WIF pool + bindings
1-org/               stage 1: folders, org policies (29), audit logging, monitoring, custom IAM roles
2-network-projects/  stage 2: hub + Shared VPC host projects, infra SA grants
4-workload-projects/ stage 3: workload projects from YAML (data/projects/*.yaml), workload SA grants
config/stages.txt    apply order, read by the workflows
docs/                architecture, runbook, controls, ADRs (including ADR 0007 for SA design)
scripts/             changed-stages, offline validation, branch protection, set-org
```
