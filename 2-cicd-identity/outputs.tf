output "github_actions_variables" {
  description = "Values to store as GitHub Actions repository variables (not secrets) in the pipeline repositories."
  value = {
    WIF_PROVIDER = module.github_wif.provider_name
  }
}

output "workload_identity_pool_name" {
  description = "Fully qualified workload identity pool name, used to build principalSet members."
  value       = module.github_wif.pool_name
}

output "workload_identity_provider_name" {
  description = "Fully qualified provider name. This is the WIF_PROVIDER variable of every pipeline repository."
  value       = module.github_wif.provider_name
}
