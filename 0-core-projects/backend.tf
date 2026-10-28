terraform {
  # The bucket is passed with -backend-config="bucket=..." (see docs/runbook-bootstrap.md).
  # First apply uses local state; run 'terraform init -migrate-state -backend-config="bucket=..."'
  # once the bucket exists. After migration, CI initialises this stage the same as every other.
  backend "gcs" {
    prefix = "bootstrap/0-core-projects"
  }
}
