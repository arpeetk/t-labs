# ── Organization Policies ────────────────────────────────────────────────────
# GCP equivalent of AWS SCPs. Applied at the org level and inherited by all
# folders and projects. Cannot be overridden by project-level IAM.

# Restrict all resource creation to US regions.
resource "google_org_policy_policy" "resource_locations" {
  name   = "organizations/${var.org_id}/policies/gcp.resourceLocations"
  parent = "organizations/${var.org_id}"

  spec {
    rules {
      values {
        allowed_values = ["in:us-locations"]
      }
    }
  }

  depends_on = [google_organization_iam_member.terraform_org_policy_admin]
}

# Prevent Cloud SQL instances from having public IPs.
resource "google_org_policy_policy" "sql_no_public_ip" {
  name   = "organizations/${var.org_id}/policies/sql.restrictPublicIp"
  parent = "organizations/${var.org_id}"

  spec {
    rules {
      enforce = "TRUE"
    }
  }

  depends_on = [google_organization_iam_member.terraform_org_policy_admin]
}

# Require uniform bucket-level access on all GCS buckets.
# Blocks legacy per-object ACLs; enforces IAM-only access control.
resource "google_org_policy_policy" "gcs_uniform_access" {
  name   = "organizations/${var.org_id}/policies/storage.uniformBucketLevelAccess"
  parent = "organizations/${var.org_id}"

  spec {
    rules {
      enforce = "TRUE"
    }
  }

  depends_on = [google_organization_iam_member.terraform_org_policy_admin]
}

# Disable the automatic Editor grant on default service accounts.
# Default SAs auto-granted Editor is a well-known privilege escalation path.
resource "google_org_policy_policy" "disable_sa_auto_iam" {
  name   = "organizations/${var.org_id}/policies/iam.automaticIamGrantsForDefaultServiceAccounts"
  parent = "organizations/${var.org_id}"

  spec {
    rules {
      enforce = "TRUE"
    }
  }

  depends_on = [google_organization_iam_member.terraform_org_policy_admin]
}

# Block external IPs on all compute instances.
# GKE nodes are private; Cloud NAT handles outbound. No VM should be internet-reachable directly.
resource "google_org_policy_policy" "no_vm_external_ip" {
  name   = "organizations/${var.org_id}/policies/compute.vmExternalIpAccess"
  parent = "organizations/${var.org_id}"

  spec {
    rules {
      deny_all = "TRUE"
    }
  }

  depends_on = [google_organization_iam_member.terraform_org_policy_admin]
}

# Require Shielded VM on all compute instances (Secure Boot + vTPM).
# Consistent with GKE node pool config; protects against boot-level compromise.
resource "google_org_policy_policy" "require_shielded_vm" {
  name   = "organizations/${var.org_id}/policies/compute.requireShieldedVm"
  parent = "organizations/${var.org_id}"

  spec {
    rules {
      enforce = "TRUE"
    }
  }

  depends_on = [google_organization_iam_member.terraform_org_policy_admin]
}
