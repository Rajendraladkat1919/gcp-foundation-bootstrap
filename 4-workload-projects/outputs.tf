output "projects" {
  description = "Everything the landing zone and the workload repositories need to know about each workload project, keyed by YAML file name."
  value = {
    for k, v in local.projects : k => {
      project_id               = module.project[k].project_id
      project_number           = module.project[k].number
      business_unit            = v.business_unit
      environment              = v.environment
      repository               = v.repository
      terraform_executor_email = local.terraform_executor_email
      state_bucket             = module.state[k].name
      kms_key_id               = module.kms[k].keys["tfstate"].id
      shared_vpc_users         = [local.terraform_executor]
    }
  }
}
