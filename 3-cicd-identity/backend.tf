terraform {
  # The bucket is passed with -backend-config="bucket=..." (see docs/runbook-bootstrap.md).
  backend "gcs" {
    # Kept. This stage was first applied under this key.
    prefix = "bootstrap/2-cicd-identity"
  }
}
