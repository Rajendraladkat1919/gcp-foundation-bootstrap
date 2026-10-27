variable "allow_destroy" {
  description = "Lift deletion protection in this stage. Apply with -var allow_destroy=true before terraform destroy."
  type        = bool
  default     = false
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
  description = "Cost center label applied to every network project."
  type        = string
}

variable "prefix" {
  description = "Short organization prefix used in every project id and bucket name."
  type        = string
}
