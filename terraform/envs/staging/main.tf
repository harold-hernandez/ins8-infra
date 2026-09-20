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
  #   gcloud storage buckets create gs://seedtech-tfstate-staging \
  #     --project=<your-staging-project-id> --location=us-east4 --uniform-bucket-level-access
  backend "gcs" {
    bucket = "seedtech-tfstate-staging"
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
  environment = "staging"
  domain      = var.domain

  backend_image  = var.backend_image
  frontend_image = var.frontend_image
  migrate_image  = var.migrate_image

  extra_cors_origins = var.extra_cors_origins

  github_owner        = var.github_owner
  backend_repository  = var.backend_repository
  frontend_repository = var.frontend_repository
  # Staging tracks main continuously — every merge deploys. Prod (once wired)
  # should not reuse "main" here; see ci.tf's comment on ci_deploy_branch.
  ci_deploy_branch = "main"

  # Scale-to-zero in staging: pairs with Neon's own autosuspend, so an idle
  # staging environment costs nothing. First request after idle eats a cold
  # start (DB reconnect + Cloud Run boot) — acceptable for staging.
  backend_min_instances  = 0
  frontend_min_instances = 0
}
