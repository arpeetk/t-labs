output "cluster_name" {
  value = google_container_cluster.main.name
}

output "cluster_endpoint" {
  value     = google_container_cluster.main.endpoint
  sensitive = true
}

output "cluster_ca_certificate" {
  value     = google_container_cluster.main.master_auth[0].cluster_ca_certificate
  sensitive = true
}

output "node_service_account_email" {
  description = "Grant this SA roles/artifactregistry.reader on the shared registry and roles/cloudsql.client on the env project"
  value       = google_service_account.gke_nodes.email
}

output "workload_identity_pool" {
  description = "Use this as the pool ID when binding Kubernetes ServiceAccounts to Google Service Accounts"
  value       = "${var.project_id}.svc.id.goog"
}
