output "network_folder_id" {
  description = "ID of the Infrastructure/Network folder that contains hub, shared-prod, and shared-nonprod projects."
  value       = local.network_folder
}

output "projects" {
  description = <<-EOT
    Network projects inside Infrastructure/Network, keyed by role:
      hub            — NCC hub, VPN termination, Interconnect; NOT a Shared VPC host
      shared-prod    — Shared VPC host for production workloads
      shared-nonprod — Shared VPC host for non-production workloads
    The landing zone (gcp-infrastructure-lz) builds VPCs inside these projects.
    network-tf-infra-sa is pre-granted on hub, shared-prod, and shared-nonprod.
  EOT
  value = {
    for k, m in module.project : k => {
      project_id      = m.project_id
      project_number  = m.number
      shared_vpc_host = local.projects[k].shared_vpc_host
      role            = local.projects[k].role
      folder_id       = local.network_folder
    }
  }
}

output "infra_sa_email" {
  description = "network-tf-infra-sa email pre-granted on all network projects. Set as TF_SA in gcp-infrastructure-lz."
  value       = local.infra_email
}
