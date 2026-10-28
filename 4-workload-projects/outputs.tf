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
      # SA that gcp-workload uses in its GitHub Actions workflow for this environment.
      workload_sa_email = (
        v.environment == "prod"
        ? data.terraform_remote_state.org.outputs.sa_emails.workload_prod
        : data.terraform_remote_state.org.outputs.sa_emails.workload_nonprod
      )
      # terraform_executor_email is the same value under the name gcp-infrastructure-lz reads
      # to grant compute.networkUser on Shared VPC subnets to the workload deployer SA.
      terraform_executor_email = (
        v.environment == "prod"
        ? data.terraform_remote_state.org.outputs.sa_emails.workload_prod
        : data.terraform_remote_state.org.outputs.sa_emails.workload_nonprod
      )
    }
  }
}
