module "naming" {
  source = "../modules/naming"
  prefix = var.prefix
}

data "terraform_remote_state" "org" {
  backend = "gcs"
  config = {
    bucket = module.naming.state_bucket_full_names["bootstrap"]
    prefix = "bootstrap/1-org"
  }
}

data "terraform_remote_state" "cicd" {
  backend = "gcs"
  config = {
    bucket = module.naming.state_bucket_full_names["bootstrap"]
    prefix = "bootstrap/2-cicd-identity"
  }
}

locals {
  baseline_apis = [
    "bigquery.googleapis.com",
    "cloudbilling.googleapis.com",
    "cloudkms.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "secretmanager.googleapis.com",
    "serviceusage.googleapis.com",
    "storage.googleapis.com",
    "sts.googleapis.com",
  ]

  default_deployer_roles = [
    "roles/editor",
    "roles/resourcemanager.projectIamAdmin",
  ]

  files = fileset("${path.module}/data/projects", "*.yaml")

  projects = {
    for f in local.files : trimsuffix(f, ".yaml") => yamldecode(file("${path.module}/data/projects/${f}"))
  }

  pool_name = data.terraform_remote_state.cicd.outputs.workload_identity_pool_name
}

module "project" {
  source                  = "../../gcp-terraform-module/modules/project"
  for_each                = local.projects
  name                    = "${module.naming.environments[each.value.environment].code}-${each.value.environment}-${each.value.short_name}"
  prefix                  = var.prefix
  parent                  = data.terraform_remote_state.org.outputs.folder_ids["workloads/${each.value.business_unit}/${each.value.environment}"]
  billing_account         = var.billing_account_id
  default_service_account = "delete"
  deletion_policy         = "PREVENT"
  services                = distinct(concat(local.baseline_apis, try(each.value.extra_apis, [])))
  iam_by_principals       = try(each.value.iam_groups, {})
  labels = {
    business-unit = each.value.business_unit
    cost-center   = try(each.value.cost_center, var.cost_center)
    environment   = each.value.environment
    managed-by    = "terraform"
    repository    = each.value.repository
  }
}

module "deployer" {
  source       = "../../gcp-terraform-module/modules/iam-service-account"
  for_each     = local.projects
  project_id   = module.project[each.key].project_id
  name         = "sa-wlp-deployer"
  display_name = "Workload deployer (${each.value.repository}, main branch)"
  iam_project_roles = {
    (module.project[each.key].project_id) = try(each.value.deployer_roles, local.default_deployer_roles)
  }
}

module "planner" {
  source       = "../../gcp-terraform-module/modules/iam-service-account"
  for_each     = local.projects
  project_id   = module.project[each.key].project_id
  name         = "sa-wlp-planner"
  display_name = "Workload planner (${each.value.repository}, pull requests)"
  iam_project_roles = {
    (module.project[each.key].project_id) = ["roles/viewer", "roles/iam.securityReviewer"]
  }
}

data "google_storage_project_service_account" "workload" {
  for_each   = local.projects
  project    = module.project[each.key].project_id
  depends_on = [module.project]
}

module "kms" {
  source     = "../../gcp-terraform-module/modules/kms"
  for_each   = local.projects
  project_id = module.project[each.key].project_id
  keyring = {
    location = var.region
    name     = "workload"
  }
  keys = {
    tfstate = {
      rotation_period = "7776000s" # 90 days
      labels = {
        managed-by = "terraform"
        purpose    = "terraform-state"
      }
      iam_bindings_additive = {
        gcs_agent = {
          member = "serviceAccount:${data.google_storage_project_service_account.workload[each.key].email_address}"
          role   = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
        }
      }
    }
  }
}

module "state" {
  source                      = "../../gcp-terraform-module/modules/gcs"
  for_each                    = local.projects
  project_id                  = module.project[each.key].project_id
  prefix                      = module.project[each.key].project_id
  name                        = "tfstate"
  location                    = var.region
  versioning                  = true
  encryption_key              = module.kms[each.key].keys["tfstate"].id
  public_access_prevention    = "enforced"
  uniform_bucket_level_access = true
  soft_delete_retention       = 604800
  labels = {
    managed-by = "terraform"
    purpose    = "terraform-state"
  }
  iam = {
    "roles/storage.objectAdmin"  = [module.deployer[each.key].iam_email]
    "roles/storage.objectViewer" = [module.planner[each.key].iam_email]
  }
}

# The workload repository authenticates with its own identity and can only reach its own project.
resource "google_service_account_iam_member" "deployer" {
  for_each           = local.projects
  service_account_id = module.deployer[each.key].id
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${local.pool_name}/attribute.fast_sub/repo:${var.github_org}/${each.value.repository}:ref:refs/heads/main"
}

resource "google_service_account_iam_member" "planner" {
  for_each           = local.projects
  service_account_id = module.planner[each.key].id
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${local.pool_name}/attribute.repository/${var.github_org}/${each.value.repository}"
}
