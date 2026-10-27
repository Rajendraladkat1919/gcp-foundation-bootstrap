terraform {
  # The bucket is passed with -backend-config="bucket=..." (see docs/runbook-bootstrap.md).
  # The very first apply uses local state and then migrates here.
  backend "gcs" {
    # Kept. This stage was first applied under this key.
    prefix = "bootstrap/3-workload-projects"
  }
}
