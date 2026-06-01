project_id                 = "t-labs-prod"
environment                = "prod"
region                     = "us-west1"
management_project_id      = "t-labs-management"
artifact_registry_location = "us-central1"
artifact_registry_name     = "t-labs"

# GKE — larger nodes, high autoscale ceiling
gke_machine_type = "e2-standard-8"
gke_min_nodes    = 2
gke_max_nodes    = 10

# Cloud SQL — production-grade tier
cloudsql_tier = "db-n1-standard-4"

# Restrict GKE API server access to your VPN or office egress IP.
# Override at apply time: terraform apply -var='master_authorized_networks=[{cidr_block="x.x.x.x/32",display_name="vpn"}]'
master_authorized_networks = []
