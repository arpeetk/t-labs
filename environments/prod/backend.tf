# Bucket: t-labs-state-prod (created by bootstrap)
# Run: terraform init -backend-config="bucket=$(cd ../../bootstrap && terraform output -raw state_bucket_prod)"
terraform {
  backend "gcs" {
    prefix = "terraform"
  }
}
