output "instance_name" {
  value = google_sql_database_instance.main.name
}

output "instance_connection_name" {
  description = "Used to configure Cloud SQL Auth Proxy (format: project:region:instance)"
  value       = google_sql_database_instance.main.connection_name
}

output "private_ip" {
  value = google_sql_database_instance.main.private_ip_address
}

output "database_name" {
  value = google_sql_database.main.name
}

output "db_user" {
  value = google_sql_user.app.name
}

output "db_password_secret_id" {
  description = "Secret Manager secret ID — grant roles/secretmanager.secretAccessor to app Workload Identity SAs"
  value       = google_secret_manager_secret.db_password.secret_id
}

output "db_connection_secret_id" {
  description = "Secret Manager secret ID — JSON blob with host/port/db_name/db_user. Apps wire DB_HOST/DB_NAME from this instead of hardcoding."
  value       = google_secret_manager_secret.db_connection.secret_id
}
