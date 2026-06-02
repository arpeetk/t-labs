# ── Terraform service accounts ─────────────────────────────────────────────
#
# Goal: blast-radius isolation. There is one SA per environment + one
# read-only plan SA, none of which holds roles/owner.
#
#   terraform-dev/stage/prod : apply the matching env directory. Scoped admin
#                              roles on their own env project + their own
#                              state bucket only. WIF principal binding is
#                              tied to GitHub environment `dev`/`stage`/`prod`.
#   terraform-plan-ro   : runs the PR plan against dev. Viewer + state read
#                         only. WIF binding tied to pull_request events.

# ── Per-env Terraform SAs ───────────────────────────────────────────────────

locals {
  # Scoped admin roles, replacing roles/owner. Each role is the smallest one
  # that covers what the corresponding env-Terraform module touches.
  terraform_env_roles = [
    "roles/compute.networkAdmin",
    "roles/compute.securityAdmin",
    "roles/container.admin",
    "roles/cloudsql.admin",
    "roles/secretmanager.admin",
    "roles/iam.serviceAccountAdmin",
    "roles/resourcemanager.projectIamAdmin",
    "roles/servicenetworking.networksAdmin",
    "roles/cloudkms.admin",
    "roles/monitoring.editor",
    "roles/logging.configWriter",
    "roles/serviceusage.serviceUsageAdmin",
  ]
}

resource "google_service_account" "terraform_env" {
  for_each     = local.env_projects
  account_id   = "terraform-${each.key}"
  display_name = "Terraform — ${each.key} (scoped)"
  project      = google_project.shared.project_id
  depends_on   = [google_project_service.shared_apis]
}

resource "google_project_iam_member" "terraform_env_role" {
  for_each = {
    for pair in setproduct(keys(local.env_projects), local.terraform_env_roles) :
    "${pair[0]}-${replace(pair[1], "/", "_")}" => {
      env  = pair[0]
      role = pair[1]
    }
  }
  project = local.env_projects[each.value.env]
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.terraform_env[each.value.env].email}"
}

# Cross-project: env SAs bind the GKE node SA → AR reader on the shared repo.
# repoAdmin is the smallest role that grants both read and IAM-edit on a repo.
resource "google_artifact_registry_repository_iam_member" "terraform_env_ar_admin" {
  for_each   = google_service_account.terraform_env
  project    = google_project.shared.project_id
  location   = google_artifact_registry_repository.main.location
  repository = google_artifact_registry_repository.main.repository_id
  role       = "roles/artifactregistry.repoAdmin"
  member     = "serviceAccount:${each.value.email}"
}

# Cross-project IAM reads (e.g. getIamPolicy on AR repo in shared) go through
# the IAM v1 API which requires iam.policies.get, not the AR-specific permission.
# securityReviewer on the shared project satisfies this without data access.
resource "google_project_iam_member" "terraform_env_shared_iam_reviewer" {
  for_each = google_service_account.terraform_env
  project  = google_project.shared.project_id
  role     = "roles/iam.securityReviewer"
  member   = "serviceAccount:${each.value.email}"
}

# Each env SA writes only to its own state bucket.
resource "google_storage_bucket_iam_member" "terraform_env_state_admin" {
  for_each = google_service_account.terraform_env
  bucket   = google_storage_bucket.state[each.key].name
  role     = "roles/storage.objectAdmin"
  member   = "serviceAccount:${each.value.email}"
}

# ── Read-only SA for PR plan jobs ───────────────────────────────────────────
# Limits the blast radius of a malicious PR: even if it changes the workflow
# and exfiltrates the token, the worst it can do is list resources.

resource "google_service_account" "terraform_plan_ro" {
  account_id   = "terraform-plan-ro"
  display_name = "Terraform — read-only for PR plans"
  project      = google_project.shared.project_id
  depends_on   = [google_project_service.shared_apis]
}

resource "google_project_iam_member" "terraform_plan_viewer" {
  for_each = local.env_projects
  project  = each.value
  role     = "roles/viewer"
  member   = "serviceAccount:${google_service_account.terraform_plan_ro.email}"
}

