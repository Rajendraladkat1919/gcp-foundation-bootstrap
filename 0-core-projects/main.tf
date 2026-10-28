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

# bootstrap and lz state buckets share the same config; only name, log prefix, and IAM differ.
# bootstrap bucket  → sa-tf-bootstrap only (this repo's pipeline)
# lz bucket         → sa-tf-infra-prod + sa-tf-infra-nonprod (gcp-infrastructure-lz pipeline)
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
  iam = each.key == "bootstrap" ? {
    # Only sa-tf-bootstrap writes bootstrap state.
    # Infra SAs get objectViewer so gcp-infrastructure-lz can read workload project outputs
    # published at bootstrap/3-workload-projects (e.g. project IDs for Shared VPC attachment).
    "roles/storage.objectAdmin"  = [module.sa_tf_bootstrap.iam_email]
    "roles/storage.objectViewer" = [module.sa_tf_infra_prod.iam_email, module.sa_tf_infra_nonprod.iam_email]
  } : {
    # Infra SAs own the lz bucket — they read and write their own state.
    "roles/storage.objectAdmin" = [module.sa_tf_infra_prod.iam_email, module.sa_tf_infra_nonprod.iam_email]
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
#
# Five scoped Terraform executor SAs — all live in pr-iac-core.
# WIF bindings (below) enforce which GitHub repo + environment may impersonate each SA.
#
#   sa-tf-bootstrap     → gcp-foundation-bootstrap  (this repo, any env)
#   sa-tf-infra-prod    → gcp-infrastructure-lz     (environment=production only)
#   sa-tf-infra-nonprod → gcp-infrastructure-lz     (environment=nonprod only)
#   sa-tf-workload-prod    → gcp-workload            (environment=production only)
#   sa-tf-workload-nonprod → gcp-workload            (environment=nonprod only)

module "sa_tf_bootstrap" {
  source       = "../../gcp-terraform-module/modules/iam-service-account"
  project_id   = module.core_project["iac_core"].project_id
  name         = "sa-tf-bootstrap"
  display_name = "Terraform bootstrap executor"
  description  = "Runs Terraform for all gcp-foundation-bootstrap stages. Org-admin scope."
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
      "roles/monitoring.admin",   # required: Stage 1 creates log-based metrics + alert policies here
      "roles/resourcemanager.projectIamAdmin",
      "roles/storage.admin",
    ]
  }
  iam_billing_roles = {
    (var.billing_account_id) = ["roles/billing.user", "roles/billing.viewer"]
  }
}

# Infra SAs: created here with no project roles. Roles on network projects are
# granted in Stage 2 once those projects exist.
module "sa_tf_infra_prod" {
  source       = "../../gcp-terraform-module/modules/iam-service-account"
  project_id   = module.core_project["iac_core"].project_id
  name         = "sa-tf-infra-prod"
  display_name = "Terraform infra executor — prod"
  description  = "Runs gcp-infrastructure-lz Terraform for production. Scoped to hub + shared-prod projects."
}

module "sa_tf_infra_nonprod" {
  source       = "../../gcp-terraform-module/modules/iam-service-account"
  project_id   = module.core_project["iac_core"].project_id
  name         = "sa-tf-infra-nonprod"
  display_name = "Terraform infra executor — nonprod"
  description  = "Runs gcp-infrastructure-lz Terraform for non-production. Scoped to hub + shared-nonprod projects."
}

# Workload SAs: created here with no project roles. Roles on workload projects are
# granted in Stage 4 once those projects exist.
module "sa_tf_workload_prod" {
  source       = "../../gcp-terraform-module/modules/iam-service-account"
  project_id   = module.core_project["iac_core"].project_id
  name         = "sa-tf-workload-prod"
  display_name = "Terraform workload executor — prod"
  description  = "Runs gcp-workload Terraform for production workload projects."
}

module "sa_tf_workload_nonprod" {
  source       = "../../gcp-terraform-module/modules/iam-service-account"
  project_id   = module.core_project["iac_core"].project_id
  name         = "sa-tf-workload-nonprod"
  display_name = "Terraform workload executor — nonprod"
  description  = "Runs gcp-workload Terraform for non-production workload projects."
}

