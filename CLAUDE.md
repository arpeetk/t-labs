# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

GCP infrastructure repo using Terraform. Manages four GCP projects (management, dev, stage, prod) under a single GCP Organization with one billing account. Each environment gets its own VPC, GKE cluster (regional, HA), and Cloud SQL PostgreSQL instance. A shared Artifact Registry lives in the management project.

## Repository layout

```
bootstrap/          # One-time org setup — run first, uses local state initially
modules/
  vpc/              # VPC, 3 subnets (public/private-gke/private-data), Cloud NAT, PSA
  gke/              # Regional GKE cluster + autoscaling node pool + Workload Identity
  cloudsql/         # HA PostgreSQL, private IP only, password auto-stored in Secret Manager
environments/
  dev/              # Calls all 3 modules; deletion_protection=false; small sizing
  stage/            # Same structure; medium sizing; non-overlapping CIDRs (10.10.x.x)
  prod/             # Same structure; deletion_protection=true; large sizing (10.20.x.x)
```

## Workflow

### First time (run once)

```bash
cd bootstrap
terraform init
terraform apply          # creates org folders, 4 projects, GCS bucket, Artifact Registry, IAM

# Migrate bootstrap state into GCS
terraform init -migrate-state -backend-config="bucket=$(terraform output -raw state_bucket_name)"
```

### Per environment

```bash
cd environments/dev      # or stage / prod
terraform init -backend-config="bucket=t-labs-terraform-state"
terraform plan
terraform apply
```

### Common commands

```bash
terraform fmt -recursive         # format all files
terraform validate               # validate config in current directory
terraform output                 # show environment outputs after apply
terraform state list             # inspect what's in state
```

## Key design decisions

**IAM**: Uses Google Workspace Groups instead of Workforce Identity Federation — simpler since the org is on Google Workspace. Two groups (`developers@buildersfundvc.com`, `infra-admins@buildersfundvc.com`) are created in `admin.google.com` and bound to folder-level IAM roles in bootstrap. Adding/removing a user from a group takes effect immediately with no Terraform change needed.

**Networking**: GCP subnets are regional (span all zones automatically). Each env uses one public, one private-gke, and one private-data subnet. CIDRs are non-overlapping across envs (dev: 10.0.x, stage: 10.10.x, prod: 10.20.x) in case VPC peering is ever needed. Cloud NAT provides outbound internet for private subnets. Private Google Access is on for private subnets.

**GKE**: Regional cluster (HA control plane + nodes across 3 zones). Cluster Autoscaler scales nodes; apps define their own HPAs. Workload Identity is enabled at cluster and node level — `GKE_METADATA` mode on nodes is required. Dataplane V2 (ADVANCED_DATAPATH) provides eBPF networking and built-in network policy.

**Cloud SQL**: Private IP only (no public IP), bound to the VPC via Private Services Access. `availability_type = REGIONAL` = HA with automatic failover to a standby in another zone. DB password is auto-generated and written to Secret Manager at apply time — read it with `terraform output db_password_secret_id`.

**Artifact Registry**: Single shared repo in the management project. Each environment's GKE node service account is granted `roles/artifactregistry.reader` cross-project from within the environment's Terraform.

**Workload Identity (IRSA equivalent)**: For apps that need GCP resource access (buckets, queues, etc.), create a Google Service Account, grant it the required roles, then bind it to the Kubernetes ServiceAccount:
```hcl
resource "google_service_account_iam_member" "workload_identity" {
  service_account_id = google_service_account.app.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[namespace/k8s-sa-name]"
}
```
Annotate the Kubernetes ServiceAccount with `iam.gke.io/gcp-service-account: <gsa-email>`.

**State locking**: GCS backend uses native object-level locking — no DynamoDB equivalent needed. Versioning is enabled; old state versions are pruned after 10 newer versions exist.

**State buckets**: One dedicated bucket per environment, all in the management project. Developers have read access to dev/stage buckets only; prod state bucket is restricted to infra-admin and the Terraform SA.

| Bucket | Used by |
|--------|---------|
| `t-labs-state-bootstrap` | `bootstrap/` |
| `t-labs-state-dev` | `environments/dev/` |
| `t-labs-state-stage` | `environments/stage/` |
| `t-labs-state-prod` | `environments/prod/` |

**Bootstrap state**: The `bootstrap/` directory starts with local state. After first apply, migrate it to GCS:
```bash
terraform init -migrate-state -backend-config="bucket=$(terraform output -raw state_bucket_bootstrap)"
```

## What's not in Terraform (configure manually or in CI)

- `gcloud auth application-default login` — required before running Terraform locally
- Google Workspace group membership — managed in admin.google.com, not Terraform
- `kubectl` context setup: `gcloud container clusters get-credentials <cluster-name> --region <region> --project <project-id>`
- `docker push` to Artifact Registry: `gcloud auth configure-docker us-central1-docker.pkg.dev`
