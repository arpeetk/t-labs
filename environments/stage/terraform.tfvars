project_id                 = "t-labs-stage-2"
environment                = "stage"
region                     = "us-east4"
shared_project_id          = "t-labs-shared"
artifact_registry_location = "us-central1"
artifact_registry_name     = "t-labs"

# GKE — medium nodes, moderate autoscale ceiling
gke_machine_type = "e2-standard-4"
gke_min_nodes    = 1
gke_max_nodes    = 5

# Cloud SQL — medium tier for stage load testing
cloudsql_tier = "db-custom-2-7680"

# Stage is the proving ground for the prod topology: master endpoint is public,
# but only the VPN egress CIDR is allowed in. Replace the placeholder with the
# real VPN CIDR before applying. Module precondition rejects an empty list when
# enable_private_endpoint = false.
master_authorized_networks = [
  {
    cidr_block   = "203.0.113.0/24"
    display_name = "vpn-placeholder-replace-me"
  }
]

# Stage holds longer backups than dev so we can rehearse PITR procedures.
backup_retention_days          = 14
transaction_log_retention_days = 7
