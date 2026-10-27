output "access_log_bucket" {
  description = "Bucket that receives Cloud Storage access logs."
  value       = module.access_logs.name
}

output "automation_service_accounts" {
  description = "Email of the Terraform executor. The GitHub variable TF_SA uses the execute key. sa-billing-reader and sa-logging-reader are not included."
  value = {
    execute = module.sa_terraform.email
  }
}

output "core_project_numbers" {
  description = "Project number of each core project."
  value = {
    iac_core = module.iac_core.number
    billing  = module.billing.number
    logging  = module.logging.number
  }
}

output "core_projects" {
  description = "Project id of each core project."
  value = {
    iac_core = module.iac_core.project_id
    billing  = module.billing.project_id
    logging  = module.logging.project_id
  }
}

output "kms_state_key_id" {
  description = "Id of the customer managed key that encrypts the state buckets."
  value       = module.kms.keys["tfstate"].id
}

output "state_buckets" {
  description = "Terraform state bucket of each repository, keyed by bootstrap and lz."
  value = {
    bootstrap = module.state_bootstrap.name
    lz        = module.state_lz.name
  }
}
