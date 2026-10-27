module "naming" {
  source = "../../gcp-terraform-module/modules/naming"
  prefix = var.prefix
}

locals {
  iac_core_project = module.naming.core_project_ids["iac_core"]

  # Pool condition must list workload repos or their tokens are rejected before binding evaluation.
  workload_repositories = [
    for f in fileset("${path.module}/../4-workload-projects/data/projects", "*.yaml") :
    yamldecode(file("${path.module}/../4-workload-projects/data/projects/${f}")).repository
  ]

  token_repositories = distinct(concat(
    [for p in values(var.pipelines) : "${var.github_org}/${p.repository}"],
    [for r in local.workload_repositories : "${var.github_org}/${r}"],
    [for r in var.additional_repositories : "${var.github_org}/${r}"],
  ))

  executor = "projects/${local.iac_core_project}/serviceAccounts/${module.naming.automation_service_account_emails["execute"]}"

  # additional_repositories get pool access only; only pipeline and workload repos get impersonation.
  executor_repositories = toset(distinct(concat(
    [for p in values(var.pipelines) : p.repository],
    local.workload_repositories,
  )))
}

module "github_wif" {
  source       = "../../gcp-terraform-module/modules/iam-workload-identity-pool"
  project_id   = local.iac_core_project
  pool_id      = "github"
  provider_id  = "github-actions"
  display_name = "GitHub Actions"

  # Restrict token minting to our org's listed repositories.
  attribute_condition ="assertion.repository_owner == '${var.github_org}' && assertion.repository in [${join(", ", formatlist("'%s'", local.token_repositories))}]"
}

# Any ref can impersonate (so PR plans work); apply still requires the production environment.
resource "google_service_account_iam_member" "execute" {
  for_each           = local.executor_repositories
  service_account_id = local.executor
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${module.github_wif.pool_name}/attribute.repository/${var.github_org}/${each.value}"
}
