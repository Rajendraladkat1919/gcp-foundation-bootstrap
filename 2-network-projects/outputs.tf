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
    sa-tf-infra-prod/nonprod are pre-granted on the appropriate projects.
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

output "infra_sa_emails" {
  description = "Infra SA emails pre-granted on network projects. Set these as TF_SA in gcp-infrastructure-lz."
  value = {
    prod    = "sa-tf-infra-prod@${local.iac_core_project}.iam.gserviceaccount.com"
    nonprod = "sa-tf-infra-nonprod@${local.iac_core_project}.iam.gserviceaccount.com"
  }
}
