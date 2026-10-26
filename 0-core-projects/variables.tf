variable "access_log_retention_days" {
  description = "Retention, in days, of the Cloud Storage access log bucket."
  type        = number
  default     = 400

  validation {
    condition     = var.access_log_retention_days >= 365
    error_message = "Access logs must be kept for at least 365 days."
  }
}

variable "billing_account_id" {
  description = "Billing account id in ABCDEF-123456-ABCDEF format."
  type        = string

  validation {
    condition     = can(regex("^[A-Z0-9]{6}-[A-Z0-9]{6}-[A-Z0-9]{6}$", var.billing_account_id))
    error_message = "billing_account_id must look like ABCDEF-123456-ABCDEF."
  }
}

variable "cost_center" {
  description = "Cost center label applied to every resource this stage creates."
  type        = string
}

variable "lock_log_retention" {
  description = "Lock the retention policy of the access log bucket. Irreversible, enable only after the retention period is confirmed."
  type        = bool
  default     = false
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
  description = "Region for state buckets, the KMS key ring and the access log bucket. Must be allowed by the location org policy."
  type        = string
}
