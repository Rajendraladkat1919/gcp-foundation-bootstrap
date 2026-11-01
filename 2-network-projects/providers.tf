provider "google" {
  billing_project       = "${var.prefix}-pr-iac-core"
  user_project_override = true
}

provider "google-beta" {
  billing_project       = "${var.prefix}-pr-iac-core"
  user_project_override = true
}
