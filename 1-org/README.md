# 1-org

Folder hierarchy (Infrastructure, Workloads, business units), organization policies, organization audit logging with a central sink, a separate VPC flow-log sink, and group access. Org level IAM is additive only.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | ~> 1.16.6 |
| google | ~> 8.5 |
| google-beta | ~> 8.5 |

## Providers

No providers.

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| audit\_log\_bucket | ../../gcp-terraform-module/modules/logging-bucket | n/a |
| folder\_business\_unit\_environments | ../../gcp-terraform-module/modules/folder | n/a |
| folder\_business\_units | ../../gcp-terraform-module/modules/folder | n/a |
| folder\_infrastructure | ../../gcp-terraform-module/modules/folder | n/a |
| folder\_infrastructure\_children | ../../gcp-terraform-module/modules/folder | n/a |
| folder\_workloads | ../../gcp-terraform-module/modules/folder | n/a |
| naming | ../../gcp-terraform-module/modules/naming | n/a |
| network\_log\_bucket | ../../gcp-terraform-module/modules/logging-bucket | n/a |
| organization | ../../gcp-terraform-module/modules/organization | n/a |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| allow\_destroy | Lift deletion protection in this stage. Apply with -var allow\_destroy=true before terraform destroy. | `bool` | `false` | no |
| allowed\_locations | Value groups or regions allowed by the gcp.resourceLocations organization policy. | `list(string)` | ```[ "in:us-locations" ]``` | no |
| allowed\_workload\_identity\_issuers | OIDC issuers allowed in workload identity pool providers. | `list(string)` | ```[ "https://token.actions.githubusercontent.com" ]``` | no |
| audit\_log\_retention\_days | Retention, in days, of the central organization audit log bucket. | `number` | `400` | no |
| business\_units | Business units under the Workloads folder. The key is a stable slug, display\_name is the folder name, group is the Google group that can browse the folder. | ```map(object({ display_name = string group = string }))``` | n/a | yes |
| domain | Primary domain. Essential contacts are limited to it. | `string` | n/a | yes |
| enable\_data\_access\_logs | Turn on ADMIN\_READ, DATA\_READ and DATA\_WRITE audit logs for every service. Required by most compliance frameworks, and billed by log volume. | `bool` | `true` | no |
| groups | Google groups, as email addresses. They must already exist in Cloud Identity. | ```object({ platform_engineers = string })``` | n/a | yes |
| lock\_audit\_log\_bucket | Lock the audit log bucket retention. Irreversible, enable only once the retention period is confirmed. | `bool` | `false` | no |
| network\_log\_retention\_days | Retention, in days, of the central VPC flow log bucket. Flow logs are high volume, so this is shorter than the audit bucket. | `number` | `30` | no |
| organization\_id | Organization id in organizations/NNNNNNNNNNNN format. | `string` | n/a | yes |
| prefix | Short organization prefix used in every project id and bucket name. | `string` | n/a | yes |
| region | Region of the central audit log bucket. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| audit\_log\_bucket\_id | Id of the central audit log bucket. |
| folder\_ids | Folder ids keyed by path: infrastructure, infrastructure/network, infrastructure/prod, workloads, workloads/<business unit>/<environment>, and so on. |
| network\_log\_bucket\_id | Id of the central VPC flow log bucket. |
| org\_policies\_enforced | Names of the organization policies this stage manages. |
<!-- END_TF_DOCS -->
