variable "allow_destroy" {
  description = "Lift deletion protection in this stage. Apply with -var allow_destroy=true before terraform destroy."
  type        = bool
  default     = false
}

variable "allowed_locations" {
  description = "Value groups or regions allowed by the gcp.resourceLocations organization policy."
  type        = list(string)
  default     = ["in:us-locations"]
}

variable "allowed_workload_identity_issuers" {
  description = "OIDC issuers allowed in workload identity pool providers."
  type        = list(string)
  default     = ["https://token.actions.githubusercontent.com"]
}

variable "audit_log_retention_days" {
  description = "Retention, in days, of the central organization audit log bucket."
  type        = number
  default     = 400

  validation {
    condition     = var.audit_log_retention_days >= 365
    error_message = "Audit logs must be kept for at least 365 days."
  }
}

variable "business_units" {
  description = "Business units under the Workloads folder. The key is a stable slug, display_name is the folder name, group is the Google group that can browse the folder."
  type = map(object({
    display_name = string
    group        = string
  }))
}

variable "domain" {
  description = "Primary domain. Essential contacts are limited to it."
  type        = string
}

variable "enable_data_access_logs" {
  description = "Turn on ADMIN_READ, DATA_READ and DATA_WRITE audit logs for every service. Required by most compliance frameworks, and billed by log volume."
  type        = bool
  default     = true
}

variable "groups" {
  description = "Google groups, as email addresses. They must already exist in Cloud Identity."
  type = object({
    platform_engineers = string
  })
}

variable "lock_audit_log_bucket" {
  description = "Lock the audit log bucket retention. Irreversible, enable only once the retention period is confirmed."
  type        = bool
  default     = false
}

variable "network_log_retention_days" {
  description = "Retention, in days, of the central VPC flow log bucket. Flow logs are high volume, so this is shorter than the audit bucket."
  type        = number
  default     = 30

  validation {
    condition     = var.network_log_retention_days >= 1
    error_message = "Network log retention must be at least 1 day."
  }
}

variable "organization_id" {
  description = "Organization id in organizations/NNNNNNNNNNNN format."
  type        = string

  validation {
    condition     = can(regex("^organizations/[0-9]+$", var.organization_id))
    error_message = "organization_id must look like organizations/123456789012."
  }
}

variable "prefix" {
  description = "Short organization prefix used in every project id and bucket name."
  type        = string
}

variable "region" {
  description = "Region of the central audit log bucket."
  type        = string
}
