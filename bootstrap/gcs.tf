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

  depends_on = [google_project_service.shared_apis]
}

# Terraform SA gets full admin on all state buckets (storage.admin includes storage.buckets.get)
resource "google_storage_bucket_iam_member" "terraform_state_admin" {
  for_each = google_storage_bucket.state

  bucket = each.value.name
  role   = "roles/storage.admin"
  member = "serviceAccount:${google_service_account.terraform.email}"
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
