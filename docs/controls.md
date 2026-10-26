# Controls

What this repository enforces in code, where, and what it deliberately leaves to people or other systems. This is a mapping aid for audits (CIS Google Cloud Foundation Benchmark topics, SOC 2 change management and logical access, ISO 27001 Annex A). It is **not** a certification, and no repository can make an organization compliant on its own. See *Not covered here*.

## Enforced in code

### Change management

| Control | Implementation | Where |
|---|---|---|
| Peer review of every change | Two approvals, one from a code owner, stale approvals dismissed, last pusher cannot approve | `.github/rulesets/main.json`, `.github/CODEOWNERS` |
| No direct commits to `main` | Ruleset plus `no-commit-to-branch` hook | ruleset, `.pre-commit-config.yaml` |
| Signed commits, linear history | Ruleset | `.github/rulesets/main.json` |
| Mandatory automated checks | `pre-commit`, `plan-gate`, `pr-title`, `dependency-review` are required status checks | ruleset, `.github/workflows/` |
| Plan reviewed before apply | Plan is commented on the PR for each touched stage | `tf-plan.yml` |
| Human approval to apply | `production` environment with required reviewers, no self-review, `main` only | `scripts/apply-branch-protection.sh` |
| Serial applies | `concurrency: tf-apply`, no cancellation mid-apply | `tf-apply.yml` |
| Drift detection | Nightly plan, issue on drift | `drift-detect.yml` |
| Reproducible toolchain | Terraform `1.16.6`, providers `~> 8.5` with a committed lock file, actions pinned to commit SHA, pre-commit hooks pinned by tag | `.terraform-version`, `.terraform.lock.hcl`, workflows |
| Supply chain | Modules pinned by tag from one internal repository, Dependabot for actions, Terraform and hooks, dependency review on PRs | `dependabot.yml` |

### Identity and access

| Control | Implementation | Where |
|---|---|---|
| No long-lived credentials | OIDC only. Service account key creation blocked org-wide. Key upload stays on the Google organization security baseline | `1-org/policies/org-policies/iam.yaml`, `2-cicd-identity` |
| Least privilege automation | Separate plan (read-only) and apply identities per repository | `0-core-projects/main.tf` |
| Pull requests cannot write | Plan identity is reachable from any ref, apply identity only from `refs/heads/main`; plans run with `-lock=false` and `objectViewer` | `2-cicd-identity/main.tf`, `tf-plan.yml` |
| Only our repositories and owner can mint tokens | Provider `attribute_condition` lists the owner and each repository | `2-cicd-identity/main.tf` |
| Only approved OIDC issuers | `iam.workloadIdentityPoolProviders` | `1-org/org-policies.tf` |
| Only our directory can be granted access | `iam.allowedPolicyMemberDomains` | Google organization security baseline. This stage does not manage it. |
| Groups, not users | All human grants in code are to groups | `1-org`, `3-workload-projects/data` |
| Default service accounts removed | `default_service_account = "delete"` in every project | stages 0 and 3 |
| Additive org IAM | Org level IAM here is additive, so nothing it did not create is removed | `1-org/main.tf` |

### Data protection

| Control | Implementation | Where |
|---|---|---|
| State encrypted with a customer managed key | CMEK, 90 day rotation | `0-core-projects/main.tf` |
| Public access impossible | `storage.publicAccessPrevention` in `1-org`. `storage.uniformBucketLevelAccess` is the Google organization security baseline. Bucket level `public_access_prevention = enforced` | `1-org`, all buckets |
| TLS only | `storage.secureHttpTransport` | `1-org/policies/org-policies/storage.yaml` |
| State history | Versioning, 7 day soft delete, 90 day noncurrent pruning | `0-core-projects/main.tf` |
| Data residency | `gcp.resourceLocations` | `1-org/org-policies.tf` |
| No public IPs by default | `compute.vmExternalIpAccess` deny all, `sql.restrictPublicIp` | `1-org/org-policies.tf` |

### Logging and monitoring

