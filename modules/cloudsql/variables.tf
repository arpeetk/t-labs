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

variable "backup_retention_days" {
  description = "Number of daily backups to retain. Prod typically 30; dev/stage 7."
  type        = number
  default     = 7
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 365
    error_message = "backup_retention_days must be between 1 and 365."
  }
}

variable "transaction_log_retention_days" {
  description = "Number of days of PITR (write-ahead log) retention. Prod typically 14+; dev/stage 7."
  type        = number
  default     = 7
  validation {
    condition     = var.transaction_log_retention_days >= 1 && var.transaction_log_retention_days <= 35
    error_message = "transaction_log_retention_days must be between 1 and 35 (GCP limit)."
  }
}

variable "deny_maintenance_period" {
  description = "Optional deny window during which Google may not perform routine maintenance. Use ISO date+time. Set to null on dev/stage."
  type = object({
    start_date = string # YYYY-MM-DD
    end_date   = string # YYYY-MM-DD
    time       = string # HH:MM:SS
  })
  default = null
}
