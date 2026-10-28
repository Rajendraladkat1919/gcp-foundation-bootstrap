output "access_log_bucket" {
  description = "Bucket that receives Cloud Storage access logs."
  value       = module.access_logs.name
}

output "automation_service_accounts" {
  description = "Terraform executor SA emails. Set these as GitHub Actions variables in each repo."
  value = {
    bootstrap      = module.sa_tf_bootstrap.email       # TF_SA_BOOTSTRAP in gcp-foundation-bootstrap
    infra_prod     = module.sa_tf_infra_prod.email      # TF_SA in gcp-infrastructure-lz (prod env)
    infra_nonprod  = module.sa_tf_infra_nonprod.email   # TF_SA in gcp-infrastructure-lz (nonprod env)
    workload_prod  = module.sa_tf_workload_prod.email   # TF_SA in gcp-workload (prod env)
    workload_nonprod = module.sa_tf_workload_nonprod.email # TF_SA in gcp-workload (nonprod env)
  }
}

output "wif_provider" {
  description = "WIF provider resource name. Set as WIF_PROVIDER in every GitHub repo that authenticates to GCP."
  value       = module.github_wif.provider_name
}

output "core_project_numbers" {
  description = "Project number of each core project, keyed by iac_core / billing / logging."
  value       = { for k, v in module.core_project : k => v.number }
}

output "core_projects" {
  description = "Project id of each core project, keyed by iac_core / billing / logging."
  value       = { for k, v in module.core_project : k => v.project_id }
}

output "kms_state_key_id" {
  description = "Id of the customer managed key that encrypts the state buckets."
  value       = module.kms.keys["tfstate"].id
}

output "state_buckets" {
  description = "Terraform state bucket names, keyed by bootstrap and lz."
  value       = { for k, v in module.state : k => v.name }
}

output "billing_export_dataset" {
  description = "BigQuery dataset for Cloud Billing export. Enable the export in the Cloud Billing console pointing to this dataset."
  value = {
    project    = module.core_project["billing"].project_id
    dataset_id = google_bigquery_dataset.billing_export.dataset_id
    location   = google_bigquery_dataset.billing_export.location
  }
}

output "xsiam_pubsub_topic" {
  description = "Pub/Sub topic id that receives org-level security events for XSIAM."
  value       = google_pubsub_topic.xsiam.id
}

output "prisma_cloud_sa_email" {
  description = "Prisma Cloud CSPM service account email. Null when enable_prisma_cloud is false."
  value       = var.enable_prisma_cloud ? module.sa_prisma_cloud[0].email : null
}
