# 4-workload-projects

One project per YAML file under `data/projects/`. Each project gets baseline APIs, a Cloud KMS key, and a CMEK-encrypted state bucket. Two SAs are granted per project:

- `sa-tf-bootstrap` — project lifecycle only (`projectIamAdmin`, `serviceUsageAdmin`). Cannot deploy app resources.
- `sa-tf-workload-prod` or `sa-tf-workload-nonprod` — full deployer (`editor`, `projectIamAdmin`, `secretmanager.admin`, `serviceAccountAdmin`). Matched by the `environment` field in the YAML.

Both SA emails are read from Stage 1 remote state. Adding a new project requires only a new reviewed YAML file — no Terraform code changes.

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
| project | ../../gcp-terraform-module/modules/project | Creates one project per YAML file (for\_each over `local.projects`) |
| kms | ../../gcp-terraform-module/modules/kms | Per-project CMEK keyring + 90-day rotating key for state encryption (for\_each) |
| state | ../../gcp-terraform-module/modules/gcs | Per-project CMEK-encrypted state bucket (for\_each). Owned by the matching workload SA |

## Resources

| Name | Type | Purpose |
| ---- | ---- | ------- |
| data.google\_storage\_project\_service\_account.workload | data source | Looks up the GCS service agent per project so the CMEK key grant is made at apply time (for\_each) |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| prefix | Short organisation prefix used in every project id | `string` | n/a | yes |
| billing\_account\_id | Billing account id in `ABCDEF-123456-ABCDEF` format | `string` | n/a | yes |
| cost\_center | Default cost center label. Overridable per project via `cost_center` in the YAML | `string` | n/a | yes |
| region | Region for per-project state buckets and KMS keyrings | `string` | n/a | yes |
| allow\_destroy | Lift deletion protection | `bool` | `false` | no |

## YAML schema (`data/projects/*.yaml`)

| Field | Required | Description |
| ----- | -------- | ----------- |
| `business_unit` | yes | Must match a key in Stage 1 `var.business_units` (e.g. `business-unit-0`) |
| `environment` | yes | `prod` or `nonprod`. Determines which workload SA is granted |
| `short_name` | yes | Used in the project id: `<prefix>-<env_code>-<environment>-<short_name>` |
| `repository` | yes | GitHub repo that deploys into this project. Used as a label |
| `cost_center` | no | Overrides `var.cost_center` for this project |
| `extra_apis` | no | Additional APIs to enable on top of the baseline |
| `deployer_roles` | no | Override the default workload SA roles |
| `iam_groups` | no | Map of `"group:email" → [roles]`. Principals must be groups, never users |

## Outputs

| Name | Description |
| ---- | ----------- |
| projects | One entry per YAML file keyed by filename (without `.yaml`). Each entry includes `project_id`, `project_number`, `business_unit`, `environment`, `repository`, `state_bucket`, `kms_key_id`, and `workload_sa_email` (the SA that `gcp-workload` must use for this project) |
<!-- END_TF_DOCS -->
