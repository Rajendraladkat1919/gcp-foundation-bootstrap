# naming

Names shared by every stage and by `gcp-infrastructure-lz`. Creates nothing.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | ~> 1.16.6 |

## Providers

No providers.

## Modules

No modules.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| prefix | Short organization prefix used in every project id and bucket name, for example pe. Lowercase letters and digits, 2 to 10 characters. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| automation\_service\_account\_emails | Email of each automation service account, keyed by role (bootstrap\_plan, bootstrap\_apply, lz\_plan, lz\_apply). |
| automation\_service\_account\_ids | Account id (the part before the @) of each automation service account. |
| core\_project\_ids | Project id of each org-level core project, keyed by iac\_core, billing, logging. |
| core\_project\_names | Project name (without prefix) of each org-level core project. |
| environments | Environment short code and folder display name, keyed by prod and nonprod. |
| state\_bucket\_full\_names | Full GCS bucket names of the Terraform state buckets. |
| state\_bucket\_names | Bucket name suffixes (the gcs module adds the prefix). |
<!-- END_TF_DOCS -->
