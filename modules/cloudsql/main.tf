terraform {
  required_version = ">= 1.8"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Cloud SQL instance names cannot be reused for 7 days after deletion — suffix avoids conflicts.
resource "random_id" "instance_suffix" {
  byte_length = 4
}

resource "random_password" "db_password" {
  length  = 32
  special = false
}

# Password rotation is deliberately manual today: bumping the `keepers` map below
# (e.g. set `rotation = timestamp()` and commit a date) forces a new random value,
# which is then written to a new Secret Manager version. Apps reading `latest`
# pick it up automatically. For automated rotation, swap to
# google_secret_manager_secret_rotation + a Cloud Function that updates the
# Cloud SQL user. Tracked in README → Future Work.

# ── Secret Manager ────────────────────────────────────────────────────────────

resource "google_secret_manager_secret" "db_password" {
  secret_id = "${var.name}-db-password"
  project   = var.project_id

  # auto replication is global and violates gcp.resourceLocations org policy
  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }

  # replication is ForceNew in the Google provider — create_before_destroy prevents
  # a destroy window where running pods can't read credentials during any future change.
  lifecycle {
    create_before_destroy = true
  }
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db_password.result
}

# ── Cloud SQL instance ────────────────────────────────────────────────────────
# availability_type = REGIONAL enables HA: primary in one zone, standby in another.
# Private IP only — access is via the PSA VPC peering established in the VPC module.

resource "google_sql_database_instance" "main" {
  name             = "${var.name}-postgres-${random_id.instance_suffix.hex}"
  project          = var.project_id
  database_version = "POSTGRES_16"
  region           = var.region

  deletion_protection = var.deletion_protection

  settings {
    tier              = var.tier
    edition           = "ENTERPRISE"
    availability_type = "REGIONAL"

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = "03:00"
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 7
      }
    }

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = var.vpc_id
      enable_private_path_for_google_cloud_services = true
    }

    database_flags {
      name  = "max_connections"
      value = var.max_connections
    }

    insights_config {
      query_insights_enabled  = true
      query_string_length     = 1024
      record_application_tags = true
    }

    maintenance_window {
      day          = 7
      hour         = 3
      update_track = "stable"
    }
  }
}

# ── Database and user ─────────────────────────────────────────────────────────

resource "google_sql_database" "main" {
  name     = var.database_name
  project  = var.project_id
  instance = google_sql_database_instance.main.name
}

resource "google_sql_user" "app" {
  name     = var.db_user
  project  = var.project_id
  instance = google_sql_database_instance.main.name
  password = random_password.db_password.result
}
