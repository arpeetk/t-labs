locals {
  env_projects = {
    dev   = google_project.dev.project_id
    stage = google_project.stage.project_id
    prod  = google_project.prod.project_id
  }

  env_apis = [
    "compute.googleapis.com",
    "container.googleapis.com",
    "sqladmin.googleapis.com",
    "servicenetworking.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "artifactregistry.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    # KMS underpins CMEK for GKE etcd application-layer secrets and any
    # future customer-managed encryption on Cloud SQL or GCS.
    "cloudkms.googleapis.com",
  ]
}

# ── Folder structure ────────────────────────────────────────────────────────

resource "google_folder" "shared_services" {
  display_name = "shared-services"
  parent       = "organizations/${var.org_id}"
}

resource "google_folder" "dev" {
  display_name = "dev"
  parent       = "organizations/${var.org_id}"
}

resource "google_folder" "stage" {
  display_name = "stage"
  parent       = "organizations/${var.org_id}"
}

resource "google_folder" "prod" {
  display_name = "prod"
  parent       = "organizations/${var.org_id}"
}

# ── Projects ────────────────────────────────────────────────────────────────

resource "google_project" "shared" {
  name                = "${var.project_prefix}-shared"
  project_id          = "${var.project_prefix}-shared"
  folder_id           = google_folder.shared_services.folder_id
  billing_account     = var.billing_account_id
  auto_create_network = false
}

resource "google_project" "dev" {
  name                = "${var.project_prefix}-dev"
  project_id          = "${var.project_prefix}-dev${var.env_project_suffix}"
  folder_id           = google_folder.dev.folder_id
  billing_account     = var.billing_account_id
  auto_create_network = false
}

resource "google_project" "stage" {
  name                = "${var.project_prefix}-stage"
  project_id          = "${var.project_prefix}-stage${var.env_project_suffix}"
  folder_id           = google_folder.stage.folder_id
  billing_account     = var.billing_account_id
  auto_create_network = false
}

resource "google_project" "prod" {
  name                = "${var.project_prefix}-prod"
  project_id          = "${var.project_prefix}-prod${var.env_project_suffix}"
  folder_id           = google_folder.prod.folder_id
  billing_account     = var.billing_account_id
  auto_create_network = false
}

# ── API enablement ──────────────────────────────────────────────────────────

resource "google_project_service" "shared_apis" {
  for_each = toset([
    "cloudresourcemanager.googleapis.com",
    "storage.googleapis.com",
    "artifactregistry.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "orgpolicy.googleapis.com",
    "sts.googleapis.com",
    # The Terraform SA lives in this project; GCP routes quota/billing for
    # every API call through the SA's home project, so all APIs the SA
    # touches across env projects must also be enabled here.
    "compute.googleapis.com",
    "container.googleapis.com",
    "sqladmin.googleapis.com",
    "servicenetworking.googleapis.com",
    "secretmanager.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
  ])

  project                    = google_project.shared.project_id
  service                    = each.value
  disable_dependent_services = false
  disable_on_destroy         = false
}

resource "google_project_service" "env_apis" {
  for_each = {
    for pair in setproduct(keys(local.env_projects), local.env_apis) :
    "${pair[0]}-${pair[1]}" => {
      project = local.env_projects[pair[0]]
      api     = pair[1]
    }
  }

  project                    = each.value.project
  service                    = each.value.api
  disable_dependent_services = false
  disable_on_destroy         = false
}
