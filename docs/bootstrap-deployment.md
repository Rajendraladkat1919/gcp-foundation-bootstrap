# Bootstrap deployment

What stages `0-core-projects` through `4-workload-projects` build, the roles and policies required to apply them, and the manual steps that Terraform cannot do.

This is the record of the applied foundation. The command-by-command procedure is [run-from-local-or-cloud-shell.md](run-from-local-or-cloud-shell.md). The designed control list is [controls.md](controls.md). Stage `2-network-projects` is in the repository and has not been applied on this organization yet. VPCs, firewall, NAT and service-project attachment stay in `gcp-infrastructure-lz`.

## Architecture pattern

This repository is a staged Cloud Foundation Fabric bootstrap (modules pinned to Fabric **v59.1.0**).

A person applies the four stages once, in order, with elevated organization access. After that, GitHub Actions is the intended operator: a pull request can impersonate only a read-only plan identity, and a write identity can be impersonated only from `refs/heads/main` of the matching repository. No service account keys are created.

Each stage has its own Terraform state object. They share one bucket and do not share one state file. A failure in a later stage does not roll back an earlier stage.

Core projects are created directly under the organization. They are not placed in a folder, so a folder move or a folder policy exception cannot take the state buckets, the CMEK key, or the central logs with it.

```text
Organization example.com (000000000000)
├── demo-pr-iac-core     state, CMEK, 5 Terraform SAs, WIF pool + provider
├── demo-pr-billing      billing export bucket, BigQuery billing_export dataset
├── demo-pr-logging      org audit logs, VPC flow logs, access logs, monitoring
├── Infrastructure/                              deletion protection on
│   └── Network/                                 all three network projects live here
│       ├── demo-net-core-hub                    NCC hub, VPN, Interconnect
│       ├── demo-net-shared-prod                 Shared VPC host — production
│       └── demo-net-shared-nonprod              Shared VPC host — non-production
└── Workloads/
    ├── Business Unit 0/
    │   ├── Prod/demo-pr-prod-bu-0
    │   └── Non-Prod/demo-np-nonprod-bu-0
    └── Business Unit 1/
        ├── Prod/demo-pr-prod-bu-1
        └── Non-Prod/demo-np-nonprod-bu-1
```

| Stage | State prefix in `demo-pr-tfstate-bootstrap` | Depends on |
|---|---|---|
| `0-core-projects` | `bootstrap/0-core-projects` | Organization, billing account |
| `1-org` | `bootstrap/1-org` | Stage 0 project IDs (naming module) |
| `2-network-projects` | `bootstrap/2-network-projects` | Stage 1 folder ID `infrastructure/network` |
| `4-workload-projects` | `bootstrap/3-workload-projects` | Stage 1 folder IDs and SA emails (remote state) |

Stage 3 (`3-cicd-identity`) was removed. The WIF pool and all SA WIF bindings are now in Stage 0 so identity exists before any CI pipeline runs.

`gcp-infrastructure-lz` reads `projects` from Stage 2 (network projects) and Stage 1 (`folder_ids`) to build VPCs. It does not create host projects. `gcp-workload` reads `projects` from Stage 4 for project IDs and workload SA emails. Changing any of those outputs is a breaking change for the downstream repositories.

Workload projects are not listed in HCL. One YAML file under `4-workload-projects/data/projects/` creates one project, two identities, one CMEK key, and one state bucket.

## Identity of this deployment

| Item | Value |
|---|---|
| Organization | `example.com`, `organizations/000000000000` |
| Directory customer | `C00000000` |
| Billing account | `000000-000000-000000` |
| Prefix | `demo` |
| Region | `us-west2` |
| GitHub organization | `<github-org>` (the name only, not `https://github.com/<github-org>`) |
| Break-glass user for the first apply | `operator@example.com` |
| Module source used on the machine that applied | `../../gcp-terraform-module` |

`0-core-projects/terraform.tfvars` sets `github_org`. Use the GitHub organization name, not a URL (e.g. `"acme"` not `"https://github.com/acme"`). A wrong value here causes WIF to reject every token from your repositories.

## Prerequisites

Terraform does not create any of these.

