# REPLACE_ME values below before the first apply. Nothing here is secret.
prefix     = "pe"
github_org = "twlabs"

# Same pool as the pipelines. This repository does not get a Terraform service account.
additional_repositories = ["cicd-runners"]

# Keys of service accounts are the account ids created in 0-core-projects.
pipelines = {
  bootstrap = {
    repository            = "gcp-foundation-bootstrap"
    plan_service_account  = "sa-tf-bootstrap-plan"
    apply_service_account = "sa-tf-bootstrap-apply"
  }
  lz = {
    repository            = "gcp-infrastructure-lz"
    plan_service_account  = "sa-tf-lz-plan"
    apply_service_account = "sa-tf-lz-apply"
  }
}
