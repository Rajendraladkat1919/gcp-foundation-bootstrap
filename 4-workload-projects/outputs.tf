output "projects" {
  description = "Everything gcp-workload and gcp-infrastructure-lz need per project, keyed by YAML file name."
  value = {
    for k, v in local.projects : k => {
      project_id     = module.project[k].project_id
      project_number = module.project[k].number
      business_unit  = v.business_unit
      environment    = v.environment
      repository     = v.repository
      state_bucket   = module.state[k].name
      kms_key_id     = module.kms[k].keys["tfstate"].id
      # Per-project SA: workload-{short_name}-{environment}-sa in pr-iac-core.
      # Set this as TF_SA in the GitHub Actions workflow for this repo.
      workload_sa_email        = "workload-${v.short_name}-${v.environment}-sa@${local.iac_core_project}.iam.gserviceaccount.com"
      # Same value under the name gcp-infrastructure-lz reads to grant compute.networkUser.
      terraform_executor_email = "workload-${v.short_name}-${v.environment}-sa@${local.iac_core_project}.iam.gserviceaccount.com"
    }
  }
}
