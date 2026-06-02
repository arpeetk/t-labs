variable "project_id" {
  description = "GCP project ID for this environment"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Environment name (dev, stage, prod)"
  type        = string
}

variable "shared_project_id" {
  description = "Project ID of the management project hosting Artifact Registry"
  type        = string
}

variable "artifact_registry_location" {
  description = "Location of the shared Artifact Registry repository"
  type        = string
}

variable "artifact_registry_name" {
  description = "Repository ID of the shared Artifact Registry"
  type        = string
}

variable "gke_machine_type" {
  description = "GCE machine type for GKE node pool"
  type        = string
}

variable "gke_min_nodes" {
  description = "Minimum nodes per zone in the node pool"
  type        = number
}

variable "gke_max_nodes" {
  description = "Maximum nodes per zone in the node pool"
  type        = number
}

variable "cloudsql_tier" {
  description = "Cloud SQL machine tier"
  type        = string
}

variable "master_authorized_networks" {
  description = "CIDRs allowed to reach the GKE API server. Prod sets enable_private_endpoint=true and reaches the master via a bastion / Cloud Shell inside the VPC; this list is the private-endpoint allowlist."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

variable "backup_retention_days" {
  description = "Daily Cloud SQL backups to keep."
  type        = number
  default     = 30
}

variable "transaction_log_retention_days" {
  description = "Cloud SQL PITR window in days."
  type        = number
  default     = 14
}

variable "deny_maintenance_period" {
  description = "Window during which Google may not perform routine Cloud SQL maintenance (peak season, launches)."
  type = object({
    start_date = string
    end_date   = string
    time       = string
  })
  default = null
}
