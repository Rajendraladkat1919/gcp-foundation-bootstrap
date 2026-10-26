provider "google" {
  billing_project       = module.naming.core_project_ids["iac_core"]
  user_project_override = true
}

provider "google-beta" {
  billing_project       = module.naming.core_project_ids["iac_core"]
  user_project_override = true
}
