module "naming" {
  source = "../../gcp-terraform-module/modules/naming"
  prefix = var.prefix
}

locals {
  # ── API groups ──────────────────────────────────────────────────────────────
  foundation_apis = [
    "cloudbilling.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "serviceusage.googleapis.com",
    "sts.googleapis.com",
  ]
  observability_apis = ["logging.googleapis.com", "monitoring.googleapis.com"]
  data_apis          = ["bigquery.googleapis.com", "secretmanager.googleapis.com", "storage.googleapis.com"]
  default_apis       = concat(local.foundation_apis, local.observability_apis, local.data_apis)

  # Per-project extra APIs on top of default_apis.
  core_project_services = {
    iac_core = concat(
      local.default_apis,
      [
        "cloudasset.googleapis.com",
        "cloudkms.googleapis.com",
        "essentialcontacts.googleapis.com",
        "orgpolicy.googleapis.com",
        "pubsub.googleapis.com",
      ],
      var.enable_scc ? ["securitycenter.googleapis.com"] : []
    )
    billing = local.default_apis
    logging = concat(local.default_apis, ["orgpolicy.googleapis.com"])
  }

  # ── Labels ──────────────────────────────────────────────────────────────────
  labels = {
    cost-center = var.cost_center
    managed-by  = "terraform"
    repository  = "gcp-foundation-bootstrap"
    stage       = "0-core-projects"
    tier        = "core"
  }

  # ── IAM helpers ─────────────────────────────────────────────────────────────
  organization_id_numeric = trimprefix(var.organization_id, "organizations/")
  quota_project_roles     = ["roles/serviceusage.serviceUsageConsumer"]
  org_read_roles = [
    "roles/browser",
    "roles/iam.securityReviewer",
    "roles/orgpolicy.policyViewer",
    "roles/viewer",
  ]

  # State bucket names and their access-log object prefixes.
  state_buckets = {
    bootstrap = "tfstate-bootstrap"
    lz        = "tfstate-lz"
  }
}

# ──────────────────────────────────────────────────────────────── core projects

module "core_project" {
  source   = "../../gcp-terraform-module/modules/project"
  for_each = local.core_project_services

  name                    = module.naming.core_project_names[each.key]
  prefix                  = var.prefix
  parent                  = var.organization_id
  billing_account         = var.billing_account_id
  default_service_account = "delete"
  deletion_policy         = var.allow_destroy ? "DELETE" : "PREVENT"
  labels                  = local.labels
  services                = each.value
}

# Allow Google's log-writer SA: legacy iam.allowedPolicyMemberDomains can't name it by customer id.
resource "google_org_policy_policy" "logging_member_domains" {
  name   = "projects/${module.core_project["logging"].project_id}/policies/iam.allowedPolicyMemberDomains"
  parent = "projects/${module.core_project["logging"].project_id}"
  spec {
    inherit_from_parent = false
    rules { allow_all = "TRUE" }
  }
  depends_on = [module.core_project]
}

resource "google_org_policy_policy" "logging_allowed_members" {
  name   = "projects/${module.core_project["logging"].project_id}/policies/iam.managed.allowedPolicyMembers"
  parent = "projects/${module.core_project["logging"].project_id}"
  spec {
    rules {
      enforce = "TRUE"
      parameters = jsonencode({
        allowedMemberSubjects = [
          "group:cloud-storage-analytics@google.com",
          "serviceAccount:cloud-storage-analytics@google.com",
        ]
        allowedPrincipalSets = [
          "//cloudresourcemanager.googleapis.com/organizations/${local.organization_id_numeric}",
        ]
      })
    }
  }
  depends_on = [module.core_project]
}

# ──────────────────────────────────────────────────────────────────── state CMEK

# resource (not data source) so it is created at apply time, not read during plan.
resource "google_project_service_identity" "gcs" {
  provider   = google-beta
  project    = module.core_project["iac_core"].project_id
  service    = "storage.googleapis.com"
  depends_on = [module.core_project]
}

module "kms" {
  source     = "../../gcp-terraform-module/modules/kms"
  project_id = module.core_project["iac_core"].project_id
  keyring    = { location = var.region, name = "tfstate" }
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
  member        = "serviceAccount:service-${module.core_project["iac_core"].number}@gs-project-accounts.iam.gserviceaccount.com"
  depends_on    = [google_project_service_identity.gcs]
}

# ────────────────────────────────────────────────────────────────────── buckets

module "access_logs" {
  source     = "../../gcp-terraform-module/modules/gcs"
  depends_on = [google_org_policy_policy.logging_member_domains, google_org_policy_policy.logging_allowed_members]

  project_id                  = module.core_project["logging"].project_id
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

# bootstrap and lz state buckets share the same config; only name and log prefix differ.
module "state" {
  source     = "../../gcp-terraform-module/modules/gcs"
  for_each   = local.state_buckets
  depends_on = [google_kms_crypto_key_iam_member.gcs_agent]

