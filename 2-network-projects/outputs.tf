output "projects" {
  description = "Hub and Shared VPC host projects under the Network folder. The landing zone builds VPCs in these projects and does not create them."
  value = {
    for k, m in module.project : k => {
      project_id      = m.project_id
      project_number  = m.number
      shared_vpc_host = local.projects[k].shared_vpc_host
    }
  }
}
