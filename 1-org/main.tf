module "naming" {
  source = "../../gcp-terraform-module/modules/naming"
  prefix = var.prefix
}

locals {
  # ── Convenience references ───────────────────────────────────────────────────
  org_id_numeric         = trimprefix(var.organization_id, "organizations/")
  iac_core_project       = module.naming.core_project_ids["iac_core"]
  # sa-tf-bootstrap owns all bootstrap stages; explicit email avoids naming-module coupling.
  terraform_executor     = "serviceAccount:sa-tf-bootstrap@${local.iac_core_project}.iam.gserviceaccount.com"
  logging_project        = module.naming.core_project_ids["logging"]
  xsiam_topic_resource   = "pubsub.googleapis.com/projects/${local.iac_core_project}/topics/${var.prefix}-pr-xsiam"
  prisma_cloud_sa_member = "serviceAccount:sa-prisma-cloud@${local.iac_core_project}.iam.gserviceaccount.com"

  # ── Folder IAM ───────────────────────────────────────────────────────────────
  # Both top-level folders (Infrastructure, Workloads) need the same executor bindings.
  top_level_folder_iam = {
    terraform_executor_xpn_admin = {
      member = local.terraform_executor
      role   = "roles/compute.xpnAdmin"
    }
    terraform_executor_folder_viewer = {
      member = local.terraform_executor
      role   = "roles/resourcemanager.folderViewer"
    }
  }

  # Extra bindings for the Network sub-folder — executor needs full network admin there.
  network_folder_iam = {
    terraform_executor_network_admin = {
      member = local.terraform_executor
      role   = "roles/compute.networkAdmin"
    }
    terraform_executor_security_admin = {
      member = local.terraform_executor
      role   = "roles/compute.securityAdmin"
    }
    terraform_executor_dns_admin = {
      member = local.terraform_executor
      role   = "roles/dns.admin"
    }
    terraform_executor_ncc_admin = {
      member = local.terraform_executor
      role   = "roles/networkconnectivity.admin"
    }
    terraform_executor_service_networking = {
      member = local.terraform_executor
      role   = "roles/servicenetworking.networksAdmin"
    }
    terraform_executor_xpn_admin = {
      member = local.terraform_executor
      role   = "roles/compute.xpnAdmin"
    }
  }

  # ── Folder layout ────────────────────────────────────────────────────────────
  # Infrastructure only needs a single Network sub-folder; all three network projects
  # (hub, shared-prod, shared-nonprod) live there. Prod/NonProd env-split is done
  # inside the Workloads tree, not here.
  infrastructure_children = {
    network = "Network"
  }

  business_unit_environments = {
    for pair in setproduct(keys(var.business_units), keys(module.naming.environments)) :
    "${pair[0]}/${pair[1]}" => {
      business_unit = pair[0]
      environment   = pair[1]
      folder_name   = module.naming.environments[pair[1]].folder_name
    }
  }

  # ── Okta group IAM ───────────────────────────────────────────────────────────
  # Only include a group when its email is non-empty (optional fields in var.groups).
  optional_group_bindings = merge(
    var.groups.audit_viewers != "" ? {
      "group:${var.groups.audit_viewers}" = ["roles/logging.viewer", "roles/iam.securityReviewer"]
    } : {},
    var.groups.billing_viewers != "" ? {
      "group:${var.groups.billing_viewers}" = ["roles/billing.viewer"]
    } : {},
    var.groups.network_viewers != "" ? {
      "group:${var.groups.network_viewers}" = ["roles/compute.networkViewer"]
    } : {},
    var.groups.security_reviewers != "" ? {
      "group:${var.groups.security_reviewers}" = [
        "roles/iam.securityReviewer",
        "roles/logging.viewer",
        "roles/orgpolicy.policyViewer",
      ]
    } : {},
    var.groups.break_glass != "" ? {
      "group:${var.groups.break_glass}" = ["roles/resourcemanager.organizationViewer"]
    } : {},
  )
}

