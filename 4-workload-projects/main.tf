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

  # Roles sa-tf-bootstrap needs to manage project lifecycle (project IAM, service enablement).
  bootstrap_project_roles = [
    "roles/resourcemanager.projectIamAdmin",
    "roles/serviceusage.serviceUsageAdmin",
  ]

  # Roles sa-tf-workload-* need to deploy application resources inside workload projects.
  workload_deployer_roles = [
    "roles/editor",
    "roles/iam.serviceAccountAdmin",
    "roles/resourcemanager.projectIamAdmin",
    "roles/secretmanager.admin",
  ]

  files    = fileset("${path.module}/data/projects", "*.yaml")
  projects = { for f in local.files : trimsuffix(f, ".yaml") => yamldecode(file("${path.module}/data/projects/${f}")) }

  iac_core_project = module.naming.core_project_ids["iac_core"]

  # Explicit SA emails — decoupled from the naming module.
  bootstrap_sa      = "serviceAccount:sa-tf-bootstrap@${local.iac_core_project}.iam.gserviceaccount.com"
  workload_prod_sa  = "serviceAccount:sa-tf-workload-prod@${local.iac_core_project}.iam.gserviceaccount.com"
  workload_nonprod_sa = "serviceAccount:sa-tf-workload-nonprod@${local.iac_core_project}.iam.gserviceaccount.com"
}

# ─────────────────────────────────────────────── workload project creation

module "project" {
  source   = "../../gcp-terraform-module/modules/project"
  for_each = local.projects

  name                    = "${module.naming.environments[each.value.environment].code}-${each.value.environment}-${each.value.short_name}"
  prefix                  = var.prefix
  parent                  = data.terraform_remote_state.org.outputs.folder_ids["workloads/${each.value.business_unit}/${each.value.environment}"]
  billing_account         = var.billing_account_id
  default_service_account = "delete"
  deletion_policy         = var.allow_destroy ? "DELETE" : "PREVENT"
  services                = distinct(concat(local.baseline_apis, try(each.value.extra_apis, [])))
  iam_by_principals       = try(each.value.iam_groups, {})

  iam_bindings_additive = merge(
    # Bootstrap SA: project-lifecycle management only (no editor, no resource access).
    { for role in local.bootstrap_project_roles :
      "bootstrap_${replace(role, "roles/", "")}" => {
        member = local.bootstrap_sa
        role   = role
      }
    },
    # Workload SA: full deployer access, scoped to the matching environment SA.
    { for role in try(each.value.deployer_roles, local.workload_deployer_roles) :
      "workload_${replace(role, "roles/", "")}" => {
        member = each.value.environment == "prod" ? local.workload_prod_sa : local.workload_nonprod_sa
        role   = role
      }
    }
  )

  labels = {
    business-unit = each.value.business_unit
    cost-center   = try(each.value.cost_center, var.cost_center)
    environment   = each.value.environment
    managed-by    = "terraform"
    repository    = each.value.repository
  }
}

# ─────────────────────────────────────────────── per-project CMEK + state bucket

data "google_storage_project_service_account" "workload" {
  for_each   = local.projects
  project    = module.project[each.key].project_id
  depends_on = [module.project]
}

module "kms" {
  source     = "../../gcp-terraform-module/modules/kms"
  for_each   = local.projects
  project_id = module.project[each.key].project_id
  keyring    = { location = var.region, name = "workload" }
  keys = {
    tfstate = {
      rotation_period = "7776000s" # 90 days
      labels          = { managed-by = "terraform", purpose = "terraform-state" }
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
  source     = "../../gcp-terraform-module/modules/gcs"
  for_each   = local.projects
  project_id = module.project[each.key].project_id
  prefix     = module.project[each.key].project_id
  name       = "tfstate"
  location   = var.region
  versioning = true

  encryption_key              = module.kms[each.key].keys["tfstate"].id
  public_access_prevention    = "enforced"
  uniform_bucket_level_access = true
  force_destroy               = var.allow_destroy
  soft_delete_retention       = var.allow_destroy ? 0 : 604800
  labels                      = { managed-by = "terraform", purpose = "terraform-state" }

  # Workload SA owns the state; bootstrap SA has no access (not its state bucket).
  iam = {
    "roles/storage.objectAdmin" = [
      each.value.environment == "prod" ? local.workload_prod_sa : local.workload_nonprod_sa
    ]
  }
}
