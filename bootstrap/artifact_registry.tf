# Centralized Docker registry in the shared project.
# All environments pull from here — images are built once and promoted.

resource "google_artifact_registry_repository" "main" {
  project       = google_project.shared.project_id
  location      = var.region
  repository_id = var.project_prefix
  format        = "DOCKER"
  description   = "Central Docker repository shared across all environments"

  # Retention so the registry stays small and old vulnerable images get culled.
  # Order matters: keep-latest is evaluated alongside delete rules; tagged
  # images are protected for 90 days regardless of count, and untagged images
  # disappear after 7 days.
  cleanup_policies {
    id     = "keep-recent-tags"
    action = "KEEP"
    most_recent_versions {
      package_name_prefixes = []
      keep_count            = 30
    }
  }

  cleanup_policies {
    id     = "delete-untagged-quickly"
    action = "DELETE"
    condition {
      tag_state  = "UNTAGGED"
      older_than = "604800s" # 7 days
    }
  }

  cleanup_policies {
    id     = "delete-old-tagged"
    action = "DELETE"
    condition {
      tag_state  = "TAGGED"
      older_than = "7776000s" # 90 days
    }
  }

  depends_on = [google_project_service.shared_apis]
}

# ── CI image-pusher service account ──────────────────────────────────────────
# Scoped to artifactregistry.writer on this repo only — not org-level owner.
# Used by cd-images.yml; deliberately separate from the Terraform SA so a
# compromised Docker build cannot escalate to infrastructure access.

resource "google_service_account" "ci_image_pusher" {
  account_id   = "ci-image-pusher"
  display_name = "CI Image Pusher"
  project      = google_project.shared.project_id

  depends_on = [google_project_service.shared_apis]
}

resource "google_artifact_registry_repository_iam_member" "ci_image_pusher_writer" {
  project    = google_project.shared.project_id
  location   = google_artifact_registry_repository.main.location
  repository = google_artifact_registry_repository.main.repository_id
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.ci_image_pusher.email}"
}
