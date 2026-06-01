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
  description = "Cloud SQL machine tier for ENTERPRISE edition. Must use db-custom-<cpu>-<mb> format."
  type        = string

  validation {
    condition     = can(regex("^db-custom-[0-9]+-[0-9]+$", var.tier))
    error_message = "tier must be in db-custom-<cpu>-<memorymb> format (e.g., db-custom-1-3840). Shared-core and db-n1 tiers are not supported by ENTERPRISE edition."
  }
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
