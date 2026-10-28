# 1-org

Folder hierarchy, 29 organisation policies (compute, IAM, storage, SQL, GKE, BigQuery, Cloud Run, Cloud Functions), 4 org-level audit sinks + XSIAM Pub/Sub sink, 10 config-change monitoring alerts, 6 custom IAM roles, Essential Contacts, Okta group bindings, and optional Security Command Center notification config. Org-level IAM is additive only.

Outputs `sa_emails` and `folder_ids` are the cross-stage contracts read by Stages 2 and 4 via remote state.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | ~> 1.16.6 |
| google | ~> 8.5 |
| google-beta | ~> 8.5 |

## Providers

| Name | Version |
| ---- | ------- |
| google | ~> 8.5 |

## Modules

| Name | Source | Purpose |
| ---- | ------ | ------- |
| naming | ../../gcp-terraform-module/modules/naming | Deterministic resource names from `prefix` |
| audit\_log\_bucket | ../../gcp-terraform-module/modules/logging-bucket | Org-wide audit log bucket in the logging project (400-day default) |
| network\_log\_bucket | ../../gcp-terraform-module/modules/logging-bucket | VPC flow-log bucket — separate from audit, shorter retention (30-day default) |
| organization | ../../gcp-terraform-module/modules/organization | Org policies (YAML factory + inline), 4 logging sinks, org-level IAM |
| folder\_infrastructure | ../../gcp-terraform-module/modules/folder | Top-level `Infrastructure` folder |
| folder\_workloads | ../../gcp-terraform-module/modules/folder | Top-level `Workloads` folder |
| folder\_infrastructure\_children | ../../gcp-terraform-module/modules/folder | `Infrastructure/Network` sub-folder (for\_each) |
| folder\_business\_units | ../../gcp-terraform-module/modules/folder | One folder per business unit under `Workloads` (for\_each over `var.business_units`) |
| folder\_business\_unit\_environments | ../../gcp-terraform-module/modules/folder | `Prod` and `NonProd` folders under each business-unit folder (for\_each) |

## Resources

| Name | Type | Purpose |
| ---- | ---- | ------- |
| google\_logging\_organization\_sink.xsiam | resource | Org sink to the XSIAM Pub/Sub topic. Standalone so `writer_identity` is exposed for IAM |
| google\_pubsub\_topic\_iam\_member.xsiam\_logging\_writer | resource | Grants the XSIAM sink `writer_identity` `pubsub.publisher` on the XSIAM topic |
| google\_essential\_contacts\_contact.security | resource | Essential contact SECURITY/SUSPENSION. Created when `security_contact_email != ""` |
| google\_essential\_contacts\_contact.platform | resource | Essential contact TECHNICAL/LEGAL/BILLING. Bound to `groups.platform_engineers` |
| google\_organization\_iam\_member.prisma\_cloud\_scc\_viewer | resource | Grants Prisma Cloud SA `securitycenter.findingsViewer`. Created when `enable_scc = true` |
| google\_scc\_notification\_config.all\_findings | resource | Routes all active SCC findings to the XSIAM topic. Created when `enable_scc = true` |
| google\_pubsub\_topic\_iam\_member.scc\_publisher | resource | Grants SCC service agent `pubsub.publisher` on XSIAM topic. Created when `enable_scc = true` |
| google\_monitoring\_notification\_channel.security\_email | resource | Email alert channel. Created when `monitoring_notification_email != ""` |
| google\_logging\_metric.security | resource | 10 bucket-scoped log-based metrics (for\_each over `local.security_metrics` in monitoring.tf) |
| google\_monitoring\_alert\_policy.security | resource | 10 config-change alert policies (for\_each over `local.security_metrics` in monitoring.tf) |
| google\_organization\_iam\_custom\_role.roles | resource | 6 custom org-level IAM roles (for\_each over `local.custom_roles` in custom-roles.tf) |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| prefix | Short organisation prefix. Must match Stage 0 | `string` | n/a | yes |
| organization\_id | Organisation id in `organizations/NNNNNNNNNNNN` format | `string` | n/a | yes |
| domain | Primary domain for Essential Contacts and org policy condition variables | `string` | n/a | yes |
| region | Region of the central audit log bucket | `string` | n/a | yes |
| business\_units | Business units under Workloads. Key is a stable slug, `display_name` is the folder name, `group` is the Google group | `map(object({ display_name = string, group = string }))` | n/a | yes |
| groups | Okta-provisioned groups. `platform_engineers` is required. Optional fields default to `""` — no IAM binding is created when empty | `object({ platform_engineers = string, audit_viewers = optional(string,""), billing_viewers = optional(string,""), network_viewers = optional(string,""), security_reviewers = optional(string,""), break_glass = optional(string,"") })` | n/a | yes |
| enable\_data\_access\_logs | Enable ADMIN\_READ, DATA\_READ, DATA\_WRITE audit logs for every service | `bool` | `true` | no |
| enable\_scc | Create SCC notification config. Requires SCC Premium activated in Console first | `bool` | `false` | no |
| security\_contact\_email | Email for Essential Contacts SECURITY category. Leave empty to skip | `string` | `""` | no |
| monitoring\_notification\_email | Email for Cloud Monitoring alert notifications. Leave empty to skip | `string` | `""` | no |
| audit\_log\_retention\_days | Retention in days for the central audit log bucket (minimum 365) | `number` | `400` | no |
| network\_log\_retention\_days | Retention in days for the VPC flow-log bucket (minimum 1) | `number` | `30` | no |
| lock\_audit\_log\_bucket | Lock the audit log bucket retention. Irreversible | `bool` | `false` | no |
| allowed\_locations | Values for the `gcp.resourceLocations` org policy | `list(string)` | `["in:us-locations"]` | no |
| allowed\_workload\_identity\_issuers | OIDC issuers for the `iam.workloadIdentityPoolProviders` org policy | `list(string)` | `["https://token.actions.githubusercontent.com"]` | no |
| allow\_destroy | Lift deletion protection | `bool` | `false` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| sa\_emails | All five Terraform executor SA emails keyed by `bootstrap`, `infra_prod`, `infra_nonprod`, `workload_prod`, `workload_nonprod`. **Single source of truth** — Stages 2 and 4 read SA emails from here via remote state |
| folder\_ids | Folder ids keyed by logical path: `infrastructure`, `infrastructure/network`, `workloads`, `workloads/<bu>`, `workloads/<bu>/prod`, `workloads/<bu>/nonprod` |
| audit\_log\_bucket\_id | Id of the central audit log bucket |
| network\_log\_bucket\_id | Id of the central VPC flow-log bucket |
| org\_policies\_enforced | Names of all organisation policies managed by this stage |
| xsiam\_pubsub\_sink\_writer | `writer_identity` of the XSIAM org log sink |
| scc\_notification\_config\_name | Resource name of the SCC notification config. Null when `enable_scc = false` |
| monitoring\_alert\_policy\_names | Display names of the 10 config-change alert policies |
| custom\_role\_ids | Resource ids of the 6 custom IAM roles keyed by role id |
<!-- END_TF_DOCS -->
