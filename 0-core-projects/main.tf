locals {
  # ── Naming conventions (replaces the external naming module) ──────────────────
  # Resource names follow the pattern {prefix}-{short-name}. The project module
  # takes (prefix + name) and creates the full project ID as {prefix}-{name}.
  naming_core_project_names = {
    iac_core = "pr-iac-core"
    billing  = "pr-billing"
    logging  = "pr-logging"
  }
  naming_core_project_ids = {
    iac_core = "${var.prefix}-pr-iac-core"
    billing  = "${var.prefix}-pr-billing"
    logging  = "${var.prefix}-pr-logging"
  }

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

  # ── Workload SA discovery ────────────────────────────────────────────────────
  # Read every YAML in Stage 4 to derive one SA + one WIF binding per workload.
  # Adding a new YAML automatically creates the SA and the repo/env-scoped WIF binding.
  workload_yamls = {
    for f in fileset("${path.module}/../4-workload-projects/data/projects", "*.yaml") :
    trimsuffix(f, ".yaml") => yamldecode(file("${path.module}/../4-workload-projects/data/projects/${f}"))
  }

  # Maps YAML environment value → GitHub Actions environment name.
  github_env_names = {
    prod    = "production"
    nonprod = "nonprod"
    qa      = "qa"
    dev     = "dev"
  }

  # SA name formula: workload-{short_name}-{environment}-sa
  # Stage 4 computes the identical formula from YAML data — no remote state read needed.
  workload_sa_map = {
    for k, v in local.workload_yamls : k => {
      sa_name    = "workload-${v.short_name}-${v.environment}-sa"
      repository = v.repository
      github_env = try(local.github_env_names[v.environment], v.environment)
    }
  }

  # State buckets — explicit names so every stage can compute the same value from var.prefix
  # without relying on the naming module (which would couple downstream stages to its internals).
  #   foundation → bootstrap stages 0-4  (the org skeleton)
  #   network    → gcp-infrastructure-lz (hub + spoke VPCs)
  state_buckets = {
    bootstrap = {
      bucket_name = "${var.prefix}-terraform-state-foundation"
      log_prefix  = "terraform-state-foundation"
    }
    lz = {
      bucket_name = "${var.prefix}-terraform-state-network"
      log_prefix  = "terraform-state-network"
    }
  }
}

# ──────────────────────────────────────────────────────────────── core projects

module "core_project" {
  source   = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/project?ref=5b9de0cf7bb5163ef8d0fa4973f31dd36b6de528"
  for_each = local.core_project_services

  name                    = local.naming_core_project_names[each.key]
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
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/kms?ref=5b9de0cf7bb5163ef8d0fa4973f31dd36b6de528"
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
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/gcs?ref=5b9de0cf7bb5163ef8d0fa4973f31dd36b6de528"
  depends_on = [google_org_policy_policy.logging_member_domains, google_org_policy_policy.logging_allowed_members]

  project_id                  = module.core_project["logging"].project_id
  prefix                      = var.prefix
  name                        = "gcs-access-logs"
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
# bootstrap bucket  → platform-tf-admin-sa only (this repo's pipeline)
# lz bucket         → network-tf-infra-sa (gcp-infrastructure-lz pipeline, all environments)
module "state" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/gcs?ref=5b9de0cf7bb5163ef8d0fa4973f31dd36b6de528"
  for_each   = local.state_buckets
  depends_on = [google_kms_crypto_key_iam_member.gcs_agent]

  project_id                  = module.core_project["iac_core"].project_id
  prefix                      = var.prefix
  name                        = each.value.bucket_name
  location                    = var.state_location
  labels                      = local.labels
  versioning                  = true
  encryption_key              = module.kms.keys["tfstate"].id
  public_access_prevention    = "enforced"
  uniform_bucket_level_access = true
  force_destroy               = var.allow_destroy
  soft_delete_retention       = var.allow_destroy ? 0 : 604800 # 7 days
  logging_config = {
    log_bucket        = module.access_logs.name
    log_object_prefix = each.value.log_prefix
  }
  lifecycle_rules = {
    prune_noncurrent = {
      action    = { type = "Delete" }
      condition = { days_since_noncurrent_time = 90, with_state = "ARCHIVED" }
    }
  }
  iam = each.key == "bootstrap" ? {
    # Only platform-tf-admin-sa writes bootstrap state.
    # network-tf-infra-sa gets objectViewer so gcp-infrastructure-lz can read workload project outputs
    # published at bootstrap/3-workload-projects (e.g. project IDs for Shared VPC attachment).
    "roles/storage.objectAdmin"  = [module.sa_tf_bootstrap.iam_email]
    "roles/storage.objectViewer" = [module.sa_tf_infra.iam_email]
  } : {
    # network-tf-infra-sa owns the lz bucket — reads and writes its own state.
    "roles/storage.objectAdmin" = [module.sa_tf_infra.iam_email]
  }
}

module "billing_exports" {
  source = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/gcs?ref=5b9de0cf7bb5163ef8d0fa4973f31dd36b6de528"

