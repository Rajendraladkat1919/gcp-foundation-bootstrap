variable "additional_repositories" {
  description = "Extra repositories that may mint a token from this pool but do not get a bootstrap or landing-zone service account. cicd-runners is the usual entry. Workload repositories are read from stage 3 YAML and do not belong here."
  type        = list(string)
  default     = []
}

variable "github_org" {
  description = "GitHub organization that owns the repositories. Tokens from any other owner are rejected by the provider."
  type        = string
}

variable "pipelines" {
  description = "Repositories allowed to impersonate automation service accounts. The plan service account is reachable from any ref of the repository (pull requests), the apply service account only from apply_ref."
  type = map(object({
    repository            = string
    plan_service_account  = string
    apply_service_account = string
    apply_ref             = optional(string, "refs/heads/main")
  }))

  validation {
    condition     = alltrue([for p in values(var.pipelines) : startswith(p.apply_ref, "refs/")])
    error_message = "apply_ref must be a full git ref such as refs/heads/main."
  }
}

variable "prefix" {
  description = "Short organization prefix used in every project id and bucket name."
  type        = string
}
