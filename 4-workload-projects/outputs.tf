output "projects" {
  description = "Everything gcp-workload needs per project, keyed by YAML file name."
  value = {
    for k, v in local.projects : k => {
      project_id   = module.project[k].project_id
      project_number = module.project[k].number
      business_unit  = v.business_unit
      environment    = v.environment
      repository     = v.repository
      state_bucket   = module.state[k].name
      kms_key_id     = module.kms[k].keys["tfstate"].id
      # SA to use in gcp-workload GitHub Actions workflow for this project's environment.
      workload_sa_email = (
        v.environment == "prod"
        ? "sa-tf-workload-prod@${local.iac_core_project}.iam.gserviceaccount.com"
        : "sa-tf-workload-nonprod@${local.iac_core_project}.iam.gserviceaccount.com"
      )
    }
  }
}
