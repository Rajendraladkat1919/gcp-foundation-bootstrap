output "access_log_bucket" {
  description = "Bucket that receives Cloud Storage access logs."
  value       = module.access_logs.name
}

output "automation_service_accounts" {
  description = "Terraform executor SA emails. Set bootstrap and infra as GitHub Actions variables. Workload SA emails are per-YAML — see workload_sa_emails output."
  value = {
    bootstrap = module.sa_tf_bootstrap.email # TF_SA_BOOTSTRAP in gcp-foundation-bootstrap
    infra     = module.sa_tf_infra.email     # TF_SA in gcp-infrastructure-lz (all envs)
  }
}

output "workload_sa_emails" {
  description = "Workload executor SA emails keyed by YAML filename. Each entry is the TF_SA for the repo named in that YAML file. Stage 4 outputs.projects also exposes the email per project."
  value       = { for k, v in module.sa_workload : k => v.email }
}

output "wif_provider" {
  description = "WIF provider resource name. Set as WIF_PROVIDER in every GitHub repo that authenticates to GCP."
  value       = google_iam_workload_identity_pool_provider.github_actions.name
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

output "lz_state_config" {
  description = <<-EOT
    Everything gcp-infrastructure-lz needs to configure its GitHub Actions variables.

    Required variables in the gcp-infrastructure-lz GitHub repo (Settings → Secrets and variables → Actions → Variables):

      TF_STATE_BUCKET           = state_bucket          (lz state bucket; also used as TF_VAR_lz_state_bucket in spoke stages)
      TF_BOOTSTRAP_STATE_BUCKET = bootstrap_state_bucket (read by spoke stages for workload project outputs)
      TF_IAC_PROJECT_ID         = core_projects.iac_core (billing project for all Terraform API calls)
      TF_SA                     = sa_email              (set by 0-core-projects: automation_service_accounts.infra)
      WIF_PROVIDER              = set by 0-core-projects: wif_provider output

    Network project IDs (set from: terraform -chdir=2-network-projects output projects):
      TF_HUB_PROJECT_ID           = projects["hub"].project_id
      TF_SPOKE_PROJECT_ID_PROD    = projects["shared-prod"].project_id
      TF_SPOKE_PROJECT_ID_NONPROD = projects["shared-nonprod"].project_id

    Each stage backend "gcs" block uses one of the prefixes below, all in TF_STATE_BUCKET:
      net-core-hub/backend.tf       → prefix = "terraform/state/net-core-hub"
      net-shared-prod/backend.tf    → prefix = "terraform/state/net-shared-prod"
      net-shared-non-prod/backend.tf→ prefix = "terraform/state/net-shared-non-prod"

    GitHub Actions environment gates (Settings → Environments):
      net-core-hub    → production  (hub changes affect both spokes; always production-gated)
      net-shared-prod → production
      net-shared-non-prod → nonprod (can deploy without production approval)
  EOT
  value = {
    state_bucket           = module.state["lz"].name
    bootstrap_state_bucket = module.state["bootstrap"].name
    sa_email               = module.sa_tf_infra.email
    prefixes = {
      net_core_hub       = "terraform/state/net-core-hub"
      net_shared_prod    = "terraform/state/net-shared-prod"
      net_shared_nonprod = "terraform/state/net-shared-non-prod"
    }
    pipeline_environments = {
      net_core_hub       = "production"
      net_shared_prod    = "production"
      net_shared_nonprod = "nonprod"
    }
  }
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
