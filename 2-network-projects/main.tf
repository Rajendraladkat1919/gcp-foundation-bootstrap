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
  parent = data.terraform_remote_state.org.outputs.folder_ids["infrastructure/network"]

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
    "serviceusage.googleapis.com",
    "sts.googleapis.com",
  ]

  projects = {
    hub = {
      name            = module.naming.network_project_names["hub"]
      shared_vpc_host = false
      services        = local.base_apis
      labels = {
        role = "hub"
      }
    }
    prod = {
      name            = module.naming.network_project_names["prod"]
      shared_vpc_host = true
      services        = concat(local.base_apis, ["servicenetworking.googleapis.com"])
      labels = {
        environment = "prod"
        role        = "shared-vpc-host"
      }
    }
    nonprod = {
      name            = module.naming.network_project_names["nonprod"]
      shared_vpc_host = true
      services        = concat(local.base_apis, ["servicenetworking.googleapis.com"])
      labels = {
        environment = "nonprod"
        role        = "shared-vpc-host"
      }
    }
  }
}

module "project" {
  source                  = "../../gcp-terraform-module/modules/project"
  for_each                = local.projects
  name                    = each.value.name
  prefix                  = var.prefix
  parent                  = local.parent
  billing_account         = var.billing_account_id
  default_service_account = "delete"
  deletion_policy         = var.allow_destroy ? "DELETE" : "PREVENT"
  services                = each.value.services
  shared_vpc_host_config = {
    enabled = each.value.shared_vpc_host
  }
  labels = merge({
    cost-center = var.cost_center
    managed-by  = "terraform"
    repository  = "gcp-foundation-bootstrap"
    stage       = "2-network-projects"
    tier        = "network"
  }, each.value.labels)
}
