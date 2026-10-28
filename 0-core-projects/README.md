# 0-core-projects

Creates the org-root shell projects, CMEK state encryption, Terraform state buckets, **five scoped Terraform service accounts**, the GitHub OIDC Workload Identity pool, and operational readers. Everything else in the bootstrap depends on this stage.

**First apply is manual** — the state bucket does not exist yet. Apply locally, then migrate state into `demo-pr-tfstate-bootstrap`. See [the runbook](../docs/runbook-bootstrap.md).

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
| google-beta | ~> 8.5 |

## Modules

| Name | Source | Purpose |
| ---- | ------ | ------- |
| naming | ../../gcp-terraform-module/modules/naming | Deterministic resource names from `prefix` |
| core\_project | ../../gcp-terraform-module/modules/project | Creates all three core projects (`iac_core`, `billing`, `logging`) via `for_each` |
| kms | ../../gcp-terraform-module/modules/kms | CMEK keyring + 90-day rotating key for state encryption |
| access\_logs | ../../gcp-terraform-module/modules/gcs | GCS access-log bucket in the logging project |
| state | ../../gcp-terraform-module/modules/gcs | Bootstrap and LZ state buckets via `for_each`; IAM scoped per bucket |
| billing\_exports | ../../gcp-terraform-module/modules/gcs | GCS billing export bucket in the billing project |
| sa\_tf\_bootstrap | ../../gcp-terraform-module/modules/iam-service-account | Terraform executor for `gcp-foundation-bootstrap` — org-admin scope |
| sa\_tf\_infra\_prod | ../../gcp-terraform-module/modules/iam-service-account | Terraform executor for `gcp-infrastructure-lz` production environment |
| sa\_tf\_infra\_nonprod | ../../gcp-terraform-module/modules/iam-service-account | Terraform executor for `gcp-infrastructure-lz` nonprod environment |
| sa\_tf\_workload\_prod | ../../gcp-terraform-module/modules/iam-service-account | Terraform executor for `gcp-workload` production environment |
| sa\_tf\_workload\_nonprod | ../../gcp-terraform-module/modules/iam-service-account | Terraform executor for `gcp-workload` nonprod environment |
| sa\_billing\_reader | ../../gcp-terraform-module/modules/iam-service-account | Read-only billing export reader (operational, not a Terraform executor) |
| sa\_logging\_reader | ../../gcp-terraform-module/modules/iam-service-account | Read-only audit log reader (operational, not a Terraform executor) |
| sa\_prisma\_cloud | ../../gcp-terraform-module/modules/iam-service-account | Org read-only SA for Prisma Cloud CSPM. Created only when `enable_prisma_cloud = true` |
| github\_wif | ../../gcp-terraform-module/modules/iam-workload-identity-pool | GitHub OIDC Workload Identity pool and provider in `pr-iac-core` |

## Resources