# ──────────────────────────────────────────────────────── central audit logs

module "audit_log_bucket" {
  source = "../../gcp-terraform-module/modules/logging-bucket"
  # Provider stores this as projects/<id>. The short id forces a new bucket on rename.
  parent      = "projects/${module.naming.core_project_ids["logging"]}"
  parent_type = "project"
  name        = "org-audit"
  location    = var.region
  retention   = var.audit_log_retention_days
  locked      = var.lock_audit_log_bucket
  description = "Organization-wide audit logs. Managed by Terraform."
}

# Flow logs use a separate bucket — they are high-volume with a shorter retention.
module "network_log_bucket" {
  source      = "../../gcp-terraform-module/modules/logging-bucket"
  parent      = "projects/${module.naming.core_project_ids["logging"]}"
  parent_type = "project"
  name        = "org-network"
  location    = var.region
  retention   = var.network_log_retention_days
  description = "VPC flow logs from the whole organization. Managed by Terraform."
}

# ──────────────────────────────────────────────────────────────── organization

module "organization" {
  source          = "../../gcp-terraform-module/modules/organization"
  organization_id = var.organization_id
  factories_config = {
    org_policies = "${path.module}/policies/org-policies"
  }
  context = {
    condition_vars = {
      organization = { domain = var.domain }
    }
  }
  org_policies = local.org_policies

  logging_data_access = var.enable_data_access_logs ? {
    allServices = { ADMIN_READ = {}, DATA_READ = {}, DATA_WRITE = {} }
  } : {}

  logging_sinks = {
    audit = {
      description      = "Admin activity, data access, system events and policy denied logs from the whole org."
      destination      = module.audit_log_bucket.id
      filter           = "logName:\"/logs/cloudaudit.googleapis.com\" OR logName:\"/logs/access_transparency\""
      include_children = true
      type             = "logging"
    }
    network = {
      description      = "VPC flow logs from every subnet. Kept apart from the audit bucket."
      destination      = module.network_log_bucket.id
      filter           = "log_id(\"compute.googleapis.com/vpc_flows\")"
      include_children = true
      type             = "logging"
    }
    iam = {
      description      = "IAM service and admin activity changes across the whole org."
      destination      = module.audit_log_bucket.id
      filter           = "protoPayload.serviceName:(\"iam.googleapis.com\" OR \"admin.googleapis.com\") AND logName:\"/logs/cloudaudit.googleapis.com\""
      include_children = true
      type             = "logging"
    }
    vpc_sc = {
      description      = "VPC Service Controls and Access Context Manager audit events."
      destination      = module.audit_log_bucket.id
      filter           = "protoPayload.serviceName=\"accesscontextmanager.googleapis.com\" AND logName:\"/logs/cloudaudit.googleapis.com\""
      include_children = true
      type             = "logging"
    }
  }

  # Additive only: this stage must never remove an IAM member it did not add.
  iam_by_principals_additive = merge(
    {
      "group:${var.groups.platform_engineers}" = [
        "roles/iam.securityReviewer",
        "roles/logging.viewer",
        "roles/orgpolicy.policyViewer",
        "roles/resourcemanager.folderViewer",
        "roles/resourcemanager.organizationViewer",
      ]
    },
    local.optional_group_bindings,
  )
}

# ──────────────────────────────────────────────────────────────────── folders

module "folder_infrastructure" {
  source                = "../../gcp-terraform-module/modules/folder"
  parent                = var.organization_id
  name                  = "Infrastructure"
  deletion_protection   = !var.allow_destroy
  iam_bindings_additive = local.top_level_folder_iam
}

module "folder_workloads" {
  source                = "../../gcp-terraform-module/modules/folder"
  parent                = var.organization_id
  name                  = "Workloads"
  deletion_protection   = !var.allow_destroy
  iam_bindings_additive = local.top_level_folder_iam
}

