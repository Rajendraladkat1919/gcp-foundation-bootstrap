terraform {
  # The bucket is passed with -backend-config="bucket=..." (see docs/runbook-bootstrap.md).
  # The very first apply uses local state and then migrates here.
  backend "gcs" {
    prefix = "bootstrap/1-org"
  }
}