| Prerequisite | Required value or condition |
|---|---|
| Google Cloud organization | Already exists, with the id above |
| Billing account | Open, parented to this organization |
| Billing project quota | A new account links 5 projects. Free a slot before stage 3 creates the fifth `demo-` project |
| Cloud Identity groups | Already exist. This Terraform does not create them |
| GitHub organization and repository names | `<github-org>`, plus the repository names in stage 2 and in the stage 3 YAML files |
| Prefix | `demo`, matching `^[a-z][a-z0-9]{1,9}$` |
| Region | `us-west2`. The API name has no extra hyphen |
| Person applying | Signed in as `operator@example.com` with the roles in the next section |
| Module checkout | `gcp-terraform-module` is a sibling of `gcp-foundation-bootstrap` under `repos/` |

Groups that must exist before stage 1:

| tfvars key | Email | Grant this stage makes |
|---|---|---|
| `groups.platform_engineers` | `platform-engineers@example.com` | Organization viewer roles listed below |
| `business_units.business-unit-0.group` | `business-unit-0@example.com` | Folder viewer on Business Unit 0, and `roles/viewer` on both workload projects |

## Roles the person needed

`roles/owner` on the organization does not include `resourcemanager.folders.create`, and it does not make the user a Workspace directory administrator.

| Role | Scope | Why this apply needed it |
|---|---|---|
| `roles/resourcemanager.organizationAdmin` | Organization | Organization IAM and log sinks |
| `roles/resourcemanager.projectCreator` | Organization | Create projects |
| `roles/resourcemanager.folderAdmin` | Organization | Create folders. Granted during stage 1 after Owner returned 403 |
| `roles/orgpolicy.policyAdmin` | Organization | Organization policies and the logging-project exception |
| `roles/logging.configWriter` | Organization | Organization log sinks |
| `roles/billing.admin` | Billing account `000000-000000-000000` | See linked projects and disable billing on the extra project |
| `roles/billing.user` | Billing account | Link new projects |

`roles/cloudidentity.groupsAdmin` was granted on the organization and was still not enough to create groups. Cloud Identity returned `403` error 2015, and admin.google.com rejected `rala`. Group creation is a Workspace directory action. A Workspace Super Admin or Groups Admin has to create the groups, or the groups are created in the Google Groups console when the directory allows it. This deployment used the Groups console.

## Roles Terraform granted

These stay after the human's temporary roles are removed.

The first apply created `sa-tf-bootstrap-plan`, `sa-tf-bootstrap-apply`, `sa-tf-lz-plan`, `sa-tf-lz-apply`, and `sa-wlp-deployer` plus `sa-wlp-planner` in each workload project. The current code replaces those with `dev-terraform-execute` on the next apply of stages 0, 1, 3 and 4. `sa-billing-reader` and `sa-logging-reader` stay.

### Terraform executor service accounts in `demo-pr-iac-core`

See ADR 0007 for the full rationale. All five SAs live in `pr-iac-core`. Permissions are granted progressively as the skeleton is built.

| Account | Bound repository | Org / cross-project roles |
|---|---|---|
| `sa-tf-bootstrap` | `gcp-foundation-bootstrap` (any env) | Org: `organizationAdmin`, `folderAdmin`, `projectCreator`, `orgpolicy.policyAdmin`, `logging.configWriter`, `essentialcontacts.admin`, `browser`, `viewer`, `iam.securityReviewer`. Billing: `billing.user`, `billing.viewer`. On `pr-iac-core`: KMS admin, SA admin, WIF pool admin, Pub/Sub admin, BigQuery admin, storage admin. On `pr-logging`: logging admin, storage admin. On `pr-billing`: BigQuery admin. State `bootstrap` bucket: `objectAdmin`. |
| `sa-tf-infra-prod` | `gcp-infrastructure-lz` (env=production) | On hub + shared-prod: `compute.networkAdmin`, `compute.securityAdmin`, `dns.admin`, `networkconnectivity.admin`, `servicenetworking.networksAdmin`, `compute.xpnAdmin`. State `lz` bucket: `objectAdmin`. |
| `sa-tf-infra-nonprod` | `gcp-infrastructure-lz` (env=nonprod) | Same roles as infra-prod on hub + shared-nonprod. State `lz` bucket: `objectAdmin`. |
| `sa-tf-workload-prod` | `gcp-workload` (env=production) | On prod workload projects: `editor`, `projectIamAdmin`, `secretmanager.admin`, `serviceAccountAdmin`. Each prod workload state bucket: `objectAdmin`. |
| `sa-tf-workload-nonprod` | `gcp-workload` (env=nonprod) | Same roles on nonprod workload projects and state buckets. |

