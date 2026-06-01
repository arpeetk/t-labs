# Bucket: t-labs-state-stage (created by bootstrap)
# Run: terraform init -backend-config="bucket=$(cd ../../bootstrap && terraform output -raw state_bucket_stage)"
terraform {
  backend "gcs" {
    prefix = "terraform"
  }
}
