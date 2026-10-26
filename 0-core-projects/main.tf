module "naming" {
  source = "../modules/naming"
  prefix = var.prefix
}

locals {
  # Same API baseline as every project in the landing zone (see docs/controls.md).
  foundation_apis = [
    "cloudbilling.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "serviceusage.googleapis.com",
    "sts.googleapis.com",
  ]
  observability_apis = [
    "logging.googleapis.com",
    "monitoring.googleapis.com",
  ]
  data_apis = [
    "bigquery.googleapis.com",
    "secretmanager.googleapis.com",
    "storage.googleapis.com",
  ]
  default_apis = concat(local.foundation_apis, local.observability_apis, local.data_apis)

  labels = {
    cost-center = var.cost_center
    managed-by  = "terraform"
    repository  = "gcp-foundation-bootstrap"
    stage       = "0-core-projects"
    tier        = "core"
  }
}

# ---------------------------------------------------------------- projects

module "iac_core" {
  source                  = "../../gcp-terraform-module/modules/project"
  name                    = module.naming.core_project_names["iac_core"]
  prefix                  = var.prefix
  parent                  = var.organization_id
  billing_account         = var.billing_account_id
  default_service_account = "delete"
  deletion_policy         = "PREVENT"
  labels                  = local.labels
  services                = concat(local.default_apis, ["cloudkms.googleapis.com", "orgpolicy.googleapis.com"])
}

module "billing" {
  source                  = "../../gcp-terraform-module/modules/project"
  name                    = module.naming.core_project_names["billing"]
  prefix                  = var.prefix
  parent                  = var.organization_id
  billing_account         = var.billing_account_id
  default_service_account = "delete"
  deletion_policy         = "PREVENT"
  labels                  = local.labels
  services                = local.default_apis
}

module "logging" {
  source                  = "../../gcp-terraform-module/modules/project"
  name                    = module.naming.core_project_names["logging"]
  prefix                  = var.prefix
  parent                  = var.organization_id
  billing_account         = var.billing_account_id
  default_service_account = "delete"
  deletion_policy         = "PREVENT"
  labels                  = local.labels
  services                = concat(local.default_apis, ["orgpolicy.googleapis.com"])
}

# Domain restricted sharing is already enforced on this organization. The legacy
# constraint only accepts a Workspace customer id, so it cannot name Google's
# log-writer group. This project replaces that constraint with the managed one
# and allows that single group.
resource "google_org_policy_policy" "logging_member_domains" {
  name   = "projects/${module.logging.project_id}/policies/iam.allowedPolicyMemberDomains"
  parent = "projects/${module.logging.project_id}"

  spec {
    inherit_from_parent = false
    rules {
      allow_all = "TRUE"
    }
  }

  depends_on = [module.logging]
}

resource "google_org_policy_policy" "logging_allowed_members" {
  name   = "projects/${module.logging.project_id}/policies/iam.managed.allowedPolicyMembers"
  parent = "projects/${module.logging.project_id}"

  spec {
    rules {
      enforce = "TRUE"
      parameters = jsonencode({
        allowedMemberSubjects = [
          "group:cloud-storage-analytics@google.com",
          "serviceAccount:cloud-storage-analytics@google.com",
        ]
        allowedPrincipalSets = [
          "//cloudresourcemanager.googleapis.com/organizations/${trimprefix(var.organization_id, "organizations/")}",
        ]
      })
    }
  }

  depends_on = [module.logging]
}

# ----------------------------------------------------------------- state CMEK

# Created at apply time. A data source would read pe-pr-iac-core during plan, before the project exists.
resource "google_project_service_identity" "gcs" {
  provider   = google-beta
  project    = module.iac_core.project_id
  service    = "storage.googleapis.com"
  depends_on = [module.iac_core]
}

module "kms" {
  source     = "../../gcp-terraform-module/modules/kms"
  project_id = module.iac_core.project_id
  keyring = {
    location = var.region
    name     = "tfstate"
  }
  keys = {
    tfstate = {
      rotation_period = "7776000s" # 90 days
      labels          = local.labels
    }
  }
}

# The identity resource leaves email null during plan. The Cloud Storage agent address is fixed from the project number.
resource "google_kms_crypto_key_iam_member" "gcs_agent" {
  crypto_key_id = module.kms.keys["tfstate"].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${module.iac_core.number}@gs-project-accounts.iam.gserviceaccount.com"
  depends_on    = [google_project_service_identity.gcs]
}