`dev-terraform-execute` holding `roles/resourcemanager.organizationAdmin` is exception EX-1 in [controls.md](controls.md). The apply workflow still waits for the GitHub `production` environment. The account itself can write from a pull request of a bound repository.

### Folder roles for `dev-terraform-execute`

| Folder | Roles |
|---|---|
| `Infrastructure` | `compute.xpnAdmin`, `resourcemanager.folderViewer` |
| `Infrastructure/Network` | `compute.networkAdmin`, `compute.securityAdmin`, `dns.admin`, `networkconnectivity.admin`, `servicenetworking.networksAdmin`, `compute.xpnAdmin` |
| `Workloads` | `compute.xpnAdmin`, `resourcemanager.folderViewer` |

### Human groups

| Principal | Roles |
|---|---|
| `group:platform-engineers@example.com` | On the organization: `iam.securityReviewer`, `logging.viewer`, `orgpolicy.policyViewer`, `resourcemanager.folderViewer`, `resourcemanager.organizationViewer` |
| `group:business-unit-0@example.com` | `resourcemanager.folderViewer` on folder Business Unit 0. `roles/viewer` on `demo-np-nonprod-bu-0` and `demo-pr-prod-bu-0` |

### Readers

| Account | Project | Roles |
|---|---|---|
| `sa-billing-reader@demo-pr-billing.iam.gserviceaccount.com` | billing export bucket | `storage.objectViewer` |
| `sa-logging-reader@demo-pr-logging.iam.gserviceaccount.com` | `demo-pr-logging` | `logging.viewer`, `logging.privateLogViewer` |

### Workload access

`dev-terraform-execute` is granted on each workload project. Stage 3 lets `<github-org>/<repository>` impersonate it from any ref. There is no per-project deployer or planner.

## Policies

### Left on Google's organization security baseline

These already existed. Terraform does not manage them. They were imported once and then removed from state with `terraform state rm` so a later apply would not delete them.

- `iam.allowedPolicyMemberDomains`
- `iam.disableServiceAccountKeyUpload`
- `iam.automaticIamGrantsForDefaultServiceAccounts`
- `storage.uniformBucketLevelAccess`

Do not import them again.

`run.requireInvokerIam` is not available on this organization. It is not set.

### Managed by stage 1

Variable-driven rules in `1-org/org-policies.tf`:

| Policy | Value |
|---|---|
| `gcp.resourceLocations` | `in:us-locations` |
| `iam.workloadIdentityPoolProviders` | `https://token.actions.githubusercontent.com` |

YAML files under `1-org/policies/org-policies/`:

| File | Policies |
|---|---|
| `compute.yaml` | `disableGuestAttributesAccess`, `disableSerialPortAccess`, `requireOsLogin`, `requireShieldedVm`, `restrictXpnProjectLienRemoval`, `skipDefaultNetworkCreation` enforced. `restrictProtocolForwardingCreationForTypes` allows `INTERNAL` only. `vmExternalIpAccess` denies all |
| `iam.yaml` | `iam.disableServiceAccountKeyCreation` enforced |
| `sql.yaml` | `restrictAuthorizedNetworks`, `restrictPublicIp` enforced |
| `storage.yaml` | `publicAccessPrevention`, `secureHttpTransport` enforced |
| `essentialcontacts.yaml` | `allowedContactDomains` allows `@example.com` |

Organization IAM in stage 1 is additive. This stage does not remove members it did not add.

### Exception on `demo-pr-logging` only

Google's domain restriction blocks `group:cloud-storage-analytics@google.com`, and that group is who writes Cloud Storage access logs. Stage 0 sets two project policies on `demo-pr-logging` only:

- `iam.allowedPolicyMemberDomains` with `allow_all` and `inherit_from_parent = false`
- `iam.managed.allowedPolicyMembers` enforced, allowing `group:cloud-storage-analytics@google.com`, `serviceAccount:cloud-storage-analytics@google.com`, and principal set `//cloudresourcemanager.googleapis.com/organizations/000000000000`

