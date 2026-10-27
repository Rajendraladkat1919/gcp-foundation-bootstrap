module "naming" {
  source = "../../gcp-terraform-module/modules/naming"
  prefix = var.prefix
}

data "terraform_remote_state" "org" {
  backend = "gcs"
  config = {
    bucket = module.naming.state_bucket_full_names["bootstrap"]
    prefix = "bootstrap/1-org"
  }
}

locals {
  # All three network projects are siblings inside Infrastructure/Network.
  #
  #   Infrastructure/
  #   └── Network/
  #       ├── <prefix>-net-core-hub        (NCC hub, VPN, Interconnect — NOT a Shared VPC host)
  #       ├── <prefix>-net-shared-prod     (Shared VPC host for prod workloads)
  #       └── <prefix>-net-shared-nonprod  (Shared VPC host for nonprod workloads)
  #
  network_folder = data.terraform_remote_state.org.outputs.folder_ids["infrastructure/network"]

  base_apis = [
    "cloudbilling.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "dns.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "networkconnectivity.googleapis.com",
    "servicedirectory.googleapis.com",
    "serviceusage.googleapis.com",
    "sts.googleapis.com",
  ]

  # Extra APIs only needed on the hub (on-prem data-center connectivity).
  hub_extra_apis = [
    "interconnect.googleapis.com",    # Dedicated/Partner Interconnect to on-prem DC
    "networksecurity.googleapis.com", # Cloud Armor / firewall-plus policies
    "privateca.googleapis.com",       # Private CA for mTLS to on-prem
    "vpcaccess.googleapis.com",       # Serverless VPC Access (Cloud Run → VPC)
  ]

  # Shared VPC hosts need servicenetworking for PSA and vpcaccess for serverless.
  spoke_extra_apis = [
    "servicenetworking.googleapis.com",
    "vpcaccess.googleapis.com",
  ]

  projects = {
    hub = {
      name            = module.naming.network_project_names["hub"]
      role            = "net-core-hub"
      shared_vpc_host = false
      services        = distinct(concat(local.base_apis, local.hub_extra_apis))
    }
    shared-prod = {
      name            = module.naming.network_project_names["prod"]
      role            = "shared-vpc-host-prod"
      shared_vpc_host = true
      services        = concat(local.base_apis, local.spoke_extra_apis)
    }
    shared-nonprod = {
      name            = module.naming.network_project_names["nonprod"]
      role            = "shared-vpc-host-nonprod"
      shared_vpc_host = true
      services        = concat(local.base_apis, local.spoke_extra_apis)
    }
  }
}

module "project" {
  source   = "../../gcp-terraform-module/modules/project"
  for_each = local.projects

  name                    = each.value.name
  prefix                  = var.prefix
  parent                  = local.network_folder
  billing_account         = var.billing_account_id
  default_service_account = "delete"
  deletion_policy         = var.allow_destroy ? "DELETE" : "PREVENT"
  services                = each.value.services
  shared_vpc_host_config  = { enabled = each.value.shared_vpc_host }
  labels = {
    cost-center = var.cost_center
    managed-by  = "terraform"
    repository  = "gcp-foundation-bootstrap"
    stage       = "2-network-projects"
    tier        = "network"
    role        = each.value.role
  }
}
