output "projects" {
  description = "Everything the landing zone and the workload repositories need to know about each workload project, keyed by YAML file name."
  value = {
    for k, v in local.projects : k => {
      project_id       = module.project[k].project_id
      project_number   = module.project[k].number
      business_unit    = v.business_unit
      environment      = v.environment
      repository       = v.repository
      deployer_email   = module.deployer[k].email
      planner_email    = module.planner[k].email
      state_bucket     = module.state[k].name
      kms_key_id       = module.kms[k].keys["tfstate"].id
      shared_vpc_users = [module.deployer[k].iam_email]
    }
  }
}
