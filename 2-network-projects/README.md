# 2-network-projects

Three shell projects under `Infrastructure/Network`: the NCC hub (`net-core-hub`) and one Shared VPC host per environment (`net-shared-prod`, `net-shared-nonprod`). With prefix `demo` those are `demo-net-core-hub`, `demo-net-shared-prod`, `demo-net-shared-nonprod`.

After creating the projects this stage grants `network-tf-infra-sa` on hub + shared-prod + shared-nonprod. The same SA manages all three network projects. SA email is read from Stage 1 remote state.

VPCs, firewall, NAT, DNS and service-project attachment are built by `gcp-infrastructure-lz`, not here.

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
| terraform | n/a |

## Modules

| Name | Source | Purpose |
| ---- | ------ | ------- |
| naming | ../../gcp-terraform-module/modules/naming | Deterministic resource names from `prefix` |
| project | ../../gcp-terraform-module/modules/project | Creates all three network projects via `for_each` over `local.projects` |

## Resources

| Name | Type | Purpose |
| ---- | ---- | ------- |
| google\_project\_iam\_member.infra\_sa | resource | Cross-product IAM grants: `network-tf-infra-sa` on hub + shared-prod + shared-nonprod. 7 roles × 3 projects × 1 SA = 21 bindings via `for_each` over `local.infra_sa_grants` |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| prefix | Short organisation prefix used in every project id | `string` | n/a | yes |
| billing\_account\_id | Billing account id in `ABCDEF-123456-ABCDEF` format | `string` | n/a | yes |
| cost\_center | Cost center label applied to every network project | `string` | n/a | yes |
| allow\_destroy | Lift deletion protection | `bool` | `false` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| network\_folder\_id | Id of the `Infrastructure/Network` folder that contains all three projects |
| projects | Network projects keyed by `hub`, `shared-prod`, `shared-nonprod`. Each entry includes `project_id`, `project_number`, `shared_vpc_host`, `role`, `folder_id`. Read by `gcp-infrastructure-lz` to build VPCs |
| infra\_sa\_emails | `network-tf-infra-sa` email (read from Stage 1 remote state). Set as `TF_SA` in `gcp-infrastructure-lz` |
<!-- END_TF_DOCS -->
