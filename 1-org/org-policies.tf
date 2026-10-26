locals {
  # Resource locations and workload identity issuers stay here because they
  # come from variables. Every other organization policy is a file under
  # policies/org-policies.
  org_policies = {
    "gcp.resourceLocations" = {
      rules = [{ allow = { values = var.allowed_locations } }]
    }
    "iam.workloadIdentityPoolProviders" = {
      rules = [{ allow = { values = var.allowed_workload_identity_issuers } }]
    }
  }
}
