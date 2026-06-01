# ── GitHub Actions — Workload Identity Federation ─────────────────────────────
# Allows GitHub Actions to authenticate to GCP without long-lived SA keys.
# After applying bootstrap, set these GitHub repo secrets:
#   WIF_PROVIDER = $(terraform output -raw workload_identity_provider)
#   TF_SA_EMAIL  = $(terraform output -raw terraform_service_account_email)

resource "google_iam_workload_identity_pool" "github" {
  project                   = google_project.shared.project_id
  workload_identity_pool_id = "github-actions"
  display_name              = "GitHub Actions"

  depends_on = [google_project_service.shared_apis]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = google_project.shared.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-repo"
  display_name                       = "arpeetk/t-labs"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
    "attribute.actor"      = "assertion.actor"
  }

  # Only tokens issued for this specific repository are trusted.
  attribute_condition = "assertion.repository == 'arpeetk/t-labs'"
}

# Allow GitHub Actions tokens from this repo to impersonate the Terraform SA.
resource "google_service_account_iam_member" "github_wif" {
  service_account_id = google_service_account.terraform.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/arpeetk/t-labs"
}

output "workload_identity_provider" {
  description = "Full provider resource name — set as WIF_PROVIDER GitHub secret."
  value       = google_iam_workload_identity_pool_provider.github.name
}
