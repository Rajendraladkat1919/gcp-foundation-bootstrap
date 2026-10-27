# 2-network-projects

Shell projects only. Three projects under the Infrastructure / Network folder: the hub (`<prefix>-pr-net-core`) and one Shared VPC host per environment (`<prefix>-prod-net-spoke`, `<prefix>-non-prod-net-spoke`). With prefix `demo` those are `demo-pr-net-core`, `demo-prod-net-spoke` and `demo-non-prod-net-spoke`. Prod and non-prod are enabled as Shared VPC hosts. VPCs, firewall, NAT and workload attachment are built by `gcp-infrastructure-lz`.

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
| terraform | n/a |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| naming | ../../gcp-terraform-module/modules/naming | n/a |
| project | ../../gcp-terraform-module/modules/project | n/a |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| allow\_destroy | Lift deletion protection in this stage. Apply with -var allow\_destroy=true before terraform destroy. | `bool` | `false` | no |
| billing\_account\_id | Billing account id in ABCDEF-123456-ABCDEF format. | `string` | n/a | yes |
| cost\_center | Cost center label applied to every network project. | `string` | n/a | yes |
| prefix | Short organization prefix used in every project id and bucket name. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| projects | Hub and Shared VPC host projects under the Network folder. The landing zone builds VPCs in these projects and does not create them. |
<!-- END_TF_DOCS -->
