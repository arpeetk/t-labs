output "vpc_id" {
  value = google_compute_network.vpc.id
}

output "vpc_name" {
  value = google_compute_network.vpc.name
}

output "public_subnet_id" {
  value = google_compute_subnetwork.public.id
}

output "private_gke_subnet_id" {
  value = google_compute_subnetwork.private_gke.id
}

output "private_data_subnet_id" {
  value = google_compute_subnetwork.private_data.id
}

output "private_services_connection_id" {
  description = "Used as a depends_on anchor for Cloud SQL to ensure PSA peering is ready"
  value       = google_service_networking_connection.private_services.id
}
