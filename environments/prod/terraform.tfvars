project_id                 = "t-labs-prod-2"
environment                = "prod"
region                     = "us-west1"
shared_project_id          = "t-labs-shared"
artifact_registry_location = "us-central1"
artifact_registry_name     = "t-labs"

# GKE — larger nodes, high autoscale ceiling
gke_machine_type = "e2-standard-8"
gke_min_nodes    = 2
gke_max_nodes    = 10

# Cloud SQL — production-grade tier
cloudsql_tier = "db-custom-4-15360"

# Prod uses a fully private GKE endpoint (enable_private_endpoint = true in main.tf).
# Operators reach the API server through a bastion / Cloud Shell that sits inside
# the VPC — never from the public internet. This list is the private allowlist;
# leave it empty to allow all in-VPC clients, or restrict to specific bastion
# subnets if you want defence in depth.
master_authorized_networks = []

# Prod retains a month of backups and 14 days of PITR.
backup_retention_days          = 30
transaction_log_retention_days = 14

# Deny Cloud SQL maintenance for the launch window. Update or null out as
# product cycles change.
deny_maintenance_period = {
  start_date = "2026-11-15"
  end_date   = "2027-01-05"
  time       = "00:00:00"
}
