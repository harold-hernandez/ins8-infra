terraform {
  required_version = ">= 1.7.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
  }

  # Bootstrap this bucket once, by hand, before the first `terraform init`:
  #   gcloud storage buckets create gs://ins8-frontend-tfstate \
  #     --project=ins8-frontend --location=us-east4 --uniform-bucket-level-access
  backend "gcs" {
    bucket = "ins8-frontend-tfstate"
    prefix = "terraform/state"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_project_service" "apis" {
  for_each = toset([
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
  ])
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_artifact_registry_repository" "app" {
  project       = var.project_id
  location      = var.region
  repository_id = "app"
  format        = "DOCKER"
  depends_on    = [google_project_service.apis]
}

resource "google_service_account" "frontend" {
  project      = var.project_id
  account_id   = "ins8-frontend-runtime"
  display_name = "Cloud Run runtime SA for ins8-frontend"
}

# No domain mapping (see the root README) — the frontend is reachable only
# at its raw *.run.app URL for now. That URL is cross-site from the
# backend's own *.run.app URL, so the SameSite=Lax session cookie won't
# survive a real browser login yet; everything else (the deploy pipeline,
# the site serving, direct backend calls) works and is worth verifying
# before that gets fixed.
module "frontend" {
  source = "../../modules/cloud-run-service"

  project_id            = var.project_id
  region                = var.region
  name                  = "ins8-frontend"
  image                 = var.frontend_image
  service_account_email = google_service_account.frontend.email
  min_instance_count    = var.min_instances
  max_instance_count    = var.max_instances
  allow_unauthenticated = true

  depends_on = [google_project_service.apis]
}

module "ci" {
  source = "../../modules/github-ci-identity"

  project_id                      = var.project_id
  region                          = var.region
  name_prefix                     = "ins8-frontend"
  repository                      = var.github_repository
  ci_deploy_branch                = var.ci_deploy_branch
  artifact_registry_repository_id = google_artifact_registry_repository.app.repository_id
  cloud_run_service_names         = [module.frontend.name]
  runtime_service_accounts        = { frontend = google_service_account.frontend.name }

  depends_on = [google_project_service.apis]
}
