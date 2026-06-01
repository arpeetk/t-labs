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
  description = "CIDRs allowed to reach the GKE API server — restrict to VPN/office IPs in production"
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}