| Control | Implementation | Where |
|---|---|---|
| Admin activity and data access audit logs for every service | `logging_data_access.allServices` | `1-org/main.tf` |
| Central, tamper-resistant audit log | Organization sink to a project-level log bucket in the logging project, retention at least 365 days, lock available | `1-org/main.tf` |
| Central VPC flow logs | Separate organization sink to the `org-network` bucket. Flow logs are not mixed into the audit bucket | `1-org/main.tf` |
| Storage access logging | Every Terraform state bucket logs to an access log bucket with a retention policy | `0-core-projects/main.tf` |
| Workload state encrypted with a customer managed key | One keyring per workload project, 90 day rotation, used by that project's state bucket | `3-workload-projects/main.tf` |

### Platform baseline

| Control | Implementation |
|---|---|
| No default network | `compute.skipDefaultNetworkCreation`, `auto_create_network = false` |
| OS Login, no serial port, Shielded VM | `compute.requireOsLogin`, `compute.disableSerialPortAccess`, `compute.requireShieldedVm` |
| No default IAM grants to default service accounts | `iam.automaticIamGrantsForDefaultServiceAccounts`, already set by the Google organization security baseline |
| Cloud Run requires IAM invoker | Constraint `run.requireInvokerIam` is not available on this organization, so it is not set |
| Shared VPC lien cannot be removed casually | `compute.restrictXpnProjectLienRemoval` |
| Core and workload projects cannot be deleted by a stray apply | `deletion_policy = "PREVENT"`, folders with `deletion_protection` |

### Repository hygiene (mandatory pre-commit)

`terraform fmt`, `terraform validate`, `tflint` (naming, documented and typed variables and outputs, unused declarations, Google ruleset), `terraform-docs`, `checkov` (Terraform, GitHub Actions, secrets), `gitleaks`, private key detection, `actionlint`, `yamllint`, large file check, conventional commit messages, no state or plan files. CI runs the same hooks with `--all-files`, so skipping them locally only delays the failure.

## Exceptions

An exception is a deliberate departure from least privilege or from a control above. Each has an owner and a review date.

| Id | Exception | Reason | Owner | Review |
|---|---|---|---|---|
| EX-1 | `sa-tf-bootstrap-apply` holds `roles/resourcemanager.organizationAdmin` | Stage 1 manages organization IAM and organization policy. Reachable only from `main` of this repository, behind the `production` approval. | Platform engineering | Every 6 months |
| EX-2 | Plan identities hold `roles/viewer` and `roles/iam.securityReviewer` on the organization | A plan has to read every resource it manages. Read-only. | Platform engineering | Every 6 months |
| EX-3 | Workload deployers default to `roles/editor` plus `roles/projectIamAdmin` in their own project | A workload repository must create arbitrary resources in its project. Override per project with `deployer_roles` in the YAML. | Business unit owner | At project creation |
| EX-4 | Data access logs on for all services | Compliance needs outweigh log cost. Disable with `enable_data_access_logs = false` only with a written risk acceptance. | Security | Every year |
| EX-5 | Module sources are pinned by release tag, not by commit hash (checkov `CKV_TF_1` is skipped) | The modules repository is internal, and a commit hash cannot be known before the vendored repository is first pushed. Mitigation: a tag ruleset on `v*` in `gcp-terraform-module` (no deletion, no update), and re-vendoring only by reviewed PR. | Platform engineering | When the modules repository exists, then every year |

## Not covered here

These need a person, another repository or a tool outside Terraform. Do not claim them as done because this repository exists.

- Cloud Identity: groups, SSO, MFA enforcement, break-glass accounts and their monitoring
- GitHub organization settings: SSO, required 2FA, repository creation rules, secret scanning and push protection switches
- Billing export to BigQuery (a console step), budgets and alerts
- VPC Service Controls and Access Context Manager perimeters
- Security Command Center tier and notifications, alerting on the audit log (log based metrics and alert policies)
- Retention lock of the audit log bucket (irreversible; `lock_audit_log_bucket`) and of the access log bucket (`lock_log_retention`), a decision for the compliance owner
- Cloud NAT, firewall and Shared VPC (in `gcp-infrastructure-lz`)
- Application level controls inside workload projects (their own repositories)
- Evidence collection and periodic access review. Export the PR history, the plan comments, the `production` approvals and the audit log bucket as audit evidence.