  project_id                  = module.core_project["iac_core"].project_id
  prefix                      = var.prefix
  name                        = module.naming.state_bucket_names[each.key]
  location                    = var.region
  labels                      = local.labels
  versioning                  = true
  encryption_key              = module.kms.keys["tfstate"].id
  public_access_prevention    = "enforced"
  uniform_bucket_level_access = true
  force_destroy               = var.allow_destroy
  soft_delete_retention       = var.allow_destroy ? 0 : 604800 # 7 days
  logging_config = {
    log_bucket        = module.access_logs.name
    log_object_prefix = each.value
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
  source = "../../gcp-terraform-module/modules/gcs"

  project_id                  = module.core_project["billing"].project_id
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

# ───────────────────────────────────────────────────────────── service accounts

# Single executor for all stages. Folder roles granted in 1-org; project roles in 4-workload-projects.
module "sa_terraform" {
  source       = "../../gcp-terraform-module/modules/iam-service-account"
  project_id   = module.core_project["iac_core"].project_id
  name         = module.naming.automation_service_account_ids["execute"]
  display_name = "Terraform executor"
  description  = "Runs Terraform for bootstrap, the landing zone and workload projects."
  iam_organization_roles = {
    (local.organization_id_numeric) = concat(local.org_read_roles, [
      "roles/essentialcontacts.admin",
      "roles/logging.configWriter",
      "roles/orgpolicy.policyAdmin",
      "roles/resourcemanager.folderAdmin",
      "roles/resourcemanager.organizationAdmin", # see docs/controls.md exception EX-1
      "roles/resourcemanager.projectCreator",
    ], var.enable_scc ? ["roles/securitycenter.admin"] : [])
  }
  iam_project_roles = {
    (module.core_project["iac_core"].project_id) = concat(local.quota_project_roles, [
      "roles/bigquery.admin",
      "roles/cloudkms.admin",
      "roles/iam.serviceAccountAdmin",
      "roles/iam.workloadIdentityPoolAdmin",
      "roles/pubsub.admin",
      "roles/resourcemanager.projectIamAdmin",
      "roles/serviceusage.serviceUsageAdmin",
      "roles/storage.admin",
    ])
    (module.core_project["billing"].project_id) = ["roles/bigquery.admin"]
    (module.core_project["logging"].project_id) = [
      "roles/logging.admin",
      "roles/resourcemanager.projectIamAdmin",
      "roles/storage.admin",
    ]
  }
  iam_billing_roles = {
    (var.billing_account_id) = ["roles/billing.user", "roles/billing.viewer"]
  }
}

module "sa_billing_reader" {
  source       = "../../gcp-terraform-module/modules/iam-service-account"
  project_id   = module.core_project["billing"].project_id
  name         = "sa-billing-reader"
  display_name = "Billing export reader"
  description  = "Reads billing exports for reporting. No write access."
}

module "sa_logging_reader" {
  source       = "../../gcp-terraform-module/modules/iam-service-account"
  project_id   = module.core_project["logging"].project_id
  name         = "sa-logging-reader"
  display_name = "Central log reader"
  description  = "Reads the central audit log bucket for security team tooling. No write access."
  iam_project_roles = {
    (module.core_project["logging"].project_id) = [
      "roles/logging.viewer",
      "roles/logging.privateLogViewer",
    ]
  }
}

module "sa_prisma_cloud" {
  count        = var.enable_prisma_cloud ? 1 : 0
  source       = "../../gcp-terraform-module/modules/iam-service-account"
  project_id   = module.core_project["iac_core"].project_id
  name         = "sa-prisma-cloud"
  display_name = "Prisma Cloud CSPM connector"
  description  = "Read-only org-wide access for Prisma Cloud. Register this SA email under Prisma Cloud → Settings → Cloud Accounts."
  iam_organization_roles = {
    (local.organization_id_numeric) = [
      "roles/viewer",
      "roles/iam.securityReviewer",
      "roles/cloudasset.viewer",
      "roles/logging.viewer",
    ]
  }
}

# ──────────────────────────────────────────────── billing BigQuery export dataset

resource "google_bigquery_dataset" "billing_export" {
  project                    = module.core_project["billing"].project_id
  dataset_id                 = "billing_export"
  friendly_name              = "Cloud Billing Export"
  description                = "Detailed and standard Cloud Billing export. Enable the export in the Cloud Billing console (Billing → Billing export → BigQuery export)."
  location                   = var.region
  delete_contents_on_destroy = var.allow_destroy
  labels                     = local.labels

  access {
    role          = "OWNER"
    special_group = "projectOwners"
  }
  access {
    role          = "READER"
    user_by_email = module.sa_billing_reader.email
  }
}

# ──────────────────────────────────────────────────────── XSIAM Pub/Sub topic

resource "google_pubsub_topic" "xsiam" {
  project                    = module.core_project["iac_core"].project_id
  name                       = "${var.prefix}-pr-xsiam"
  labels                     = local.labels
  message_retention_duration = "604800s" # 7 days — allows XSIAM to recover from outages

  depends_on = [module.core_project]
}
