terraform {
  required_version = ">= 1.8"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.35"
    }
  }
}

# No project set at provider level — bootstrap creates projects from scratch.
# Authenticate with: gcloud auth application-default login
provider "google" {}
