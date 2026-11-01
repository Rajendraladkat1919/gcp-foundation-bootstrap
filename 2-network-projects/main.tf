data "terraform_remote_state" "org" {
  backend = "gcs"
  config = {
    bucket = "${var.prefix}-terraform-state-foundation"
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

  # SA email from Stage 1 — single infra SA covers all three network projects.
  infra_email = data.terraform_remote_state.org.outputs.sa_emails.infra

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
      name            = "net-core-hub"
      role            = "net-core-hub"
      shared_vpc_host = false
      services        = distinct(concat(local.base_apis, local.hub_extra_apis))
    }
    shared-prod = {
      name            = "net-shared-prod"
      role            = "shared-vpc-host-prod"
      shared_vpc_host = true
      services        = concat(local.base_apis, local.spoke_extra_apis)
    }
    shared-nonprod = {
      name            = "net-shared-nonprod"
      role            = "shared-vpc-host-nonprod"
      shared_vpc_host = true
      services        = concat(local.base_apis, local.spoke_extra_apis)
    }
  }

  # Roles that network-tf-infra-sa-* need to manage VPC, NCC, DNS, and firewall.
  infra_network_roles = [
    "roles/compute.networkAdmin",
    "roles/compute.securityAdmin",
    "roles/compute.xpnAdmin",
    "roles/dns.admin",
    "roles/networkconnectivity.admin",
    "roles/servicenetworking.networksAdmin",
    "roles/serviceusage.serviceUsageConsumer",
  ]

  # Cross-product of (project, role) → one google_project_iam_member per entry.
  # Single network-tf-infra-sa is granted on all three network projects (hub + both spokes).
  infra_sa_grants = {
    for pair in setproduct(["hub", "shared-prod", "shared-nonprod"], local.infra_network_roles) :
    "${pair[0]}-${replace(pair[1], "roles/", "")}" => {
      sa      = "serviceAccount:${local.infra_email}"
      project = module.project[pair[0]].project_id
      role    = pair[1]
    }
  }
}

# ─────────────────────────────────────────────────────────── network projects

module "project" {
  source   = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/project?ref=5b9de0cf7bb5163ef8d0fa4973f31dd36b6de528"
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

# ─────────────────────── grant infra SAs on their target projects ─────────────
#
# network-tf-infra-sa → hub + shared-prod + shared-nonprod (cross-project, scoped network roles only)
#
# Hub is shared: both SAs get the same roles there so each can manage its NCC spoke.

resource "google_project_iam_member" "infra_sa" {
  for_each = local.infra_sa_grants
  project  = each.value.project
  role     = each.value.role
  member   = each.value.sa
}
