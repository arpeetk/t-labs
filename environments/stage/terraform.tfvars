project_id                 = "t-labs-stage"
environment                = "stage"
region                     = "us-east4"
management_project_id      = "t-labs-management"
artifact_registry_location = "us-central1"
artifact_registry_name     = "t-labs"

# GKE — medium nodes, moderate autoscale ceiling
gke_machine_type = "e2-standard-4"
gke_min_nodes    = 1
gke_max_nodes    = 5

# Cloud SQL — medium tier for stage load testing
cloudsql_tier = "db-n1-standard-2"

master_authorized_networks = [
  {
    cidr_block   = "0.0.0.0/0"
    display_name = "all"
  }
]
