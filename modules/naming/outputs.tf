output "automation_service_account_emails" {
  description = "Email of each automation service account, keyed by role (bootstrap_plan, bootstrap_apply, lz_plan, lz_apply)."
  value = {
    for k, v in local.automation_service_account_ids :
    k => "${v}@${local.core_project_ids["iac_core"]}.iam.gserviceaccount.com"
  }
}

output "automation_service_account_ids" {
  description = "Account id (the part before the @) of each automation service account."
  value       = local.automation_service_account_ids
}

output "core_project_ids" {
  description = "Project id of each org-level core project, keyed by iac_core, billing, logging."
  value       = local.core_project_ids
}

output "core_project_names" {
  description = "Project name (without prefix) of each org-level core project."
  value       = local.core_project_names
}

output "environments" {
  description = "Environment short code and folder display name, keyed by prod and nonprod."
  value       = local.environments
}

output "state_bucket_full_names" {
  description = "Full GCS bucket names of the Terraform state buckets."
  value       = { for k, v in local.state_bucket_names : k => "${var.prefix}-${v}" }
}

output "state_bucket_names" {
  description = "Bucket name suffixes (the gcs module adds the prefix)."
  value       = local.state_bucket_names
}
