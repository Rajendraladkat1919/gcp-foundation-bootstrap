# Single source of truth for names that more than one stage (or the LZ repo)
# must agree on. Nothing here creates a resource.

locals {
  tier = "pr"

  core_project_names = {
    iac_core = "${local.tier}-iac-core"
    billing  = "${local.tier}-billing"
    logging  = "${local.tier}-logging"
  }

  core_project_ids = {
    for k, v in local.core_project_names : k => "${var.prefix}-${v}"
  }

  automation_service_account_ids = {
    bootstrap_plan  = "sa-tf-bootstrap-plan"
    bootstrap_apply = "sa-tf-bootstrap-apply"
    lz_plan         = "sa-tf-lz-plan"
    lz_apply        = "sa-tf-lz-apply"
  }

  state_bucket_names = {
    bootstrap = "${local.tier}-tfstate-bootstrap"
    lz        = "${local.tier}-tfstate-lz"
  }

  environments = {
    prod = {
      code        = "pr"
      folder_name = "Prod"
    }
    nonprod = {
      code        = "np"
      folder_name = "Non-Prod"
    }
  }
}
