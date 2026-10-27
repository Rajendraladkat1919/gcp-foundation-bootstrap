variable "additional_repositories" {
  description = "Extra repositories that may mint a token from this pool but do not get dev-terraform-execute. cicd-runners is the usual entry. Workload repositories are read from 4-workload-projects YAML and do not belong here."
  type        = list(string)
  default     = []
}

variable "github_org" {
  description = "GitHub organization that owns the repositories. Tokens from any other owner are rejected by the provider."
  type        = string
}

variable "pipelines" {
  description = "Repositories that may impersonate dev-terraform-execute. Workload repositories are added from 4-workload-projects YAML."
  type = map(object({
    repository = string
  }))
}

variable "prefix" {
  description = "Short organization prefix used in every project id and bucket name."
  type        = string
}
