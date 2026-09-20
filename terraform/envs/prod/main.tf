terraform {
  required_version = ">= 1.7.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
    neon = {
      source  = "kislerdm/neon"
      version = "~> 0.18"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Bootstrap this bucket once, by hand, before the first `terraform init`:
  #   gcloud storage buckets create gs://seedtech-tfstate-prod \
  #     --project=<your-prod-project-id> --location=us-east4 --uniform-bucket-level-access
  backend "gcs" {
    bucket = "seedtech-tfstate-prod"
    prefix = "terraform/state"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Reads NEON_API_KEY from the environment — see ../../README.md. Never
# committed to a tfvars file.
provider "neon" {}

module "environment" {
  source = "../../modules/environment"

  project_id  = var.project_id
  region      = var.region
  environment = "prod"
  domain      = var.domain

  backend_image  = var.backend_image
  frontend_image = var.frontend_image

  extra_cors_origins = var.extra_cors_origins

  # Keep at least one warm instance in prod: a cold start here means a real
  # user waits on it, not just whoever's poking at staging.
  backend_min_instances  = 1
  backend_max_instances  = 5
  frontend_min_instances = 1
  frontend_max_instances = 5
}
