# Kept commented. rala@ cannot call groups.create (Cloud Identity error 2015).
# A previous apply destroyed grp-billing-viewers and failed to recreate it.
# Leave this commented. Groups come from the console or Okta SCIM.
# Organization IAM uses the emails in terraform.tfvars, not these resources.

/*
locals {
  group_parent = "customers/${var.directory_customer_id}"
  group_labels = { "cloudidentity.googleapis.com/groups.discussion_forum" = "" }
}

resource "google_cloud_identity_group" "audit_viewers" {
  display_name         = "Audit Viewers"
  description          = "Read-only access to Cloud Logging audit buckets and log entries. For security ops and compliance auditors."
  parent               = local.group_parent
  initial_group_config = "EMPTY"

  group_key {
    id = "grp-audit-viewers@${var.domain}"
  }

  labels = local.group_labels
}

resource "google_cloud_identity_group" "billing_viewers" {
  display_name         = "Billing Viewers"
  description          = "Read-only access to billing accounts, budgets, and the billing export BigQuery dataset. For FinOps and chargeback tooling."
  parent               = local.group_parent
  initial_group_config = "EMPTY"

  group_key {
    id = "grp-billing-viewers@${var.domain}"
  }

  labels = local.group_labels
}

resource "google_cloud_identity_group" "network_viewers" {
  display_name         = "Network Viewers"
  description          = "Read-only access to VPC, firewall, DNS, and route configuration. For on-premises network team integration audits."
  parent               = local.group_parent
  initial_group_config = "EMPTY"

  group_key {
    id = "grp-network-viewers@${var.domain}"
  }

  labels = local.group_labels
}

resource "google_cloud_identity_group" "security_reviewers" {
  display_name         = "Security Reviewers"
  description          = "Broad read-only security access: IAM policies, service accounts, Cloud Asset Inventory, KMS keys. Used by Prisma Cloud and XSIAM integrations."
  parent               = local.group_parent
  initial_group_config = "EMPTY"

  group_key {
    id = "grp-security-reviewers@${var.domain}"
  }

  labels = local.group_labels
}

resource "google_cloud_identity_group" "break_glass" {
  display_name         = "Break Glass"
  description          = "Emergency access group. Members can view org structure during an incident. Membership should be tightly controlled and reviewed quarterly."
  parent               = local.group_parent
  initial_group_config = "EMPTY"

  group_key {
    id = "grp-break-glass@${var.domain}"
  }

  labels = local.group_labels
}
*/
