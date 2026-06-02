locals {
  prefix = "t-labs-${var.environment}"
  node_zones = [
    "${var.region}-a",
    "${var.region}-b",
    "${var.region}-c",
  ]
}

# KMS for GKE etcd CMEK (see environments/dev/main.tf for the design rationale).
data "google_project" "current" {
  project_id = var.project_id
}

resource "google_kms_key_ring" "gke" {
  name     = "${local.prefix}-gke"
  location = var.region
  project  = var.project_id
}

resource "google_kms_crypto_key" "gke_etcd" {
  name            = "etcd"
  key_ring        = google_kms_key_ring.gke.id
  purpose         = "ENCRYPT_DECRYPT"
  rotation_period = "7776000s"

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_kms_crypto_key_iam_member" "gke_etcd_robot" {
  crypto_key_id = google_kms_crypto_key.gke_etcd.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.current.number}@container-engine-robot.iam.gserviceaccount.com"
}

module "vpc" {
  source = "../../modules/vpc"

  name                     = local.prefix
  project_id               = var.project_id
  region                   = var.region
  public_subnet_cidr       = "10.10.0.0/20"
  private_gke_subnet_cidr  = "10.10.16.0/20"
  private_data_subnet_cidr = "10.10.32.0/20"
  pods_cidr                = "10.11.0.0/16"
  services_cidr            = "10.12.0.0/20"
}

module "gke" {
  source = "../../modules/gke"

  name                  = local.prefix
  project_id            = var.project_id
  region                = var.region
  environment           = var.environment
  vpc_id                = module.vpc.vpc_id
  private_gke_subnet_id = module.vpc.private_gke_subnet_id

  master_cidr                  = "172.16.1.0/28"
  master_authorized_networks   = var.master_authorized_networks
  enable_private_endpoint      = false
  node_zones                   = local.node_zones
  machine_type                 = var.gke_machine_type
  min_node_count               = var.gke_min_nodes
  max_node_count               = var.gke_max_nodes
  deletion_protection          = false
  database_encryption_key_name = google_kms_crypto_key.gke_etcd.id

  depends_on = [google_kms_crypto_key_iam_member.gke_etcd_robot]
}

module "cloudsql" {
  source = "../../modules/cloudsql"

  name                           = local.prefix
  project_id                     = var.project_id
  region                         = var.region
  vpc_id                         = module.vpc.vpc_id
  database_name                  = "appdb"
  db_user                        = "appuser"
  tier                           = var.cloudsql_tier
  deletion_protection            = false
  backup_retention_days          = var.backup_retention_days
  transaction_log_retention_days = var.transaction_log_retention_days

  depends_on = [module.vpc]
}

resource "google_artifact_registry_repository_iam_member" "gke_nodes_ar_reader" {
  project    = var.shared_project_id
  location   = var.artifact_registry_location
  repository = var.artifact_registry_name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${module.gke.node_service_account_email}"
}

resource "google_project_iam_member" "gke_nodes_cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${module.gke.node_service_account_email}"
}
