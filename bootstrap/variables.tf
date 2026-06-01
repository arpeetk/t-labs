variable "org_id" {
  description = "GCP Organization ID (run: gcloud organizations list)"
  type        = string
}

variable "billing_account_id" {
  description = "GCP Billing Account ID (run: gcloud billing accounts list)"
  type        = string
}

variable "project_prefix" {
  description = "Prefix for all project IDs and resource names"
  type        = string
  default     = "t-labs"
}

variable "region" {
  description = "Default GCP region for management project resources"
  type        = string
  default     = "us-central1"
}

variable "developer_group_email" {
  description = "Google Workspace group email for developers (e.g. developers@t-labs.com) — create in admin.google.com"
  type        = string
}

variable "infra_admin_group_email" {
  description = "Google Workspace group email for infra admins (e.g. infra-admins@t-labs.com) — create in admin.google.com"
  type        = string
}
