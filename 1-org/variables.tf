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

variable "directory_customer_id" {
  description = "Cloud Identity customer ID (format: C0xxxxxxxxx). Found in Google Admin console → Account → Account Settings, or via: gcloud organizations describe ORG_ID --format='value(owner.directoryCustomerId)'. Required to create Cloud Identity groups via Terraform."
  type        = string
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
  description = "Okta-provisioned Google groups in Cloud Identity. All fields are optional — leave as empty string to skip the IAM binding. Groups do not need to exist before the first apply; add emails once Okta SCIM has provisioned the groups and re-apply Stage 1."
  type = object({
    # All fields are optional so deployment can proceed before any groups are created.
    platform_engineers       = optional(string, "")
    business_unit_commercial = optional(string, "")
    developers               = optional(string, "")
    audit_viewers            = optional(string, "")
    billing_viewers          = optional(string, "")
    network_viewers          = optional(string, "")
    security_reviewers       = optional(string, "")
    break_glass              = optional(string, "")
  })
  default = {}
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

variable "enable_scc" {
  description = "Create SCC notification config that routes all active findings to the XSIAM Pub/Sub topic. Requires SCC Premium/Enterprise to be manually activated in the console first, and enable_scc=true in Stage 0."
  type        = bool
  default     = false
}

variable "monitoring_notification_email" {
  description = "Email address for Cloud Monitoring alert notifications (security config-change alerts). Leave empty to skip notification channel creation."
  type        = string
  default     = ""
}

variable "security_contact_email" {
  description = "Email address for the Essential Contacts security category (SECURITY, SUSPENSION, TECHNICAL_INCIDENTS). Must match the organization domain. Leave empty to skip creation."
  type        = string
  default     = ""
}