The access-log bucket then grants that group `roles/storage.objectCreator`. The rest of the organization keeps the baseline domain restriction.

## What was created

Projects use `deletion_policy = PREVENT`. Folders use `deletion_protection = true`. `terraform destroy` is not the way to change this foundation.

### Stage 0

| Resource | Name |
|---|---|
| Project | `demo-pr-iac-core` |
| Project | `demo-pr-billing` |
| Project | `demo-pr-logging` |
| KMS | keyring `tfstate` in `us-west2` on `demo-pr-iac-core`, key `tfstate`, rotation 90 days |
| Bucket | `demo-pr-tfstate-bootstrap` (CMEK, versioning, 7-day soft delete) |
| Bucket | `demo-pr-tfstate-lz` (same controls, for `gcp-infrastructure-lz`) |
| Bucket | `demo-pr-access-logs` in `demo-pr-logging` |
| Bucket | `demo-pr-billing-exports` in `demo-pr-billing` |
| Service accounts | First apply: `sa-tf-bootstrap-plan`, `sa-tf-bootstrap-apply`, `sa-tf-lz-plan`, `sa-tf-lz-apply`, `sa-billing-reader`, `sa-logging-reader`. Next apply of stage 0 replaces the four `sa-tf-*` accounts with `dev-terraform-execute` and keeps the two readers |

Default compute service accounts on these projects are deleted. APIs enabled on every core project include Cloud Billing, Resource Manager, IAM, IAM Credentials, Service Usage, STS, Logging, Monitoring, BigQuery, Secret Manager, and Cloud Storage. `demo-pr-iac-core` also has Cloud KMS. `demo-pr-iac-core` and `demo-pr-logging` also have Organization Policy.

### Stage 1

| Folder path | Folder id |
|---|---|
| `infrastructure` | `folders/554535761631` |
| `infrastructure/network` | `folders/734204457066` |
| `infrastructure/nonprod` | `folders/781151064797` |
| `infrastructure/prod` | `folders/184879230005` |
| `workloads` | `folders/510189971648` |
| `workloads/business-unit-0` | `folders/303503222372` |
| `workloads/business-unit-0/nonprod` | `folders/559409431088` |
| `workloads/business-unit-0/prod` | `folders/25123494968` |

Also created:

- Organization data-access audit config for every service (`ADMIN_READ`, `DATA_READ`, `DATA_WRITE`).
- Log bucket `projects/demo-pr-logging/locations/us-west2/buckets/org-audit` (retention 400 days, not locked).
- Log bucket `projects/demo-pr-logging/locations/us-west2/buckets/org-network` (retention 30 days).
- Organization sink `audit` into `org-audit`.
- Organization sink `network` into `org-network`, filtered to VPC flow logs.
- The organization policies in the table above.
- The group and landing-zone folder IAM bindings.

### Stage 2

In project `demo-pr-iac-core`:

- Workload Identity pool `github`.
- Workload Identity provider `github-actions`.
- Provider condition: `assertion.repository_owner` must be `<github-org>`, and `assertion.repository` must be one of `<github-org>/gcp-foundation-bootstrap`, `<github-org>/gcp-infrastructure-lz`, `<github-org>/cicd-runners`, `<github-org>/gcp-wlp-prod-bu-0`, `<github-org>/gcp-wlp-nonprod-bu-0`.
- First apply: `roles/iam.workloadIdentityUser` on the plan accounts for any ref, and on the apply accounts only for `refs/heads/main`.
- Next apply of this stage: `roles/iam.workloadIdentityUser` on `dev-terraform-execute` for any ref of the bootstrap repository, the landing-zone repository and each workload repository.

`cicd-runners` may mint a token. It does not receive a Terraform service account.

### Stage 3

