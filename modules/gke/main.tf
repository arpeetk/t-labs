terraform {
  required_version = ">= 1.8"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

# ── Node service account ──────────────────────────────────────────────────────
# Minimal permissions for GKE nodes — Workload Identity handles per-app access.

resource "google_service_account" "gke_nodes" {
  account_id   = "${var.name}-gke-nodes"
  display_name = "GKE Node Service Account (${var.environment})"
  project      = var.project_id
}

resource "google_project_iam_member" "gke_node_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_node_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_node_monitoring_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# ── GKE cluster ───────────────────────────────────────────────────────────────
# Regional cluster — control plane and nodes distributed across all zones in the region.

resource "google_container_cluster" "main" {
  name     = "${var.name}-gke"
  project  = var.project_id
  location = var.region

  # Manage node pools separately; GKE requires initial_node_count=1 but removes it immediately
  remove_default_node_pool = true
  initial_node_count       = 1

  # Shielded VM required by compute.requireShieldedVm org policy — applies to initial default pool
  node_config {
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  deletion_protection = var.deletion_protection

  network    = var.vpc_id
  subnetwork = var.private_gke_subnet_id

  # VPC-native cluster — required for private Cloud SQL access and PSC
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Nodes have private IPs only; master endpoint is public but gated by authorized networks
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_cidr
  }

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Dataplane V2 — eBPF-based networking, built-in network policy enforcement
  datapath_provider = "ADVANCED_DATAPATH"

  release_channel {
    channel = "REGULAR"
  }

  addons_config {
    horizontal_pod_autoscaling {
      disabled = false
    }
    http_load_balancing {
      disabled = false
    }
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
  }

  maintenance_policy {
    recurring_window {
      start_time = "2024-01-01T03:00:00Z"
      end_time   = "2024-01-01T07:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
    }
  }
}

# ── Node pool ─────────────────────────────────────────────────────────────────

resource "google_container_node_pool" "main" {
  name     = "${var.name}-nodes"
  project  = var.project_id
  cluster  = google_container_cluster.main.name
  location = var.region

  node_locations = var.node_zones

  autoscaling {
    min_node_count = var.min_node_count
    max_node_count = var.max_node_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = var.machine_type
    disk_size_gb = var.disk_size_gb
    disk_type    = "pd-ssd"

    service_account = google_service_account.gke_nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    # Required for Workload Identity on nodes
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    tags = ["gke-node", "${var.name}-node"]

    labels = {
      env = var.environment
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ── Firewall: GKE master → nodes ──────────────────────────────────────────────
# Required for admission webhooks (port 8443) and kubelet (port 10250).

resource "google_compute_firewall" "gke_master_to_nodes" {
  name    = "${var.name}-gke-master-to-nodes"
  project = var.project_id
  network = var.vpc_id

  allow {
    protocol = "tcp"
    ports    = ["443", "8443", "10250"]
  }

  source_ranges = [var.master_cidr]
  target_tags   = ["gke-node"]
}
