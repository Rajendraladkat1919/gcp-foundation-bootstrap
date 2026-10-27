locals {
  # Full path required by bucket-scoped log-based metrics.
  audit_bucket_path = "projects/${local.logging_project}/locations/${var.region}/buckets/org-audit"

  alert_combiner   = "OR"
  alert_duration   = "0s"
  alignment_period = "60s"
  notification_channels = (
    var.monitoring_notification_email != ""
    ? [google_monitoring_notification_channel.security_email[0].name]
    : []
  )

  # Each entry generates one log-based metric and one alert policy.
  # The map key becomes the metric name suffix: security/<key>.
  security_metrics = {
    "iam-org-changes" = {
      display_name = "IAM Org Changes"
      description  = "IAM policy changes at the organization level."
      alert_title  = "IAM org-level policy changed"
      filter       = "protoPayload.methodName=\"SetIamPolicy\" AND resource.type=\"organization\""
    }
    "org-policy-changes" = {
      display_name = "Org Policy Changes"
      description  = "Organization policy create, update, or delete events."
      alert_title  = "Organization policy changed"
      filter       = "protoPayload.methodName:(\"SetOrgPolicy\" OR \"ClearOrgPolicy\" OR \"CreatePolicy\" OR \"UpdatePolicy\" OR \"DeletePolicy\") AND resource.type=\"organization\""
    }
    "project-lifecycle-changes" = {
      display_name = "Project Lifecycle Changes"
      description  = "Project creation, deletion, or restore events."
      alert_title  = "Project created or deleted"
      filter       = "protoPayload.methodName:(\"CreateProject\" OR \"DeleteProject\" OR \"UndeleteProject\")"
    }
    "custom-role-changes" = {
      display_name = "Custom Role Changes"
      description  = "Custom IAM role create, update, or delete events."
      alert_title  = "Custom IAM role changed"
      filter       = "protoPayload.methodName:(\"google.iam.admin.v1.CreateRole\" OR \"google.iam.admin.v1.UpdateRole\" OR \"google.iam.admin.v1.DeleteRole\")"
    }
    "sa-key-created" = {
      display_name = "SA Key Created"
      description  = "Service account key creation events — should be zero given the SA key org policy."
      alert_title  = "Service account key created"
      filter       = "protoPayload.methodName=\"google.iam.admin.v1.CreateServiceAccountKey\""
    }
    "vpc-firewall-changes" = {
      display_name = "VPC Firewall Changes"
      description  = "VPC firewall rule insert, update, patch, or delete events."
      alert_title  = "VPC firewall rule changed"
      filter       = "protoPayload.methodName:(\"v1.compute.firewalls.insert\" OR \"v1.compute.firewalls.update\" OR \"v1.compute.firewalls.patch\" OR \"v1.compute.firewalls.delete\")"
    }
    "vpc-route-changes" = {
      display_name = "VPC Route Changes"
      description  = "VPC route insert or delete events."
      alert_title  = "VPC route changed"
      filter       = "protoPayload.methodName:(\"v1.compute.routes.insert\" OR \"v1.compute.routes.delete\")"
    }
    "kms-key-operations" = {
      display_name = "KMS Key Operations"
      description  = "KMS crypto key version destroy or disable events."
      alert_title  = "KMS key version disabled or destroyed"
      filter       = "protoPayload.methodName:(\"DestroyCryptoKeyVersion\" OR \"UpdateCryptoKeyVersion\") AND protoPayload.request.state:(\"DESTROY_SCHEDULED\" OR \"DISABLED\")"
    }
    "audit-log-sink-changes" = {
      display_name = "Audit Log Sink Changes"
      description  = "Cloud Logging sink create, update, or delete events — tampering with audit pipeline."
      alert_title  = "Audit log sink created, updated, or deleted"
      filter       = "protoPayload.methodName:(\"google.logging.v2.ConfigServiceV2.CreateSink\" OR \"google.logging.v2.ConfigServiceV2.UpdateSink\" OR \"google.logging.v2.ConfigServiceV2.DeleteSink\")"
    }
    "storage-iam-changes" = {
      display_name = "Storage IAM Changes"
      description  = "GCS bucket IAM policy change events."
      alert_title  = "GCS bucket IAM policy changed"
      filter       = "protoPayload.methodName=\"storage.setIamPermissions\" OR (protoPayload.serviceName=\"storage.googleapis.com\" AND protoPayload.methodName=\"storage.buckets.setIamPolicy\")"
    }
  }
}

# ─────────────────────────────────────────── notification channel

resource "google_monitoring_notification_channel" "security_email" {
  count        = var.monitoring_notification_email != "" ? 1 : 0
  project      = local.logging_project
  display_name = "Security Alerts"
  type         = "email"
  labels       = { email_address = var.monitoring_notification_email }
}

# ───────────────────────────── log-based metrics (one per security_metrics entry)

resource "google_logging_metric" "security" {
  for_each    = local.security_metrics
  project     = local.logging_project
  name        = "security/${each.key}"
  description = each.value.description
  filter      = each.value.filter
  bucket_name = local.audit_bucket_path

  metric_descriptor {
    metric_kind  = "DELTA"
    value_type   = "INT64"
    display_name = each.value.display_name
  }

  depends_on = [module.audit_log_bucket]
}

# ───────────────────────────── alert policies (one per security_metrics entry)

resource "google_monitoring_alert_policy" "security" {
  for_each              = local.security_metrics
  project               = local.logging_project
  display_name          = "[Security] ${each.value.alert_title}"
  combiner              = local.alert_combiner
  notification_channels = local.notification_channels

  conditions {
    display_name = "${each.value.display_name} detected"
    condition_threshold {
      filter          = "resource.type=\"global\" AND metric.type=\"logging.googleapis.com/user/${google_logging_metric.security[each.key].name}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = local.alert_duration
      aggregations {
        alignment_period   = local.alignment_period
        per_series_aligner = "ALIGN_COUNT"
      }
    }
  }

  alert_strategy {
    auto_close = "86400s"
  }
}
