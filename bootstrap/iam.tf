# ── Terraform CI/CD service account ─────────────────────────────────────────

resource "google_service_account" "terraform" {
  account_id   = "terraform"
  display_name = "Terraform Service Account"
  project      = google_project.shared.project_id

  depends_on = [google_project_service.shared_apis]
}

resource "google_organization_iam_member" "terraform_folder_admin" {
  org_id = var.org_id
  role   = "roles/resourcemanager.folderAdmin"
  member = "serviceAccount:${google_service_account.terraform.email}"
}

resource "google_organization_iam_member" "terraform_project_creator" {
  org_id = var.org_id
  role   = "roles/resourcemanager.projectCreator"
  member = "serviceAccount:${google_service_account.terraform.email}"
}

resource "google_billing_account_iam_member" "terraform_billing_user" {
  billing_account_id = var.billing_account_id
  role               = "roles/billing.user"
  member             = "serviceAccount:${google_service_account.terraform.email}"
}

resource "google_project_iam_member" "terraform_owner" {
  for_each = local.env_projects

  project = each.value
  role    = "roles/owner"
  member  = "serviceAccount:${google_service_account.terraform.email}"
}

resource "google_project_iam_member" "terraform_shared_owner" {
  project = google_project.shared.project_id
  role    = "roles/owner"
  member  = "serviceAccount:${google_service_account.terraform.email}"
}

resource "google_organization_iam_member" "terraform_org_policy_admin" {
  org_id = var.org_id
  role   = "roles/orgpolicy.policyAdmin"
  member = "serviceAccount:${google_service_account.terraform.email}"
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
# Infra admins get editor rights across all environment folders including prod,
# plus editor on the management project so they can manage Artifact Registry and state buckets.

resource "google_project_iam_member" "infra_admin_shared" {
  project = google_project.shared.project_id
  role    = "roles/editor"
  member  = "group:${var.infra_admin_group_email}"
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
  folder = google_folder.dev.folder_id
  role   = "roles/editor"
  member = "group:${var.infra_admin_group_email}"
}

resource "google_folder_iam_member" "infra_admin_stage" {
  folder = google_folder.stage.folder_id
  role   = "roles/editor"
  member = "group:${var.infra_admin_group_email}"
}

resource "google_folder_iam_member" "infra_admin_prod" {
  folder = google_folder.prod.folder_id
  role   = "roles/editor"
  member = "group:${var.infra_admin_group_email}"
}
