module "naming" {
  source = "../../gcp-terraform-module/modules/naming"
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

# projects

module "iac_core" {
  source                  = "../../gcp-terraform-module/modules/project"
  name                    = module.naming.core_project_names["iac_core"]
  prefix                  = var.prefix
  parent                  = var.organization_id
  billing_account         = var.billing_account_id
  default_service_account = "delete"
  deletion_policy         = var.allow_destroy ? "DELETE" : "PREVENT"
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
  deletion_policy         = var.allow_destroy ? "DELETE" : "PREVENT"
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
  deletion_policy         = var.allow_destroy ? "DELETE" : "PREVENT"
  labels                  = local.labels
  services                = concat(local.default_apis, ["orgpolicy.googleapis.com"])
}

# Allow Google's log-writer group: legacy iam.allowedPolicyMemberDomains can't name it by customer id.
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

# state CMEK

# resource (not data source) so it is created at apply time, not read during plan.
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

# GCS agent email is stable from project number; identity email is null during plan.
resource "google_kms_crypto_key_iam_member" "gcs_agent" {
  crypto_key_id = module.kms.keys["tfstate"].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${module.iac_core.number}@gs-project-accounts.iam.gserviceaccount.com"
  depends_on    = [google_project_service_identity.gcs]
}

# buckets

# GCS access logs for every bucket in this stage.
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
  force_destroy               = var.allow_destroy
  retention_policy = var.allow_destroy ? null : {
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
  force_destroy               = var.allow_destroy
  soft_delete_retention       = var.allow_destroy ? 0 : 604800 # 7 days unless a destroy apply clears it
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
    "roles/storage.objectAdmin" = [module.sa_terraform.iam_email]
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
  force_destroy               = var.allow_destroy
  soft_delete_retention       = var.allow_destroy ? 0 : 604800
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
    "roles/storage.objectAdmin" = [module.sa_terraform.iam_email]
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
  force_destroy               = var.allow_destroy
  logging_config = {
    log_bucket        = module.access_logs.name
    log_object_prefix = "billing-exports"
  }
  iam = {
    "roles/storage.objectViewer" = [module.sa_billing_reader.iam_email]
  }
}

# service accounts

locals {
  # Strip "organizations/" prefix; provider adds it back on IAM resources.
  organization_id_numeric = trimprefix(var.organization_id, "organizations/")

  # Required to use iac-core as the quota project for API calls.
  quota_project_roles = ["roles/serviceusage.serviceUsageConsumer"]

  org_read_roles = [
    "roles/browser",
    "roles/iam.securityReviewer",
    "roles/orgpolicy.policyViewer",
    "roles/viewer",
  ]
}

# Single executor for all stages. Folder roles granted in 1-org; project roles in 4-workload-projects.
module "sa_terraform" {
  source       = "../../gcp-terraform-module/modules/iam-service-account"
  project_id   = module.iac_core.project_id
  name         = module.naming.automation_service_account_ids["execute"]
  display_name = "Terraform executor"
  description  = "Runs Terraform for bootstrap, the landing zone and workload projects."
  iam_organization_roles = {
    (local.organization_id_numeric) = concat(local.org_read_roles, [
      "roles/logging.configWriter",
      "roles/orgpolicy.policyAdmin",
      "roles/resourcemanager.folderAdmin",
      "roles/resourcemanager.organizationAdmin", # needed for org IAM, see docs/controls.md (exception EX-1)
      "roles/resourcemanager.projectCreator",
    ])
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
    (var.billing_account_id) = [
      "roles/billing.user",
      "roles/billing.viewer",
    ]
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