resource "google_project_iam_member" "terraform_plan_iam_reviewer" {
  for_each = local.env_projects
  project  = each.value
  role     = "roles/iam.securityReviewer"
  member   = "serviceAccount:${google_service_account.terraform_plan_ro.email}"
}

resource "google_storage_bucket_iam_member" "terraform_plan_state_reader" {
  for_each = google_storage_bucket.state
  bucket   = each.value.name
  role     = "roles/storage.objectViewer"
  member   = "serviceAccount:${google_service_account.terraform_plan_ro.email}"
}

# The dev env plan reads cross-project IAM (Artifact Registry in t-labs-shared).
# securityReviewer on the shared project grants getIamPolicy without data access.
resource "google_project_iam_member" "terraform_plan_shared_iam_reviewer" {
  project = google_project.shared.project_id
  role    = "roles/iam.securityReviewer"
  member  = "serviceAccount:${google_service_account.terraform_plan_ro.email}"
}

# ── Developer role bindings ──────────────────────────────────────────────────
# Google Workspace group — add/remove users in admin.google.com, IAM updates automatically.
# Developers get viewer + GKE deploy on dev and stage only — no prod access.

resource "google_folder_iam_member" "developer_viewer_dev" {
  folder = google_folder.dev.folder_id
  role   = "roles/viewer"
  member = "group:${var.developer_group_email}"
}

resource "google_folder_iam_member" "developer_gke_dev" {
  folder = google_folder.dev.folder_id
  role   = "roles/container.developer"
  member = "group:${var.developer_group_email}"
}

resource "google_folder_iam_member" "developer_viewer_stage" {
  folder = google_folder.stage.folder_id
  role   = "roles/viewer"
  member = "group:${var.developer_group_email}"
}

resource "google_folder_iam_member" "developer_gke_stage" {
  folder = google_folder.stage.folder_id
  role   = "roles/container.developer"
  member = "group:${var.developer_group_email}"
}

# ── Infrastructure admin role bindings ───────────────────────────────────────
# Replaces a single roles/editor binding with scoped admin roles. editor is
# explicitly avoided per CIS and least-privilege; it can mutate things like
# IAM bindings on default SAs in ways an infra admin role rarely needs.

locals {
  infra_admin_folder_roles = [
    "roles/compute.admin",
    "roles/container.admin",
    "roles/cloudsql.admin",
    "roles/secretmanager.admin",
    "roles/iam.serviceAccountAdmin",
    "roles/resourcemanager.projectIamAdmin",
    "roles/storage.admin",
    "roles/monitoring.editor",
    "roles/logging.configWriter",
    "roles/artifactregistry.admin",
    "roles/serviceusage.serviceUsageAdmin",
  ]
}

resource "google_project_iam_member" "infra_admin_shared" {
  for_each = toset(local.infra_admin_folder_roles)
  project  = google_project.shared.project_id
  role     = each.value
  member   = "group:${var.infra_admin_group_email}"
}

# Org-wide audit logging — DATA_WRITE captures mutations across all projects.
# Admin Activity logs (create/delete/setIamPolicy) are always on and cannot be disabled.
resource "google_organization_iam_audit_config" "org_audit" {
  org_id  = var.org_id
  service = "allServices"

  audit_log_config {
    log_type = "DATA_WRITE"
  }
}

resource "google_folder_iam_member" "infra_admin_dev" {
  for_each = toset(local.infra_admin_folder_roles)
  folder   = google_folder.dev.folder_id
  role     = each.value
  member   = "group:${var.infra_admin_group_email}"
}

resource "google_folder_iam_member" "infra_admin_stage" {
  for_each = toset(local.infra_admin_folder_roles)
  folder   = google_folder.stage.folder_id
  role     = each.value
  member   = "group:${var.infra_admin_group_email}"
}

resource "google_folder_iam_member" "infra_admin_prod" {
  for_each = toset(local.infra_admin_folder_roles)
  folder   = google_folder.prod.folder_id
  role     = each.value
  member   = "group:${var.infra_admin_group_email}"
}
