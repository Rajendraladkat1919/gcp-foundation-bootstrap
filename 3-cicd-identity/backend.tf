terraform {
  # The bucket is passed with -backend-config="bucket=..." (see docs/runbook-bootstrap.md).
  backend "gcs" {
    prefix = "bootstrap/2-cicd-identity"
  }
}
