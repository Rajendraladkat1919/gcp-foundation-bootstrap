module "naming" {
  source = "../modules/naming"
  prefix = var.prefix
}

locals {
  iac_core_project = module.naming.core_project_ids["iac_core"]

  # Stage 3 binds each workload repository to its own service accounts. The pool
  # condition has to name those repositories too, or their tokens are rejected
  # before the binding is evaluated. Adding a YAML re-applies this stage
  # (scripts/changed-stages.sh).
  workload_repositories = [
    for f in fileset("${path.module}/../3-workload-projects/data/projects", "*.yaml") :
    yamldecode(file("${path.module}/../3-workload-projects/data/projects/${f}")).repository
  ]

  token_repositories = distinct(concat(
    [for p in values(var.pipelines) : "${var.github_org}/${p.repository}"],
    [for r in local.workload_repositories : "${var.github_org}/${r}"],
    [for r in var.additional_repositories : "${var.github_org}/${r}"],
  ))
}

module "github_wif" {
  source       = "../../gcp-terraform-module/modules/iam-workload-identity-pool"
  project_id   = local.iac_core_project
  pool_id      = "github"
  provider_id  = "github-actions"
  display_name = "GitHub Actions"

  # Only the listed repositories of our own organization can mint a usable token.
  attribute_condition = "assertion.repository_owner == '${var.github_org}' && assertion.repository in [${join(", ", formatlist("'%s'", local.token_repositories))}]"
}

locals {
  service_account_resource = {
    for k, p in var.pipelines : k => {
      plan  = "projects/${local.iac_core_project}/serviceAccounts/${p.plan_service_account}@${local.iac_core_project}.iam.gserviceaccount.com"
      apply = "projects/${local.iac_core_project}/serviceAccounts/${p.apply_service_account}@${local.iac_core_project}.iam.gserviceaccount.com"
    }
  }
}

# Plans: any ref of the repository, so pull requests and the nightly drift check work.
resource "google_service_account_iam_member" "plan" {
  for_each           = var.pipelines
  service_account_id = local.service_account_resource[each.key].plan
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${module.github_wif.pool_name}/attribute.repository/${var.github_org}/${each.value.repository}"
}

# Applies: only the protected ref. The GitHub environment adds a human approval on top.
resource "google_service_account_iam_member" "apply" {
  for_each           = var.pipelines
  service_account_id = local.service_account_resource[each.key].apply
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${module.github_wif.pool_name}/attribute.fast_sub/repo:${var.github_org}/${each.value.repository}:ref:${each.value.apply_ref}"
}
