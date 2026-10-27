output "audit_log_bucket_id" {
  description = "Id of the central audit log bucket."
  value       = module.audit_log_bucket.id
}

output "network_log_bucket_id" {
  description = "Id of the central VPC flow log bucket."
  value       = module.network_log_bucket.id
}

output "folder_ids" {
  description = <<-EOT
    Folder IDs keyed by logical path. Useful keys for downstream stages:
      infrastructure                  — top-level Infrastructure folder
      infrastructure/network          — Network folder; hub + shared-prod + shared-nonprod projects live here
      workloads                       — top-level Workloads folder
      workloads/<bu>/<env>            — per business-unit / per environment folder (used by Stage 4)
  EOT
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

output "xsiam_pubsub_sink_writer" {
  description = "IAM writer_identity of the XSIAM org log sink — used to grant pubsub.publisher on the topic."
  value       = google_logging_organization_sink.xsiam.writer_identity
}

output "scc_notification_config_name" {
  description = "Resource name of the SCC all-findings notification config. Null when enable_scc is false."
  value       = var.enable_scc ? google_scc_notification_config.all_findings[0].name : null
}

output "monitoring_alert_policy_names" {
  description = "Display names of the 10 config-change alert policies."
  value       = [for p in google_monitoring_alert_policy.security : p.display_name]
}

output "custom_role_ids" {
  description = "Resource IDs of the custom IAM roles, keyed by role_id."
  value       = { for k, v in google_organization_iam_custom_role.roles : k => v.id }
}
