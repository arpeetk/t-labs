output "vpc_id" {
  value = module.vpc.vpc_id
}

output "gke_cluster_name" {
  value = module.gke.cluster_name
}

output "gke_cluster_endpoint" {
  value     = module.gke.cluster_endpoint
  sensitive = true
}

output "gke_node_service_account" {
  value = module.gke.node_service_account_email
}

output "workload_identity_pool" {
  description = "Use when wiring Kubernetes ServiceAccounts to Google Service Accounts for app-level GCP access"
  value       = module.gke.workload_identity_pool
}

output "cloudsql_instance_connection_name" {
  description = "Set as the instance connection name in Cloud SQL Auth Proxy config"
  value       = module.cloudsql.instance_connection_name
}

output "cloudsql_private_ip" {
  value = module.cloudsql.private_ip
}

output "db_password_secret_id" {
  description = "Grant roles/secretmanager.secretAccessor to app Workload Identity SAs to read this"
  value       = module.cloudsql.db_password_secret_id
}

output "db_connection_secret_id" {
  description = "JSON-encoded Secret Manager entry: {host, port, db_name, db_user}."
  value       = module.cloudsql.db_connection_secret_id
}
