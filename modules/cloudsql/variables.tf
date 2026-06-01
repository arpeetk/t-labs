variable "name" {
  description = "Name prefix for all resources (e.g., t-labs-dev)"
  type        = string
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region — standby replica will be placed in a different zone in this region"
  type        = string
}

variable "vpc_id" {
  description = "VPC network ID — Cloud SQL binds to this VPC via Private Services Access"
  type        = string
}

variable "database_name" {
  description = "Name of the application database to create"
  type        = string
}

variable "db_user" {
  description = "Database username for the application"
  type        = string
  default     = "appuser"
}

variable "tier" {
  description = "Cloud SQL machine tier for ENTERPRISE edition (e.g., db-n1-standard-1, db-n1-standard-2, db-n1-standard-4)"
  type        = string
}

variable "max_connections" {
  description = "PostgreSQL max_connections setting"
  type        = string
  default     = "100"
}

variable "deletion_protection" {
  description = "Prevent accidental instance deletion"
  type        = bool
  default     = true
}