  project_id                  = module.core_project["billing"].project_id
  prefix                      = var.prefix
  name                        = "billing-exports"
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
# Terraform executor SAs — all live in pr-iac-core.
# WIF bindings enforce which GitHub repo + environment may impersonate each SA.
#
#   platform-tf-admin-sa       → gcp-foundation-bootstrap (any env)
#   network-tf-infra-sa        → gcp-infrastructure-lz   (any env — hub is shared)
#   workload-{name}-{env}-sa   → one SA per YAML file, scoped to that repo + environment

module "sa_tf_bootstrap" {
  source       = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/iam-service-account?ref=5b9de0cf7bb5163ef8d0fa4973f31dd36b6de528"
  project_id   = module.core_project["iac_core"].project_id
  name         = "platform-tf-admin-sa"
  display_name = "Terraform bootstrap executor"
  description  = "Runs Terraform for all gcp-foundation-bootstrap stages. Org-admin scope."
  iam_organization_roles = {
    (local.organization_id_numeric) = concat(local.org_read_roles, [
      "roles/cloudidentity.groupAdmin",   # create and manage Cloud Identity groups in Stage 1
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

# Infra SA: created here with no project roles. Roles on network projects are
# granted in Stage 2 once those projects exist. Single SA covers both prod and nonprod
# because the hub project is shared between environments.
module "sa_tf_infra" {
  source       = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/iam-service-account?ref=5b9de0cf7bb5163ef8d0fa4973f31dd36b6de528"
  project_id   = module.core_project["iac_core"].project_id
  name         = "network-tf-infra-sa"
  display_name = "Terraform infra executor"
  description  = "Runs gcp-infrastructure-lz Terraform for all network projects (hub, shared-prod, shared-nonprod)."
}

# Workload SAs: one per YAML file in Stage 4. No project roles at creation time —
# Stage 4 grants each SA on its own project once that project exists.
module "sa_workload" {
  source       = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/iam-service-account?ref=5b9de0cf7bb5163ef8d0fa4973f31dd36b6de528"
  for_each     = local.workload_sa_map
  project_id   = module.core_project["iac_core"].project_id
  name         = each.value.sa_name
  display_name = "Workload executor — ${each.key}"
  description  = "Runs ${each.value.repository} Terraform. Scoped to ${each.key} project and '${each.value.github_env}' environment only."
}

# ──────────────────────── WIF pool — direct provider resources ───────────────
# Using direct resources instead of the CFF module because the public CFF repo
# does not include an iam-workload-identity-pool module. Direct resources also
# give native support for attribute_mapping with no uncertainty.

resource "google_iam_workload_identity_pool" "github" {
  project                   = module.core_project["iac_core"].project_id
  workload_identity_pool_id = "github"
  display_name              = "GitHub Actions OIDC"
  description               = "WIF pool — single pool for all GitHub Actions pipelines"
}

resource "google_iam_workload_identity_pool_provider" "github_actions" {
  project                            = module.core_project["iac_core"].project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-actions"
  display_name                       = "GitHub Actions"

  # Map JWT claims → GCP attributes. attribute.environment MUST be mapped —
  # all infra and workload SA IAM conditions depend on it.
  attribute_mapping = {
    "google.subject"        = "assertion.sub"
    "attribute.repository"  = "assertion.repository"
    "attribute.environment" = "assertion.environment"
    "attribute.ref"         = "assertion.ref"
    "attribute.workflow"    = "assertion.workflow"
  }

  # Pool-level gate: reject any token not from our GitHub org.
  attribute_condition = "assertion.repository_owner == '${var.github_org}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
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
    "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_org}/${var.bootstrap_repository}",
  ]
}

# Infra SA: any job in gcp-infrastructure-lz may impersonate (plan + apply, all envs).
# Hub is shared between prod and nonprod — environment segregation at SA level adds
# complexity without meaningful security gain for a shared network plane.
resource "google_service_account_iam_binding" "wif_infra" {
  service_account_id = module.sa_tf_infra.id
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_org}/${var.infra_lz_repository}",
  ]
}

# Workload SAs: one binding per YAML file. Each SA is bound to exactly one repo
# and one GitHub Environment — no cross-repo or cross-environment impersonation.
resource "google_service_account_iam_binding" "wif_workload" {
  for_each           = local.workload_sa_map
  service_account_id = module.sa_workload[each.key].id
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_org}/${each.value.repository}",
  ]
  condition {
    title       = "${each.key}-env-gate"
    description = "Only the '${each.value.github_env}' GitHub Environment of ${each.value.repository} may impersonate this SA."
    expression  = "attribute.environment == \"${each.value.github_env}\""
  }
}

module "sa_billing_reader" {
  source       = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/iam-service-account?ref=5b9de0cf7bb5163ef8d0fa4973f31dd36b6de528"
  project_id   = module.core_project["billing"].project_id
  name         = "billing-reader-sa"
  display_name = "Billing export reader"
  description  = "Reads billing exports for reporting. No write access."
}

module "sa_logging_reader" {
  source       = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/iam-service-account?ref=5b9de0cf7bb5163ef8d0fa4973f31dd36b6de528"
  project_id   = module.core_project["logging"].project_id
  name         = "logging-reader-sa"
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
  source       = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/iam-service-account?ref=5b9de0cf7bb5163ef8d0fa4973f31dd36b6de528"
  project_id   = module.core_project["iac_core"].project_id
  name         = "prisma-cloud-sa"
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
