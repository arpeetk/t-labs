# Bucket: t-labs-state-dev (created by bootstrap)
# Run: terraform init -backend-config="bucket=$(cd ../../bootstrap && terraform output -raw state_bucket_dev)"
terraform {
  backend "gcs" {
    prefix = "terraform"
  }
}
