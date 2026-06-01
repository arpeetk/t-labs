# State is stored in GCS after first apply.
# Run: terraform init -migrate-state -backend-config="bucket=t-labs-state-bootstrap"
terraform {
  backend "gcs" {
    prefix = "terraform"
  }
}
