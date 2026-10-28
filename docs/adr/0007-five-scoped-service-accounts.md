# 0007: Five scoped service accounts with environment-segregated WIF bindings

Status: accepted

Supersedes [0006](0006-one-terraform-service-account.md).

## Context

ADR 0006 consolidated all Terraform identity into one service account (`dev-terraform-execute`) shared by every repository and every GitHub Actions job. This was simpler to operate but created an unacceptable blast radius: a compromised pipeline in any repository — including a workload repository that runs frequently and has a broader attack surface — could impersonate an account holding `roles/resourcemanager.organizationAdmin`.

The four-repository architecture (`gcp-foundation-bootstrap`, `gcp-infrastructure-lz`, `gcp-workload`, `gcp-terraform-modules`) has distinct permission requirements:

- **Bootstrap** needs org-admin, folder-admin, and project-creator to build the skeleton.
- **Infra LZ** needs network-admin and NCC-admin on specific network projects only. It does not need org-level access.
- **Workload** needs editor on specific workload projects only. It does not need network or org access.
- **Modules** is a library. It never runs Terraform and needs no service account.

In addition, a pull request that plans against nonprod state must be mathematically incapable of obtaining production credentials, regardless of workflow logic.

## Decision

Replace `dev-terraform-execute` with five service accounts, all in `pr-iac-core`:

| SA | Bound repository | Condition |
|---|---|---|
| `sa-tf-bootstrap` | `gcp-foundation-bootstrap` | any ref (no env restriction) |
| `sa-tf-infra-prod` | `gcp-infrastructure-lz` | `attribute.environment == "production"` |
| `sa-tf-infra-nonprod` | `gcp-infrastructure-lz` | `attribute.environment == "nonprod"` |
| `sa-tf-workload-prod` | `gcp-workload` | `attribute.environment == "production"` |
| `sa-tf-workload-nonprod` | `gcp-workload` | `attribute.environment == "nonprod"` |

Each SA IAM binding is authoritative (`google_service_account_iam_binding`, not `_member`) so no other principal can impersonate the SA without an explicit code change.

The WIF pool maps `attribute.environment` from `assertion.environment`. GitHub Actions jobs declare `environment: nonprod` or `environment: production` in the workflow, which populates this claim. A PR plan job declares `environment: nonprod` and can therefore only impersonate the nonprod SA.

Permissions are granted progressively:
- Stage 0 creates all five SAs with no project roles on infra and workload SAs.
- Stage 2 grants infra SAs on network projects after those projects exist.
- Stage 4 grants workload SAs on workload projects after those projects exist.

SA emails are computed once in Stage 1 (`outputs.sa_emails`) and consumed by Stages 2 and 4 via remote state. Stage 1 is the single source of truth for SA email strings.

The `bootstrap` state bucket is owned by `sa-tf-bootstrap` only. The `lz` state bucket is owned by `sa-tf-infra-prod` and `sa-tf-infra-nonprod`. Each workload project's state bucket is owned by its environment's workload SA.

## Consequences

- `dev-terraform-execute` is deleted and replaced by `sa-tf-bootstrap` on the next apply of Stage 0.
- `3-cicd-identity` is removed. WIF pool creation and all SA WIF bindings move to Stage 0 so identity exists from the first apply.
- `gcp-infrastructure-lz` must set `TF_SA` to `sa-tf-infra-prod` (prod jobs) or `sa-tf-infra-nonprod` (nonprod jobs). The emails are in Stage 2 `outputs.infra_sa_emails` and Stage 0 `outputs.automation_service_accounts`.
- `gcp-workload` must set `TF_SA` per environment. The emails are in Stage 4 `outputs.projects[*].workload_sa_email`.
- `gcp-foundation-bootstrap` uses `TF_SA_BOOTSTRAP` (renamed from `TF_SA`) for all its stages.
- EX-1 in [controls.md](../controls.md) still applies: `sa-tf-bootstrap` holds `roles/resourcemanager.organizationAdmin`. The exception now names `sa-tf-bootstrap` and is narrowed because the infra and workload SAs no longer carry this role.
- EX-3 in controls.md is updated: workload SAs hold `roles/editor` on workload projects. Bootstrap SA holds only `projectIamAdmin` and `serviceUsageAdmin` on those same projects.
