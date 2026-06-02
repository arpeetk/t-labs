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

  # Manage node pools separately; GKE requires initial_node_count=1 but removes it immediately.
  remove_default_node_pool = true
  initial_node_count       = 1

  # node_config here applies only to the transient default node pool created above.
  # It must be present: compute.requireShieldedVm org policy fires at pool creation time,
  # before remove_default_node_pool can delete it, causing cluster creation to fail on fresh apply.
  # WARNING: node_config is ForceNew in the Google provider — never change these values on an
  # existing cluster, only set them to match the values already in state.
  node_config {
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
    # Tags must match what the GKE API wrote to state on creation.
    # The default pool is deleted immediately, but its node_config is immutable once
    # the pool is gone — the GKE API rejects any update with "default-pool not found".
    tags = ["gke-node", "${var.name}-node"]
  }

  deletion_protection = var.deletion_protection

  network    = var.vpc_id
  subnetwork = var.private_gke_subnet_id

  # VPC-native cluster — required for private Cloud SQL access and PSC
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Nodes always have private IPs. The master endpoint is public for dev/stage
  # (gated by master_authorized_networks) and private for prod
  # (enable_private_endpoint = true → only reachable from inside the VPC).
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_cidr

    dynamic "master_global_access_config" {
      for_each = var.enable_private_endpoint ? [1] : []
      content {
        enabled = var.master_global_access_enabled
      }
    }
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

  # CMEK for application-layer secrets in etcd. When key_name is null, the
  # block is omitted and Google-managed keys protect Secrets at rest.
  dynamic "database_encryption" {
    for_each = var.database_encryption_key_name == null ? [] : [1]
    content {
      state    = "ENCRYPTED"
      key_name = var.database_encryption_key_name
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
    # NodeLocal DNSCache — large QPS reduction on internal DNS, no app changes.
    dns_cache_config {
      enabled = true
    }
    # Required for PVCs backed by pd-ssd / pd-standard / pd-balanced.
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
  }

  # Capture the control-plane audit trail: APISERVER + SCHEDULER + CONTROLLER_MANAGER
  # are how you forensically answer "who deleted this Deployment?".
  logging_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "WORKLOADS",
      "APISERVER",
      "SCHEDULER",
      "CONTROLLER_MANAGER",
    ]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = true
    }
  }

  maintenance_policy {
    recurring_window {
      start_time = "2024-01-01T03:00:00Z"
      end_time   = "2024-01-01T07:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
    }
  }

  # Defence-in-depth on the master endpoint and a hint to future readers
  # that the precondition is intentional, not a leftover.
  lifecycle {
    precondition {
      condition     = var.enable_private_endpoint || length(var.master_authorized_networks) > 0
      error_message = "When enable_private_endpoint = false, master_authorized_networks must list at least one CIDR. Public master + unrestricted auth networks is rejected."
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
