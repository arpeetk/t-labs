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
    "google.subject"        = "assertion.sub"
    "attribute.repository"  = "assertion.repository"
    "attribute.ref"         = "assertion.ref"
    "attribute.actor"       = "assertion.actor"
    "attribute.environment" = "assertion.environment"
    "attribute.event_name"  = "assertion.event_name"
  }

  # Only tokens issued for this specific repository are trusted.
  attribute_condition = "assertion.repository == 'arpeetk/t-labs'"
}

# ── WIF principal bindings ─────────────────────────────────────────────────
#
# Each binding answers: "which subset of GitHub Actions jobs can impersonate
# this SA?" The narrower the principalSet, the smaller the blast radius.
#
#   terraform-{env} : only jobs that opt into GitHub Environment <env>. The
#                     environment gate also enforces required reviewers.
#   terraform-plan-ro : only pull_request events. PR authors can run plan
#                       but the SA has no write permissions to begin with.
#   ci-image-pusher : push events (no PRs) so a malicious PR cannot push images.
#   terraform (legacy) : still bound to the whole repo for backward compat,
#                        deleted after Phase D migrates the workflows.

# Per-env Terraform SAs — tied to GitHub Environment claim.
# Bound to BOTH "<env>" (apply jobs, required-reviewers gated) and "<env>-plan"
# (plan jobs, no gate). The plan-job environment carries no required reviewers
# in GitHub, so plan runs immediately and its output becomes the context for
# the approval that gates the apply job.
resource "google_service_account_iam_member" "github_wif_terraform_env" {
  for_each = google_service_account.terraform_env

  service_account_id = each.value.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.environment/${each.key}"
}

resource "google_service_account_iam_member" "github_wif_terraform_env_plan" {
  for_each = google_service_account.terraform_env

  service_account_id = each.value.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.environment/${each.key}-plan"
}

# Plan-only SA — tied to pull_request events.
resource "google_service_account_iam_member" "github_wif_terraform_plan_ro" {
  service_account_id = google_service_account.terraform_plan_ro.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.event_name/pull_request"
}

# Image push SA — tied to push events only, blocking misuse via PR workflows.
resource "google_service_account_iam_member" "github_wif_image_pusher" {
  service_account_id = google_service_account.ci_image_pusher.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.event_name/push"
}

# Legacy: the original cross-repo binding for the catch-all terraform SA.
# Removed once Phase D ships and no workflow references TF_SA_EMAIL.
resource "google_service_account_iam_member" "github_wif" {
  service_account_id = google_service_account.terraform.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/arpeetk/t-labs"
}

output "workload_identity_provider" {
  description = "Full provider resource name — set as WIF_PROVIDER GitHub secret."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "image_pusher_sa_email" {
  description = "SA for Docker image pushes — set as IMAGES_SA_EMAIL GitHub secret."
  value       = google_service_account.ci_image_pusher.email
}

output "terraform_env_sa_emails" {
  description = "Per-env Terraform SA emails — set as TF_SA_EMAIL_DEV / _STAGE / _PROD GitHub secrets."
  value       = { for k, v in google_service_account.terraform_env : k => v.email }
}

output "terraform_plan_ro_sa_email" {
  description = "Read-only SA for the PR plan job — set as TF_SA_EMAIL_PLAN GitHub secret."
  value       = google_service_account.terraform_plan_ro.email
}
