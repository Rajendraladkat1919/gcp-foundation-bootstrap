module "naming" {
  source = "../../gcp-terraform-module/modules/naming"
  prefix = var.prefix
}

locals {
  terraform_executor = "serviceAccount:${module.naming.automation_service_account_emails["execute"]}"
}

# ------------------------------------------------------- central audit logs

module "audit_log_bucket" {
  source = "../../gcp-terraform-module/modules/logging-bucket"
  # Provider stores this as projects/<id>. The short id forces a new bucket.
  parent      = "projects/${module.naming.core_project_ids["logging"]}"
  parent_type = "project"
  name        = "org-audit"
  location    = var.region
  retention   = var.audit_log_retention_days
  locked      = var.lock_audit_log_bucket
  description = "Organization wide audit logs. Managed by Terraform."
}

# Flow logs stay out of the audit bucket. They are high volume and have a shorter retention.
module "network_log_bucket" {
  source = "../../gcp-terraform-module/modules/logging-bucket"
  # Provider stores this as projects/<id>. The short id forces a new bucket.
  parent      = "projects/${module.naming.core_project_ids["logging"]}"
  parent_type = "project"
  name        = "org-network"
  location    = var.region
  retention   = var.network_log_retention_days
  description = "VPC flow logs from the whole organization. Managed by Terraform."
}

# --------------------------------------------------------------- organization

module "organization" {
  source          = "../../gcp-terraform-module/modules/organization"
  organization_id = var.organization_id
  factories_config = {
    org_policies = "${path.module}/policies/org-policies"
  }
  context = {
    condition_vars = {
      organization = {
        domain = var.domain
      }
    }
  }
  org_policies = local.org_policies

  logging_data_access = var.enable_data_access_logs ? {
    allServices = {
      ADMIN_READ = {}
      DATA_READ  = {}
      DATA_WRITE = {}
    }
  } : {}

  logging_sinks = {
    audit = {
      description      = "Admin activity, data access, system events and policy denied logs from the whole organization."
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
  }

  # Additive only: this stage must never remove an IAM member it did not add.
  iam_by_principals_additive = {
    "group:${var.groups.platform_engineers}" = [
      "roles/iam.securityReviewer",
      "roles/logging.viewer",
      "roles/orgpolicy.policyViewer",
      "roles/resourcemanager.folderViewer",
      "roles/resourcemanager.organizationViewer",
    ]
  }
}

# ------------------------------------------------------------------- folders

locals {
  infrastructure_children = {
    network = "Network"
    prod    = module.naming.environments["prod"].folder_name
    nonprod = module.naming.environments["nonprod"].folder_name
  }

  # xpnAdmin here so stage 2 can enable Shared VPC hosts in projects it creates.
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

  business_unit_environments = {
    for pair in setproduct(keys(var.business_units), keys(module.naming.environments)) :
    "${pair[0]}/${pair[1]}" => {
      business_unit = pair[0]
      environment   = pair[1]
      folder_name   = module.naming.environments[pair[1]].folder_name
    }
  }
}

module "folder_infrastructure" {
  source              = "../../gcp-terraform-module/modules/folder"
  parent              = var.organization_id
  name                = "Infrastructure"
  deletion_protection = !var.allow_destroy
  iam_bindings_additive = {
    terraform_executor_shared_vpc_admin = {
      member = local.terraform_executor
      role   = "roles/compute.xpnAdmin"
    }
    terraform_executor_folder_viewer = {
      member = local.terraform_executor
      role   = "roles/resourcemanager.folderViewer"
    }
  }
}

module "folder_workloads" {
  source              = "../../gcp-terraform-module/modules/folder"
  parent              = var.organization_id
  name                = "Workloads"
  deletion_protection = !var.allow_destroy
  iam_bindings_additive = {
    terraform_executor_shared_vpc_admin = {
      member = local.terraform_executor
      role   = "roles/compute.xpnAdmin"
    }
    terraform_executor_folder_viewer = {
      member = local.terraform_executor
      role   = "roles/resourcemanager.folderViewer"
    }
  }
}

module "folder_infrastructure_children" {
  source                = "../../gcp-terraform-module/modules/folder"
  for_each              = local.infrastructure_children
  parent                = module.folder_infrastructure.id
  name                  = each.value
  deletion_protection   = !var.allow_destroy
  iam_bindings_additive = each.key == "network" ? local.network_folder_iam : {}
}

module "folder_business_units" {
  source              = "../../gcp-terraform-module/modules/folder"
  for_each            = var.business_units
  parent              = module.folder_workloads.id
  name                = each.value.display_name
  deletion_protection = !var.allow_destroy
  iam_bindings_additive = {
    business_unit_group_folder_viewer = {
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
