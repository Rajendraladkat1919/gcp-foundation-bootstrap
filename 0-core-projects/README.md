# 0-core-projects

Org-level core projects, the customer managed key and Terraform state buckets, access logging, and the four automation service accounts (plan and apply for this repository and for `gcp-infrastructure-lz`).

**First apply is manual**, see [the runbook](../docs/runbook-bootstrap.md).

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
| google | 8.8.1 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| access\_logs | ../../gcp-terraform-module/modules/gcs | n/a |
| billing | ../../gcp-terraform-module/modules/project | n/a |
| billing\_exports | ../../gcp-terraform-module/modules/gcs | n/a |
| iac\_core | ../../gcp-terraform-module/modules/project | n/a |
| kms | ../../gcp-terraform-module/modules/kms | n/a |
| logging | ../../gcp-terraform-module/modules/project | n/a |
| naming | ../modules/naming | n/a |
| sa\_billing\_reader | ../../gcp-terraform-module/modules/iam-service-account | n/a |
| sa\_bootstrap\_apply | ../../gcp-terraform-module/modules/iam-service-account | n/a |
| sa\_bootstrap\_plan | ../../gcp-terraform-module/modules/iam-service-account | n/a |
| sa\_logging\_reader | ../../gcp-terraform-module/modules/iam-service-account | n/a |
| sa\_lz\_apply | ../../gcp-terraform-module/modules/iam-service-account | n/a |
| sa\_lz\_plan | ../../gcp-terraform-module/modules/iam-service-account | n/a |
| state\_bootstrap | ../../gcp-terraform-module/modules/gcs | n/a |
| state\_lz | ../../gcp-terraform-module/modules/gcs | n/a |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| access\_log\_retention\_days | Retention, in days, of the Cloud Storage access log bucket. | `number` | `400` | no |
| billing\_account\_id | Billing account id in ABCDEF-123456-ABCDEF format. | `string` | n/a | yes |
| cost\_center | Cost center label applied to every resource this stage creates. | `string` | n/a | yes |
| lock\_log\_retention | Lock the retention policy of the access log bucket. Irreversible, enable only after the retention period is confirmed. | `bool` | `false` | no |
| organization\_id | Organization id in organizations/NNNNNNNNNNNN format. | `string` | n/a | yes |
| prefix | Short organization prefix used in every project id and bucket name. | `string` | n/a | yes |
| region | Region for state buckets, the KMS key ring and the access log bucket. Must be allowed by the location org policy. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| access\_log\_bucket | Bucket that receives Cloud Storage access logs. |
| automation\_service\_accounts | Email of each automation service account, keyed by role. |
| core\_project\_numbers | Project number of each core project. |
| core\_projects | Project id of each core project. |
| kms\_state\_key\_id | Id of the customer managed key that encrypts the state buckets. |
| state\_buckets | Terraform state bucket of each repository, keyed by bootstrap and lz. |
<!-- END_TF_DOCS -->
