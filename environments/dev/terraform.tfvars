project_id                 = "t-labs-dev-2"
environment                = "dev"
region                     = "us-central1"
shared_project_id          = "t-labs-shared"
artifact_registry_location = "us-central1"
artifact_registry_name     = "t-labs"

# GKE — small nodes, low autoscale ceiling
gke_machine_type = "e2-standard-2"
gke_min_nodes    = 1
gke_max_nodes    = 3

# Cloud SQL — smallest tier sufficient for dev workloads
cloudsql_tier = "db-custom-1-3840"

# Restricted to the maintainer's egress IP for the demo. To use this repo:
#   - Run `curl -s https://api.ipify.org` to find your egress IP, or
#   - Override on the CLI:
#       terraform apply \
#         -var='master_authorized_networks=[{cidr_block="x.x.x.x/32",display_name="me"}]'
# The module rejects 0.0.0.0/0 via a precondition, so accidental wide-open
# values are caught at plan time.
master_authorized_networks = [
  {
    cidr_block   = "76.102.243.121/32"
    display_name = "maintainer-egress"
  }
]