module "folder_infrastructure_children" {
  source              = "../../gcp-terraform-module/modules/folder"
  for_each            = local.infrastructure_children
  parent              = module.folder_infrastructure.id
  name                = each.value
  deletion_protection = !var.allow_destroy
  # Only the Network folder gets the extended network admin bindings.
  iam_bindings_additive = each.key == "network" ? local.network_folder_iam : {}
}

module "folder_business_units" {
  source              = "../../gcp-terraform-module/modules/folder"
  for_each            = var.business_units
  parent              = module.folder_workloads.id
  name                = each.value.display_name
  deletion_protection = !var.allow_destroy
  iam_bindings_additive = {
    bu_group_folder_viewer = {
      member = "group:${each.value.group}"
      role   = "roles/resourcemanager.folderViewer"
    }
  }
}

module "folder_business_unit_environments" {
  source              = "../../gcp-terraform-module/modules/folder"
  for_each            = local.business_unit_environments
  parent              = module.folder_business_units[each.value.business_unit].id
  name                = each.value.folder_name
  deletion_protection = !var.allow_destroy
}

# ───────────────────────────────────────────────────────────── XSIAM log sink

# Standalone resource (not inside module.organization) so writer_identity is exposed for Pub/Sub IAM.
resource "google_logging_organization_sink" "xsiam" {
  name             = "xsiam"
  org_id           = local.org_id_numeric
  destination      = local.xsiam_topic_resource
  description      = "Routes WARNING+ severity and all audit activity to the XSIAM SIEM Pub/Sub topic."
  include_children = true
  filter           = "severity >= WARNING OR logName:\"/logs/cloudaudit.googleapis.com\""
}

resource "google_pubsub_topic_iam_member" "xsiam_logging_writer" {
  project = local.iac_core_project
  topic   = "${var.prefix}-pr-xsiam"
  role    = "roles/pubsub.publisher"
  member  = google_logging_organization_sink.xsiam.writer_identity
}

# ─────────────────────────────────────────────────────── essential contacts

resource "google_essential_contacts_contact" "security" {
  count                               = var.security_contact_email != "" ? 1 : 0
  parent                              = var.organization_id
  email                               = var.security_contact_email
  language_tag                        = "en-US"
  notification_category_subscriptions = ["SECURITY", "SUSPENSION", "TECHNICAL_INCIDENTS"]
}

resource "google_essential_contacts_contact" "platform" {
  parent                              = var.organization_id
  email                               = var.groups.platform_engineers
  language_tag                        = "en-US"
  notification_category_subscriptions = ["TECHNICAL", "LEGAL", "BILLING"]
}

# ────────────────────────────────────── Prisma Cloud + SCC (both optional)

# SCC findingsViewer lets Prisma Cloud correlate its posture findings with SCC results.
resource "google_organization_iam_member" "prisma_cloud_scc_viewer" {
  count  = var.enable_scc ? 1 : 0
  org_id = local.org_id_numeric
  role   = "roles/securitycenter.findingsViewer"
  member = local.prisma_cloud_sa_member
}

# Routes all active SCC findings to the XSIAM Pub/Sub topic.
# enable_scc must be true in BOTH Stage 0 (API + SA roles) and Stage 1.
resource "google_scc_notification_config" "all_findings" {
  count        = var.enable_scc ? 1 : 0
  config_id    = "all-active-findings"
  organization = local.org_id_numeric
  description  = "Routes all active SCC findings to the XSIAM SIEM Pub/Sub topic."
  pubsub_topic = "projects/${local.iac_core_project}/topics/${var.prefix}-pr-xsiam"
  streaming_config {
    filter = "state = \"ACTIVE\""
  }
}

resource "google_pubsub_topic_iam_member" "scc_publisher" {
  count   = var.enable_scc ? 1 : 0
  project = local.iac_core_project
  topic   = "${var.prefix}-pr-xsiam"
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:service-${local.org_id_numeric}@gcp-sa-scc.iam.gserviceaccount.com"
}
