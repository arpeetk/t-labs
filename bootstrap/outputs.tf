output "shared_project_id" {
  value = google_project.shared.project_id
}

output "dev_project_id" {
  value = google_project.dev.project_id
}

output "stage_project_id" {
  value = google_project.stage.project_id
}

output "prod_project_id" {
  value = google_project.prod.project_id
}

output "state_bucket_bootstrap" {
  value = google_storage_bucket.state["bootstrap"].name
}

output "state_bucket_dev" {
  value = google_storage_bucket.state["dev"].name
}

output "state_bucket_stage" {
  value = google_storage_bucket.state["stage"].name
}

output "state_bucket_prod" {
  value = google_storage_bucket.state["prod"].name
}

output "artifact_registry_location" {
  value = google_artifact_registry_repository.main.location
}

output "artifact_registry_name" {
  value = google_artifact_registry_repository.main.repository_id
}

