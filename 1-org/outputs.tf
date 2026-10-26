output "audit_log_bucket_id" {
  description = "Id of the central audit log bucket."
  value       = module.audit_log_bucket.id
}

output "network_log_bucket_id" {
  description = "Id of the central VPC flow log bucket."
  value       = module.network_log_bucket.id
}

output "folder_ids" {
  description = "Folder ids keyed by path: infrastructure, infrastructure/network, infrastructure/prod, workloads, workloads/<business unit>/<environment>, and so on."
  value = merge(
    {
      "infrastructure" = module.folder_infrastructure.id
      "workloads"      = module.folder_workloads.id
    },
    { for k, v in module.folder_infrastructure_children : "infrastructure/${k}" => v.id },
    { for k, v in module.folder_business_units : "workloads/${k}" => v.id },
    { for k, v in module.folder_business_unit_environments : "workloads/${k}" => v.id },
  )
}

output "org_policies_enforced" {
  description = "Names of the organization policies this stage manages."
  value       = sort(keys(module.organization.organization_policies_ids))
}
