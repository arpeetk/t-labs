variable "name" {
  description = "Name prefix for all resources (e.g., t-labs-dev)"
  type        = string
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "public_subnet_cidr" {
  description = "CIDR for the public subnet"
  type        = string
}

variable "private_gke_subnet_cidr" {
  description = "CIDR for the private GKE node subnet"
  type        = string
}

variable "private_data_subnet_cidr" {
  description = "CIDR for the private data subnet (Cloud SQL, etc.)"
  type        = string
}

variable "pods_cidr" {
  description = "Secondary CIDR range for GKE pod IPs"
  type        = string
}

variable "services_cidr" {
  description = "Secondary CIDR range for GKE service IPs"
  type        = string
}