# ─────────────────────────── WIF pool (moved from deleted Stage 3) ───────────

module "github_wif" {
  source      = "../../gcp-terraform-module/modules/iam-workload-identity-pool"
  project_id  = module.core_project["iac_core"].project_id
  pool_id     = "github"
  provider_id = "github-actions"
  display_name = "GitHub Actions OIDC"

  # Map the claims we need for per-SA IAM conditions.
  # VERIFY: confirm the CFF iam-workload-identity-pool module accepts attribute_mapping.
  # If it does not, replace this module with direct google_iam_workload_identity_pool +
  # google_iam_workload_identity_pool_provider resources where attribute_mapping is native.
  # attribute.environment MUST be mapped — all infra and workload SA conditions depend on it.
  attribute_mapping = {
    "google.subject"        = "assertion.sub"
    "attribute.repository"  = "assertion.repository"
    "attribute.environment" = "assertion.environment"
    "attribute.ref"         = "assertion.ref"
    "attribute.workflow"    = "assertion.workflow"
  }

  # Pool-level gate: reject any token not from our GitHub org.
  attribute_condition = "assertion.repository_owner == '${var.github_org}'"
}

# ─────────────────────────── per-SA WIF impersonation bindings ───────────────
#
# Each binding is authoritative for the workloadIdentityUser role on its SA.
# Fine-grained conditions (repo + environment) are enforced here, not at the pool level.

# Bootstrap SA: any job in gcp-foundation-bootstrap may impersonate (plan + apply).
resource "google_service_account_iam_binding" "wif_bootstrap" {
  service_account_id = module.sa_tf_bootstrap.id
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "principalSet://iam.googleapis.com/${module.github_wif.pool_name}/attribute.repository/${var.github_org}/${var.bootstrap_repository}",
  ]
}

# Infra prod SA: only gcp-infrastructure-lz jobs that declare environment=production.
resource "google_service_account_iam_binding" "wif_infra_prod" {
  service_account_id = module.sa_tf_infra_prod.id
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "principalSet://iam.googleapis.com/${module.github_wif.pool_name}/attribute.repository/${var.github_org}/${var.infra_lz_repository}",
  ]
  condition {
    title       = "production-env-only"
    description = "Allows impersonation only from the GitHub 'production' Environment."
    expression  = "attribute.environment == \"production\""
  }
}

# Infra nonprod SA: only gcp-infrastructure-lz jobs that declare environment=nonprod.
# PR plan jobs must declare environment: nonprod in their workflow to get this token.
resource "google_service_account_iam_binding" "wif_infra_nonprod" {
  service_account_id = module.sa_tf_infra_nonprod.id
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "principalSet://iam.googleapis.com/${module.github_wif.pool_name}/attribute.repository/${var.github_org}/${var.infra_lz_repository}",
  ]
  condition {
    title       = "nonprod-env-only"
    description = "Allows impersonation only from the GitHub 'nonprod' Environment."
    expression  = "attribute.environment == \"nonprod\""
  }
}

# Workload prod SA: only gcp-workload jobs that declare environment=production.
resource "google_service_account_iam_binding" "wif_workload_prod" {
  service_account_id = module.sa_tf_workload_prod.id
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "principalSet://iam.googleapis.com/${module.github_wif.pool_name}/attribute.repository/${var.github_org}/${var.workload_repository}",
  ]
  condition {
    title       = "production-env-only"
    description = "Allows impersonation only from the GitHub 'production' Environment."
    expression  = "attribute.environment == \"production\""
  }
}

# Workload nonprod SA: only gcp-workload jobs that declare environment=nonprod.
resource "google_service_account_iam_binding" "wif_workload_nonprod" {
  service_account_id = module.sa_tf_workload_nonprod.id
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "principalSet://iam.googleapis.com/${module.github_wif.pool_name}/attribute.repository/${var.github_org}/${var.workload_repository}",
  ]
  condition {
    title       = "nonprod-env-only"
    description = "Allows impersonation only from the GitHub 'nonprod' Environment."
    expression  = "attribute.environment == \"nonprod\""
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
