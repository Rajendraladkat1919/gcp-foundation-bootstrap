# 2-cicd-identity

GitHub OIDC workload identity pool and provider in the `iac-core` project, and the bindings that let each pipeline repository impersonate its plan and apply service accounts. Workload repositories are allowed to mint a token from the YAML files in stage 3. `cicd-runners` is allowed through `additional_repositories` and does not receive a service account here.

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
| github\_wif | ../../gcp-terraform-module/modules/iam-workload-identity-pool | n/a |
| naming | ../modules/naming | n/a |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| additional\_repositories | Extra repositories that may mint a token from this pool but do not get a bootstrap or landing-zone service account. cicd-runners is the usual entry. Workload repositories are read from stage 3 YAML and do not belong here. | `list(string)` | `[]` | no |
| github\_org | GitHub organization that owns the repositories. Tokens from any other owner are rejected by the provider. | `string` | n/a | yes |
| pipelines | Repositories allowed to impersonate automation service accounts. The plan service account is reachable from any ref of the repository (pull requests), the apply service account only from apply\_ref. | ```map(object({ repository = string plan_service_account = string apply_service_account = string apply_ref = optional(string, "refs/heads/main") }))``` | n/a | yes |
| prefix | Short organization prefix used in every project id and bucket name. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| github\_actions\_variables | Values to store as GitHub Actions repository variables (not secrets) in the pipeline repositories. |
| workload\_identity\_pool\_name | Fully qualified workload identity pool name, used to build principalSet members. |
| workload\_identity\_provider\_name | Fully qualified provider name. This is the WIF\_PROVIDER variable of every pipeline repository. |
<!-- END_TF_DOCS -->