| Name | Type | Purpose |
| ---- | ---- | ------- |
| google\_org\_policy\_policy.logging\_member\_domains | resource | Allows `cloud-storage-analytics@google.com` on the logging project only |
| google\_org\_policy\_policy.logging\_allowed\_members | resource | Enforces allowed principal sets on the logging project |
| google\_project\_service\_identity.gcs | resource | Provisions the GCS service agent so the CMEK key grant lands at apply time |
| google\_kms\_crypto\_key\_iam\_member.gcs\_agent | resource | Grants the GCS service agent encrypt/decrypt on the tfstate key |
| google\_bigquery\_dataset.billing\_export | resource | BQ dataset for Cloud Billing detailed and standard export |
| google\_pubsub\_topic.xsiam | resource | Pub/Sub topic for XSIAM SIEM. Stage 1 log sinks write here. 7-day message retention |
| google\_service\_account\_iam\_binding.wif\_bootstrap | resource | Authoritative WIF binding — `gcp-foundation-bootstrap` repo → `sa-tf-bootstrap` |
| google\_service\_account\_iam\_binding.wif\_infra\_prod | resource | Authoritative WIF binding — infra-lz repo + env=production → `sa-tf-infra-prod` |
| google\_service\_account\_iam\_binding.wif\_infra\_nonprod | resource | Authoritative WIF binding — infra-lz repo + env=nonprod → `sa-tf-infra-nonprod` |
| google\_service\_account\_iam\_binding.wif\_workload\_prod | resource | Authoritative WIF binding — workload repo + env=production → `sa-tf-workload-prod` |
| google\_service\_account\_iam\_binding.wif\_workload\_nonprod | resource | Authoritative WIF binding — workload repo + env=nonprod → `sa-tf-workload-nonprod` |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| prefix | Short organisation prefix used in every project id and bucket name | `string` | n/a | yes |
| organization\_id | Organisation id in `organizations/NNNNNNNNNNNN` format | `string` | n/a | yes |
| billing\_account\_id | Billing account id in `ABCDEF-123456-ABCDEF` format | `string` | n/a | yes |
| cost\_center | Cost center label applied to every resource this stage creates | `string` | n/a | yes |
| region | Region for state buckets, KMS keyring and access log bucket | `string` | n/a | yes |
| github\_org | GitHub organisation name (slug only, not a URL). Used in WIF pool condition and SA binding conditions | `string` | n/a | yes |
| bootstrap\_repository | GitHub repo for `gcp-foundation-bootstrap`. Only this repo may impersonate `sa-tf-bootstrap` | `string` | `"gcp-foundation-bootstrap"` | no |
| infra\_lz\_repository | GitHub repo for `gcp-infrastructure-lz`. `sa-tf-infra-prod/nonprod` are scoped to this repo | `string` | `"gcp-infrastructure-lz"` | no |
| workload\_repository | GitHub repo for `gcp-workload`. `sa-tf-workload-prod/nonprod` are scoped to this repo | `string` | `"gcp-workload"` | no |
| access\_log\_retention\_days | Retention in days for the GCS access log bucket | `number` | `400` | no |
| lock\_log\_retention | Lock the access log bucket retention policy. Irreversible | `bool` | `false` | no |
| allow\_destroy | Lift deletion protection. Use `-var allow_destroy=true` before destroy | `bool` | `false` | no |
| enable\_prisma\_cloud | Create `sa-prisma-cloud` with org read-only access for Prisma Cloud CSPM | `bool` | `false` | no |
| enable\_scc | Enable Security Command Center resources. Requires SCC Premium activated manually first | `bool` | `false` | no |
| security\_contact\_email | Email for Essential Contacts security category and SCC findings. Leave empty to skip | `string` | `""` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| automation\_service\_accounts | All five Terraform executor SA emails keyed by `bootstrap`, `infra_prod`, `infra_nonprod`, `workload_prod`, `workload_nonprod`. Set the matching email as `TF_SA` in each downstream repo. |
| wif\_provider | WIF provider resource name. Set as `WIF_PROVIDER` in every GitHub repo that authenticates to GCP. |
| core\_projects | Project ids of the three core projects keyed by `iac_core`, `billing`, `logging` |
| core\_project\_numbers | Project numbers keyed by `iac_core`, `billing`, `logging` |
| kms\_state\_key\_id | Id of the CMEK key that encrypts the bootstrap and LZ state buckets |
| state\_buckets | State bucket names keyed by `bootstrap` and `lz` |
| access\_log\_bucket | Bucket that receives GCS access logs for all Stage 0 buckets |
| billing\_export\_dataset | BigQuery dataset details for Cloud Billing export (`project`, `dataset_id`, `location`) |
| xsiam\_pubsub\_topic | Pub/Sub topic id that receives org-level security events for XSIAM |
| prisma\_cloud\_sa\_email | Prisma Cloud CSPM SA email. Register in Prisma Cloud → Settings → Cloud Accounts. Null when `enable_prisma_cloud = false` |
<!-- END_TF_DOCS -->
