variable "name" {
  description = "Name prefix for all resources (e.g., t-labs-dev)"
  type        = string
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region — the cluster will be regional (HA across all zones)"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, stage, prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC network ID"
  type        = string
}

variable "private_gke_subnet_id" {
  description = "Private GKE subnet ID"
  type        = string
}

variable "master_cidr" {
  description = "CIDR for GKE master nodes — must not overlap any VPC or pod CIDRs (e.g., 172.16.0.0/28)"
  type        = string
}

variable "master_authorized_networks" {
  description = "CIDRs allowed to reach the GKE API server endpoint"
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
}

variable "node_zones" {
  description = "Zones to distribute node pool VMs across (should be 3 zones for HA)"
  type        = list(string)
}

variable "machine_type" {
  description = "GCE machine type for node pool VMs"
  type        = string
}

variable "min_node_count" {
  description = "Minimum nodes per zone (cluster autoscaler lower bound)"
  type        = number
}

variable "max_node_count" {
  description = "Maximum nodes per zone (cluster autoscaler upper bound)"
  type        = number
}

variable "disk_size_gb" {
  description = "Boot disk size per node in GB"
  type        = number
  default     = 50
}

variable "deletion_protection" {
  description = "Prevent accidental cluster deletion"
  type        = bool
  default     = true
}