| | Non-prod | Prod |
|---|---|---|
| Project | `demo-np-nonprod-bu-0` | `demo-pr-prod-bu-0` |
| Project number | `176333189171` | `624365931161` |
| Parent | Business Unit 0 / Non-Prod | Business Unit 0 / Prod |
| GitHub repository | `gcp-wlp-nonprod-bu-0` | `gcp-wlp-prod-bu-0` |
| Terraform identity | `dev-terraform-execute@demo-pr-iac-core.iam.gserviceaccount.com` after the next apply. The first apply created `sa-wlp-deployer` and `sa-wlp-planner` in each project; that apply deletes them | `dev-terraform-execute@demo-pr-iac-core.iam.gserviceaccount.com` |
| CMEK | `projects/demo-np-nonprod-bu-0/locations/us-west2/keyRings/workload/cryptoKeys/tfstate` | `projects/demo-pr-prod-bu-0/locations/us-west2/keyRings/workload/cryptoKeys/tfstate` |
| State bucket | `demo-np-nonprod-bu-0-tfstate` | `demo-pr-prod-bu-0-tfstate` |

Each project gets the baseline APIs (the stage 0 set, plus Cloud KMS and Compute). `dev-terraform-execute` is the Shared VPC user candidate. The host projects are `2-network-projects`, under the Network folder, and are not applied on this organization yet.

## Manual steps in this deployment

| Step | Why it was manual |
|---|---|
| Create the three groups in the Groups console | `rala` is not a Workspace directory administrator. API create returned error 2015 |
| Grant `roles/resourcemanager.folderAdmin` to `rala` | Organization Owner cannot create folders |
| Apply stage 0 against local state, then migrate into `demo-pr-tfstate-bootstrap` | The bucket is created by that same apply |
| Refresh `GOOGLE_OAUTH_ACCESS_TOKEN` before `terraform init` | A stale token in the shell is preferred over `gcloud` login and returns 401 |
| Disable billing on `example-extra-project` (My First Project) | The billing account already had five linked projects: that project plus `demo-pr-iac-core`, `demo-pr-billing`, `demo-pr-logging`, and `demo-np-nonprod-bu-0` |
| `terraform untaint` of `demo-pr-prod-bu-0` | The project was created, billing link failed, and Terraform marked it tainted. The next plan tried to delete it. `PREVENT` stopped the delete |

`hidden-cosmos-512715-j9` is another My First Project in the organization. It was not linked to this billing account and was left alone.

## Code changes made so this organization could apply

These are in the stage directories. They are not one-off console edits.

| Change | Reason |
|---|---|
| GCS CMEK member is `service-<project number>@gs-project-accounts.iam.gserviceaccount.com` | `google_project_service_identity.email` is null at plan time |
| Organization IAM uses the numeric organization id | `google_organization_iam_member.org_id` rejects the `organizations/` prefix. Project parent still uses `organizations/000000000000` |
| Logging-project org policies above | Domain restriction rejected `cloud-storage-analytics@google.com` with HTTP 412 |
| Baseline policies removed from Terraform after `terraform state rm` | Managing them would adopt Google's defaults and a destroy would delete them |
| `run.requireInvokerIam` removed | The constraint returned 404 on this organization |
| Organization policies other than locations and issuers live in `1-org/policies/org-policies/*.yaml` | Same factory the organization module already reads. `var.org_policies` still supplies the two values that come from variables |
| `org_policies_enforced` reads `module.organization.organization_policies_ids` | Reading only `local.org_policies` hid the YAML policies from the output |
| `google_cloud_identity_group` removed | The groups already exist. The directory rejected API creates |
| Stage 2 `github_org` is `<github-org>` | The provider compares it to `assertion.repository_owner`, which is the organization name |

## Not built

- VPC Service Controls, custom organization-policy constraints, Security Command Center Premium, and security projects.
- Cloud Identity group resources.
- BigQuery billing export. The bucket `demo-pr-billing-exports` exists. The export configuration is a console step.
- Retention lock on `org-audit` and on `demo-pr-access-logs`. Locking is irreversible and is off by default.
- Hub, prod Shared VPC host and non-prod Shared VPC host projects. Stage `2-network-projects` creates them under Network. This deployment stopped at stage 3.
- VPCs, Cloud NAT, firewalls and Shared VPC service-project attachment. Those belong to `gcp-infrastructure-lz`, which runs after stage 4.
- Removal of `rala` as Owner of the three core projects. The project creator is Owner until that binding is removed. Do that only after GitHub apply works.
- GitHub variable `WIF_PROVIDER`, branch protection, and the `production` environment. Stage 2 created the pool. The GitHub side is still [the repository README](../README.md).
