# Custom IAM roles at organization level.
# Roles are additive to the predefined roles bound to Okta-provisioned groups in main.tf.
# Validate permissions with: gcloud iam list-testable-permissions //cloudresourcemanager.googleapis.com/organizations/ORG_ID

locals {
  custom_roles = {
    "orgIacViewer" = {
      title       = "Org IaC Viewer"
      description = "Read-only access to the org/folder/project hierarchy and IAM policies. For IaC audit tooling."
      permissions = [
        "resourcemanager.organizations.get",
        "resourcemanager.organizations.getIamPolicy",
        "resourcemanager.folders.list",
        "resourcemanager.folders.get",
        "resourcemanager.folders.getIamPolicy",
        "resourcemanager.projects.list",
        "resourcemanager.projects.get",
        "resourcemanager.projects.getIamPolicy",
        "iam.roles.list",
        "iam.roles.get",
        "orgpolicy.policies.list",
        "orgpolicy.policies.get",
        "orgpolicy.constraints.list",
      ]
    }
    "orgAuditLogViewer" = {
      title       = "Org Audit Log Viewer"
      description = "Read audit logs and Cloud Logging config. For security operations team."
      permissions = [
        "logging.logEntries.list",
        "logging.logEntries.listPrivilegedActivity",
        "logging.logs.list",
        "logging.buckets.list",
        "logging.buckets.get",
        "logging.views.list",
        "logging.views.get",
        "logging.views.access",
        "logging.sinks.list",
        "logging.sinks.get",
        "logging.exclusions.list",
        "logging.exclusions.get",
      ]
    }
    "orgBillingViewer" = {
      title       = "Org Billing Viewer"
      description = "Read billing accounts, budgets, and credits. For FinOps and chargeback tooling."
      permissions = [
        "billing.accounts.get",
        "billing.accounts.list",
        "billing.budgets.get",
        "billing.budgets.list",
        "billing.credits.list",
        "resourcemanager.organizations.get",
      ]
    }
    "orgNetworkViewer" = {
      title       = "Org Network Viewer"
      description = "Read-only VPC, firewall, DNS, and route config. For on-prem network team integration audits."
      permissions = [
        "compute.networks.list",
        "compute.networks.get",
        "compute.subnetworks.list",
        "compute.subnetworks.get",
        "compute.firewalls.list",
        "compute.firewalls.get",
        "compute.routes.list",
        "compute.routes.get",
        "compute.routers.list",
        "compute.routers.get",
        "compute.vpnGateways.list",
        "compute.vpnTunnels.list",
        "compute.interconnects.list",
        "compute.interconnectAttachments.list",
        "dns.managedZones.list",
        "dns.managedZones.get",
        "dns.resourceRecordSets.list",
      ]
    }
    "orgSecurityReviewer" = {
      title       = "Org Security Reviewer"
      description = "Broad read-only security access: IAM, service accounts, Cloud Asset, KMS. For Prisma Cloud and XSIAM."
      permissions = [
        "iam.serviceAccounts.list",
        "iam.serviceAccounts.get",
        "iam.serviceAccountKeys.list",
        "iam.roles.list",
        "iam.roles.get",
        "cloudasset.assets.searchAllResources",
        "cloudasset.assets.searchAllIamPolicies",
        "cloudasset.assets.analyzeIamPolicy",
        "cloudkms.keyRings.list",
        "cloudkms.keyRings.get",
        "cloudkms.cryptoKeys.list",
        "cloudkms.cryptoKeys.get",
        "cloudkms.cryptoKeyVersions.list",
      ]
    }
    "orgKmsKeyViewer" = {
      title       = "Org KMS Key Viewer"
      description = "List and inspect KMS keys without the ability to use or modify them."
      permissions = [
        "cloudkms.keyRings.list",
        "cloudkms.keyRings.get",
        "cloudkms.cryptoKeys.list",
        "cloudkms.cryptoKeys.get",
        "cloudkms.cryptoKeyVersions.list",
        "cloudkms.cryptoKeyVersions.get",
        "cloudkms.importJobs.list",
        "cloudkms.importJobs.get",
      ]
    }
  }
}

resource "google_organization_iam_custom_role" "roles" {
  for_each    = local.custom_roles
  org_id      = local.org_id_numeric # defined in main.tf locals
  role_id     = each.key
  title       = each.value.title
  description = each.value.description
  stage       = "GA"
  permissions = each.value.permissions
}