# ------------------------------------------------------------------- buckets

# Receives Cloud Storage access logs for every bucket in this stage.
module "access_logs" {
  source                      = "../../gcp-terraform-module/modules/gcs"
  depends_on                  = [google_org_policy_policy.logging_member_domains, google_org_policy_policy.logging_allowed_members]
  project_id                  = module.logging.project_id
  prefix                      = var.prefix
  name                        = "pr-access-logs"
  location                    = var.region
  labels                      = local.labels
  versioning                  = true
  public_access_prevention    = "enforced"
  uniform_bucket_level_access = true
  retention_policy = {
    retention_period = tostring(var.access_log_retention_days * 86400)
    is_locked        = var.lock_log_retention
  }
  iam = {
    "roles/storage.objectCreator" = ["group:cloud-storage-analytics@google.com"]
  }
}

module "state_bootstrap" {
  source                      = "../../gcp-terraform-module/modules/gcs"
  depends_on                  = [google_kms_crypto_key_iam_member.gcs_agent]
  project_id                  = module.iac_core.project_id
  prefix                      = var.prefix
  name                        = module.naming.state_bucket_names["bootstrap"]
  location                    = var.region
  labels                      = local.labels
  versioning                  = true
  encryption_key              = module.kms.keys["tfstate"].id
  public_access_prevention    = "enforced"
  uniform_bucket_level_access = true
  soft_delete_retention       = 604800 # 7 days
  logging_config = {
    log_bucket        = module.access_logs.name
    log_object_prefix = "tfstate-bootstrap"
  }
  lifecycle_rules = {
    prune_noncurrent = {
      action    = { type = "Delete" }
      condition = { days_since_noncurrent_time = 90, with_state = "ARCHIVED" }
    }
  }
  iam = {
    "roles/storage.objectAdmin"  = [module.sa_bootstrap_apply.iam_email]
    "roles/storage.objectViewer" = [module.sa_bootstrap_plan.iam_email, module.sa_lz_apply.iam_email, module.sa_lz_plan.iam_email]
  }
}

module "state_lz" {
  source                      = "../../gcp-terraform-module/modules/gcs"
  depends_on                  = [google_kms_crypto_key_iam_member.gcs_agent]
  project_id                  = module.iac_core.project_id
  prefix                      = var.prefix
  name                        = module.naming.state_bucket_names["lz"]
  location                    = var.region
  labels                      = local.labels
  versioning                  = true
  encryption_key              = module.kms.keys["tfstate"].id
  public_access_prevention    = "enforced"
  uniform_bucket_level_access = true
  soft_delete_retention       = 604800
  logging_config = {
    log_bucket        = module.access_logs.name
    log_object_prefix = "tfstate-lz"
  }
  lifecycle_rules = {
    prune_noncurrent = {
      action    = { type = "Delete" }
      condition = { days_since_noncurrent_time = 90, with_state = "ARCHIVED" }
    }
  }
  iam = {
    "roles/storage.objectAdmin"  = [module.sa_lz_apply.iam_email]
    "roles/storage.objectViewer" = [module.sa_lz_plan.iam_email, module.sa_bootstrap_apply.iam_email]
  }
}

module "billing_exports" {
  source                      = "../../gcp-terraform-module/modules/gcs"
  project_id                  = module.billing.project_id
  prefix                      = var.prefix
  name                        = "pr-billing-exports"
  location                    = var.region
  labels                      = local.labels
  versioning                  = true
  public_access_prevention    = "enforced"
  uniform_bucket_level_access = true
  logging_config = {
    log_bucket        = module.access_logs.name
    log_object_prefix = "billing-exports"
  }
  iam = {
    "roles/storage.objectViewer" = [module.sa_billing_reader.iam_email]
  }
}

# ------------------------------------------------------ service accounts

locals {
  # google_organization_iam_member.org_id is the numeric id. The organizations/ prefix is added by the provider.
  organization_id_numeric = trimprefix(var.organization_id, "organizations/")

  # Roles every automation identity needs to use APIs through the iac-core project.
  quota_project_roles = ["roles/serviceusage.serviceUsageConsumer"]

  org_read_roles = [
    "roles/browser",
    "roles/iam.securityReviewer",
    "roles/orgpolicy.policyViewer",
    "roles/viewer",
  ]
}

