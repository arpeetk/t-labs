terraform {
  required_version = ">= 1.8"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.35"
    }
  }
}

# ── VPC ─────────────────────────────────────────────────────────────────────

resource "google_compute_network" "vpc" {
  name                    = "${var.name}-vpc"
  project                 = var.project_id
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

# ── Subnets ──────────────────────────────────────────────────────────────────

resource "google_compute_subnetwork" "public" {
  name                     = "${var.name}-public"
  project                  = var.project_id
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = var.public_subnet_cidr
  private_ip_google_access = false
}

resource "google_compute_subnetwork" "private_gke" {
  name                     = "${var.name}-private-gke"
  project                  = var.project_id
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = var.private_gke_subnet_cidr
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }
}

resource "google_compute_subnetwork" "private_data" {
  name                     = "${var.name}-private-data"
  project                  = var.project_id
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = var.private_data_subnet_cidr
  private_ip_google_access = true
}

# ── Cloud NAT ────────────────────────────────────────────────────────────────

resource "google_compute_router" "router" {
  name    = "${var.name}-router"
  project = var.project_id
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.name}-nat"
  project                            = var.project_id
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.private_gke.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  subnetwork {
    name                    = google_compute_subnetwork.private_data.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}

# ── Private Services Access (required for Cloud SQL private IP) ───────────────

resource "google_compute_global_address" "private_services_range" {
  name          = "${var.name}-private-services"
  project       = var.project_id
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 24
  network       = google_compute_network.vpc.id
}

resource "google_service_networking_connection" "private_services" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_services_range.name]
  deletion_policy         = "ABANDON"
}

# ── Firewall rules ────────────────────────────────────────────────────────────
#
# Default-deny ingress is implicit on every GCP VPC. The rules below explicitly
# allow the minimum we need:
#   - allow_internal_gke   : pod-to-pod, node-to-node, node-to-pod, pod-to-node
#                            on TCP/UDP/ICMP. Required for Dataplane V2 to do
#                            its job. Network policy (Cilium) is the next layer
#                            in for fine-grained pod isolation.
#   - allow_health_checks  : GCP LB health probers (well-known ranges).
#   - allow_iap_ssh        : IAP TCP forwarding for diagnostic SSH to nodes.
#
# The data subnet has no resources today (Cloud SQL is in the peered Google
# VPC reached via PSA). Anything added there should declare its own
# tightly-scoped rule (e.g. allow TCP 5432 from var.pods_cidr only). The
# previous catch-all "allow_internal" included the data range as both source
# and destination, which would have allowed unintended lateral movement once
# the subnet is populated.

resource "google_compute_firewall" "allow_internal_gke" {
  name    = "${var.name}-allow-internal-gke"
  project = var.project_id
  network = google_compute_network.vpc.id

  allow { protocol = "tcp" }
  allow { protocol = "udp" }
  allow { protocol = "icmp" }

  source_ranges = [
    var.private_gke_subnet_cidr,
    var.pods_cidr,
  ]
}

# Required for GCP load balancer health checks
resource "google_compute_firewall" "allow_health_checks" {
  name    = "${var.name}-allow-health-checks"
  project = var.project_id
  network = google_compute_network.vpc.id

  allow { protocol = "tcp" }

  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
}

# SSH via Identity-Aware Proxy only — no direct internet SSH
resource "google_compute_firewall" "allow_iap_ssh" {
  name    = "${var.name}-allow-iap-ssh"
  project = var.project_id
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
}
