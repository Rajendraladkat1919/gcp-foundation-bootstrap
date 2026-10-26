# No user_project_override here: this stage creates the project that would
# be billed. Later stages set billing_project to the iac-core project.
provider "google" {}

provider "google-beta" {}
