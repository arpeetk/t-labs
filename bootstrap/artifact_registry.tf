# Centralized Docker registry in the shared project.
# All environments pull from here — images are built once and promoted.

resource "google_artifact_registry_repository" "main" {
  project       = google_project.shared.project_id
  location      = var.region
  repository_id = var.project_prefix
  format        = "DOCKER"
  description   = "Central Docker repository shared across all environments"

  depends_on = [google_project_service.shared_apis]
}
