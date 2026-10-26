variable "prefix" {
  description = "Short organization prefix used in every project id and bucket name, for example pe. Lowercase letters and digits, 2 to 10 characters."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.prefix))
    error_message = "prefix must be 2 to 10 lowercase letters or digits and start with a letter."
  }
}