module "sa_bootstrap_plan" {
  source       = "../../gcp-terraform-module/modules/iam-service-account"
  project_id   = module.iac_core.project_id
  name         = module.naming.automation_service_account_ids["bootstrap_plan"]
  display_name = "Terraform plan (gcp-foundation-bootstrap, pull requests)"
  description  = "Read-only. Impersonated by pull request plans and the nightly drift check."
  iam_organization_roles = {
    (local.organization_id_numeric) = local.org_read_roles
  }
  iam_project_roles = {
    (module.iac_core.project_id) = local.quota_project_roles
  }
  iam_billing_roles = {
    (var.billing_account_id) = ["roles/billing.viewer"]
  }
}

module "sa_bootstrap_apply" {
  source       = "../../gcp-terraform-module/modules/iam-service-account"
  project_id   = module.iac_core.project_id
  name         = module.naming.automation_service_account_ids["bootstrap_apply"]
  display_name = "Terraform apply (gcp-foundation-bootstrap, main branch)"
  description  = "Write access. Only the main branch of gcp-foundation-bootstrap can impersonate it."
  iam_organization_roles = {
    (local.organization_id_numeric) = [
      "roles/logging.configWriter",
      "roles/orgpolicy.policyAdmin",
      "roles/resourcemanager.folderAdmin",
      "roles/resourcemanager.organizationAdmin", # needed for org IAM, see docs/controls.md (exception EX-1)
      "roles/resourcemanager.projectCreator",
    ]
  }
  iam_project_roles = {
    (module.iac_core.project_id) = concat(local.quota_project_roles, [
      "roles/cloudkms.admin",
      "roles/iam.serviceAccountAdmin",
      "roles/iam.workloadIdentityPoolAdmin",
      "roles/resourcemanager.projectIamAdmin",
      "roles/serviceusage.serviceUsageAdmin",
      "roles/storage.admin",
    ])
    (module.logging.project_id) = [
      "roles/logging.admin",
      "roles/resourcemanager.projectIamAdmin",
      "roles/storage.admin",
    ]
  }
  iam_billing_roles = {
    (var.billing_account_id) = ["roles/billing.user"]
  }
}

module "sa_lz_plan" {
  source       = "../../gcp-terraform-module/modules/iam-service-account"
  project_id   = module.iac_core.project_id
  name         = module.naming.automation_service_account_ids["lz_plan"]
  display_name = "Terraform plan (gcp-infrastructure-lz, pull requests)"
  description  = "Read-only. Impersonated by pull request plans and the nightly drift check of the landing zone repository."
  iam_organization_roles = {
    (local.organization_id_numeric) = local.org_read_roles
  }
  iam_project_roles = {
    (module.iac_core.project_id) = local.quota_project_roles
  }
  iam_billing_roles = {
    (var.billing_account_id) = ["roles/billing.viewer"]
  }
}

module "sa_lz_apply" {
  source       = "../../gcp-terraform-module/modules/iam-service-account"
  project_id   = module.iac_core.project_id
  name         = module.naming.automation_service_account_ids["lz_apply"]
  display_name = "Terraform apply (gcp-infrastructure-lz, main branch)"
  description  = "Write access to network projects. Folder level roles are granted in stage 1-org."
  iam_organization_roles = {
    (local.organization_id_numeric) = ["roles/browser"]
  }
  iam_project_roles = {
    (module.iac_core.project_id) = local.quota_project_roles
  }
  iam_billing_roles = {
    (var.billing_account_id) = ["roles/billing.user"]
  }
}

module "sa_billing_reader" {
  source       = "../../gcp-terraform-module/modules/iam-service-account"
  project_id   = module.billing.project_id
  name         = "sa-billing-reader"
  display_name = "Billing export reader"
  description  = "Reads billing exports for reporting. No write access."
}

module "sa_logging_reader" {
  source       = "../../gcp-terraform-module/modules/iam-service-account"
  project_id   = module.logging.project_id
  name         = "sa-logging-reader"
  display_name = "Central log reader"
  description  = "Reads the central audit log bucket for the security team tooling. No write access."
  iam_project_roles = {
    (module.logging.project_id) = ["roles/logging.viewer", "roles/logging.privateLogViewer"]
  }
}
