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
  #   gcloud storage buckets create gs://ins8-tasks-tfstate \
  #     --project=ins8-tasks --location=us-east4 --uniform-bucket-level-access
  backend "gcs" {
    bucket = "ins8-tasks-tfstate"
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

resource "google_project_service" "apis" {
  for_each = toset([
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "secretmanager.googleapis.com",
    "storage.googleapis.com",
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

# --- Postgres (Neon, free tier) -------------------------------------------

resource "neon_project" "this" {
  name       = "ins8-tasks"
  region_id  = var.neon_region_id
  pg_version = var.neon_pg_version
}

# --- Secrets ------------------------------------------------------------
# JWT_SECRET and DATABASE_URL are never written to a .tfvars file or a
# terraform.tfstate value a human reads directly — they live in Secret
# Manager, and Cloud Run's `secret_env` wiring below pulls them in as env
# vars at container start. Matches tasks/CLAUDE.md's "JWT signing secret
# comes only from the JWT_SECRET env var, never hardcoded" rule.

resource "random_password" "jwt_secret" {
  length           = 64
  special          = true
  override_special = "-_.~"
}

resource "google_secret_manager_secret" "jwt_secret" {
  project   = var.project_id
  secret_id = "ins8-tasks-jwt-secret"
  replication {
    auto {}
  }
  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "jwt_secret" {
  secret      = google_secret_manager_secret.jwt_secret.id
  secret_data = random_password.jwt_secret.result
}

resource "google_secret_manager_secret" "database_url" {
  project   = var.project_id
  secret_id = "ins8-tasks-database-url"
  replication {
    auto {}
  }
  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "database_url" {
  secret      = google_secret_manager_secret.database_url.id
  secret_data = neon_project.this.connection_uri
}

# --- Uploaded floorplan images -----------------------------------------------
# Cloud Run instances have no persistent local disk, so
# internal/storage.LocalStorage's UPLOAD_DIR is pointed at a GCS bucket
# mounted in-container via Cloud Run's native Cloud Storage FUSE volume
# support. force_destroy = true since this is the only environment right
# now and its data isn't precious yet — revisit if that changes.

resource "google_storage_bucket" "uploads" {
  project                     = var.project_id
  name                        = "ins8-tasks-uploads-${var.project_id}"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true
}

# --- Runtime service account -------------------------------------------------

resource "google_service_account" "backend" {
  project      = var.project_id
  account_id   = "ins8-tasks-runtime"
  display_name = "Cloud Run runtime SA for ins8-tasks"
}

resource "google_secret_manager_secret_iam_member" "backend_jwt_secret_access" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.jwt_secret.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.backend.email}"
}

resource "google_secret_manager_secret_iam_member" "backend_database_url_access" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.database_url.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.backend.email}"
}

resource "google_storage_bucket_iam_member" "backend_uploads_access" {
  bucket = google_storage_bucket.uploads.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.backend.email}"
}

# --- Backend Cloud Run service ------------------------------------------------
# No domain mapping (see the root README and envs/ins8-frontend) — reachable
# only at its raw *.run.app URL for now. CORS_ALLOWED_ORIGINS therefore
# can't be auto-wired from the frontend's own Terraform output the way it
# could when both services shared one apply; var.frontend_url is filled in
# by hand instead, from `terraform output -raw frontend_url` in
# envs/ins8-frontend, once that's been applied.

module "backend" {
  source = "../../modules/cloud-run-service"

  project_id            = var.project_id
  region                = var.region
  name                  = "ins8-tasks"
  image                 = var.backend_image
  service_account_email = google_service_account.backend.email
  cpu                   = var.backend_cpu
  memory                = var.backend_memory
  min_instance_count    = var.min_instances
  max_instance_count    = var.max_instances
  allow_unauthenticated = true

  env = [
    { name = "APP_ENV", value = "production" },
    { name = "JWT_ACCESS_TTL", value = var.jwt_access_ttl },
    { name = "UPLOAD_DIR", value = "/mnt/uploads" },
    { name = "CORS_ALLOWED_ORIGINS", value = join(",", concat([var.frontend_url], var.extra_cors_origins)) },
  ]

  secret_env = [
    { name = "DATABASE_URL", secret_id = google_secret_manager_secret.database_url.secret_id },
    { name = "JWT_SECRET", secret_id = google_secret_manager_secret.jwt_secret.secret_id },
  ]

  gcs_volumes = [
    { name = "uploads", bucket = google_storage_bucket.uploads.name, mount_path = "/mnt/uploads" },
  ]

  depends_on = [
    google_project_service.apis,
    google_secret_manager_secret_version.database_url,
    google_secret_manager_secret_version.jwt_secret,
    google_secret_manager_secret_iam_member.backend_jwt_secret_access,
    google_secret_manager_secret_iam_member.backend_database_url_access,
    google_storage_bucket_iam_member.backend_uploads_access,
  ]
}

# --- Database migrations -----------------------------------------------------
# A Cloud Run Job running golang-migrate against Neon, executed on demand by
# CI after pushing a new migrate image (`gcloud run jobs execute ... --wait`).
# tasks/migrations/Dockerfile builds the image: golang-migrate's official
# binary plus this repo's migrations/*.sql, with every dev-only
# *_seed_*.sql fixture migration stripped out.

resource "google_service_account" "migrate" {
  project      = var.project_id
  account_id   = "ins8-tasks-migrate"
  display_name = "Cloud Run Job runtime SA for golang-migrate"
}

resource "google_secret_manager_secret_iam_member" "migrate_database_url_access" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.database_url.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.migrate.email}"
}

resource "google_cloud_run_v2_job" "migrate" {
  name     = "ins8-tasks-migrate"
  project  = var.project_id
  location = var.region

  template {
    template {
      service_account = google_service_account.migrate.email
      max_retries     = 0
      timeout         = "300s"

      containers {
        image = var.migrate_image

        # The migrate/migrate image's own ENTRYPOINT is ["migrate"], with no
        # shell involved — overriding to alpine's /bin/sh here is what makes
        # $DATABASE_URL below actually expand, rather than being passed to
        # migrate as a literal, unexpanded string.
        command = ["/bin/sh", "-c"]
        args    = ["migrate -path=/migrations -database=\"$DATABASE_URL\" up"]

        env {
          name = "DATABASE_URL"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.database_url.secret_id
              version = "latest"
            }
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      template[0].template[0].containers[0].image,
    ]
  }

  depends_on = [
    google_project_service.apis,
    google_secret_manager_secret_version.database_url,
    google_secret_manager_secret_iam_member.migrate_database_url_access,
  ]
}

# --- CI deploy identity --------------------------------------------------

module "ci" {
  source = "../../modules/github-ci-identity"

  project_id                      = var.project_id
  region                          = var.region
  name_prefix                     = "ins8-tasks"
  repository                      = var.github_repository
  ci_deploy_branch                = var.ci_deploy_branch
  artifact_registry_repository_id = google_artifact_registry_repository.app.repository_id
  cloud_run_service_names         = [module.backend.name]
  cloud_run_job_names             = [google_cloud_run_v2_job.migrate.name]
  runtime_service_account_names   = [google_service_account.backend.name, google_service_account.migrate.name]

  depends_on = [google_project_service.apis]
}
