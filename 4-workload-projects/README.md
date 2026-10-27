# 4-workload-projects

One project per file in `data/projects/*.yaml`. Each gets the baseline APIs, `dev-terraform-execute` granted on the project, a Cloud KMS key and a state bucket encrypted with that key. The service account itself is created in `0-core-projects`.

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
| terraform | n/a |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| kms | ../../gcp-terraform-module/modules/kms | n/a |
| naming | ../../gcp-terraform-module/modules/naming | n/a |
| project | ../../gcp-terraform-module/modules/project | n/a |
| state | ../../gcp-terraform-module/modules/gcs | n/a |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| allow\_destroy | Lift deletion protection in this stage. Apply with -var allow\_destroy=true before terraform destroy. | `bool` | `false` | no |
| billing\_account\_id | Billing account id in ABCDEF-123456-ABCDEF format. | `string` | n/a | yes |
| cost\_center | Default cost center label, overridable per project in the YAML file. | `string` | n/a | yes |
| prefix | Short organization prefix used in every project id and bucket name. | `string` | n/a | yes |
| region | Region of the per project Terraform state bucket. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| projects | Everything the landing zone and the workload repositories need to know about each workload project, keyed by YAML file name. |
<!-- END_TF_DOCS -->
