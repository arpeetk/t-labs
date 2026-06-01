project_id                 = "t-labs-dev"
environment                = "dev"
region                     = "us-central1"
management_project_id      = "t-labs-management"
artifact_registry_location = "us-central1"
artifact_registry_name     = "t-labs"

# GKE — small nodes, low autoscale ceiling
gke_machine_type = "e2-standard-2"
gke_min_nodes    = 1
gke_max_nodes    = 3

# Cloud SQL — smallest tier sufficient for dev workloads
cloudsql_tier = "db-g1-small"

# Restrict to your office/VPN CIDRs in practice
master_authorized_networks = [
  {
    cidr_block   = "0.0.0.0/0"
    display_name = "all"
  }
]
