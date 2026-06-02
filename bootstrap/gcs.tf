locals {
  state_buckets = {
    bootstrap = "${var.project_prefix}-state-bootstrap"
    dev       = "${var.project_prefix}-state-dev"
    stage     = "${var.project_prefix}-state-stage"
    prod      = "${var.project_prefix}-state-prod"
  }
}

resource "google_storage_bucket" "state" {
  for_each = local.state_buckets

  name                        = each.value
  project                     = google_project.shared.project_id
  location                    = var.region
  force_destroy               = false
  uniform_bucket_level_access = true

  # Blocks any future IAM binding that would make the bucket world-readable.
  # Mutable, so safe to enable on existing buckets.
  public_access_prevention = "enforced"

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 10
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  # Multi-region durability is documented as future work — moving from
  # us-central1 to "US" requires destroying and recreating each bucket
  # and migrating live state, which we punt to a controlled migration
  # window (README → Future Work).
  #
  # State-bucket access logging:
  # The legacy "GCS access logs" feature requires granting writer to
  # cloud-storage-analytics@google.com, which the org policy
  # iam.allowedPolicyMemberDomains rejects. The same data is available via
  # Cloud Audit Logs (ADMIN_READ is captured for storage by the org-level
  # google_organization_iam_audit_config) and is queryable in Log Explorer
  # with: resource.type="gcs_bucket" AND protoPayload.methodName=~"storage".
  # README → Future Work tracks adding ADMIN_READ to the org-level audit
  # config to capture read events too.
  depends_on = [google_project_service.shared_apis]
}

# Developers can read dev and stage state for debugging — no prod access.
# Use string keys to avoid dependency on google_storage_bucket (deferred unknown on first apply).
resource "google_storage_bucket_iam_member" "developer_state_reader" {
  for_each = {
    dev   = "${var.project_prefix}-state-dev"
    stage = "${var.project_prefix}-state-stage"
  }

  bucket = each.value
  role   = "roles/storage.legacyBucketReader"
  member = "group:${var.developer_group_email}"

  depends_on = [google_storage_bucket.state]
}

resource "google_storage_bucket_iam_member" "developer_state_object_viewer" {
  for_each = {
    dev   = "${var.project_prefix}-state-dev"
    stage = "${var.project_prefix}-state-stage"
  }

  bucket = each.value
  role   = "roles/storage.objectViewer"
  member = "group:${var.developer_group_email}"

  depends_on = [google_storage_bucket.state]
}

# Infra admins can read dev, stage, and prod state — not bootstrap (no operational need).
resource "google_storage_bucket_iam_member" "infra_admin_state_reader" {
  for_each = {
    dev   = "${var.project_prefix}-state-dev"
    stage = "${var.project_prefix}-state-stage"
    prod  = "${var.project_prefix}-state-prod"
  }

  bucket = each.value
  role   = "roles/storage.legacyBucketReader"
  member = "group:${var.infra_admin_group_email}"

  depends_on = [google_storage_bucket.state]
}

resource "google_storage_bucket_iam_member" "infra_admin_state_object_viewer" {
  for_each = {
    dev   = "${var.project_prefix}-state-dev"
    stage = "${var.project_prefix}-state-stage"
    prod  = "${var.project_prefix}-state-prod"
  }

  bucket = each.value
  role   = "roles/storage.objectViewer"
  member = "group:${var.infra_admin_group_email}"

  depends_on = [google_storage_bucket.state]
}
