locals {
  name_prefix = "seedtech-${var.environment}"

  # Both hostnames share the registrable domain var.domain (e.g. "seedtech.dev")
  # so they're same-site for the session cookie's SameSite=Lax check, even
  # though they're two different Cloud Run services. Using "app."/"api."
  # subdomains uniformly (rather than the bare domain for prod) keeps every
  # domain mapping a CNAME — no apex/ALIAS-record special-casing per DNS
  # provider.
  env_subdomain     = var.environment == "prod" ? "" : "${var.environment}."
  frontend_hostname = "app.${local.env_subdomain}${var.domain}"
  backend_hostname  = "api.${local.env_subdomain}${var.domain}"
}

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
  repository_id = var.artifact_registry_repository_id
  format        = "DOCKER"
  depends_on    = [google_project_service.apis]
}

# --- Postgres (Neon, free tier) -------------------------------------------

resource "neon_project" "this" {
  name       = local.name_prefix
  region_id  = var.neon_region_id
  pg_version = var.neon_pg_version
}

# --- Secrets ----------------------------------------------------------------
# JWT_SECRET and DATABASE_URL are never written to a .tfvars file or a
# terraform.tfstate value a human reads directly — they live in Secret
# Manager, and Cloud Run's `secret_env` wiring below pulls them in as env
# vars at container start. Matches CLAUDE.md's "JWT signing secret comes
# only from the JWT_SECRET env var, never hardcoded" rule.

resource "random_password" "jwt_secret" {
  length           = 64
  special          = true
  override_special = "-_.~"
}

resource "google_secret_manager_secret" "jwt_secret" {
  project   = var.project_id
  secret_id = "${local.name_prefix}-jwt-secret"
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
  secret_id = "${local.name_prefix}-database-url"
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
# Cloud Run instances have no persistent local disk (a fresh instance, or an
# instance recycled after scale-to-zero, starts with an empty filesystem),
# so internal/storage.LocalStorage's UPLOAD_DIR is pointed at a GCS bucket
# mounted in-container via Cloud Run's native Cloud Storage FUSE volume
# support. The application code is unchanged — it just sees a directory.

resource "google_storage_bucket" "uploads" {
  project                     = var.project_id
  name                        = "${local.name_prefix}-uploads-${var.project_id}"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = var.environment != "prod"
}

# --- Runtime service accounts ------------------------------------------------
# Two separate, minimally-privileged accounts rather than the default
# Compute Engine service account: the frontend gets no extra IAM roles at
# all (it serves static assets and proxies nothing sensitive), and the
# backend only gets exactly the two grants it needs.

resource "google_service_account" "backend" {
  project      = var.project_id
  account_id   = "${local.name_prefix}-backend"
  display_name = "Cloud Run runtime SA for the tasks backend (${var.environment})"
}

resource "google_service_account" "frontend" {
  project      = var.project_id
  account_id   = "${local.name_prefix}-frontend"
  display_name = "Cloud Run runtime SA for the ins8 frontend (${var.environment})"
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

# --- Frontend Cloud Run service ----------------------------------------------

module "frontend" {
  source = "../cloud-run-service"

  project_id            = var.project_id
  region                = var.region
  name                  = "${local.name_prefix}-frontend"
  image                 = var.frontend_image
  service_account_email = google_service_account.frontend.email
  cpu                   = var.frontend_cpu
  memory                = var.frontend_memory
  min_instance_count    = var.frontend_min_instances
  max_instance_count    = var.frontend_max_instances
  allow_unauthenticated = true

  depends_on = [google_project_service.apis]
}

# --- Backend Cloud Run service ------------------------------------------------
# CORS_ALLOWED_ORIGINS is wired straight from the frontend service's own
# Cloud Run URL, so this never needs a manual update — Terraform resolves
# the dependency automatically. VITE_API_BASE_URL (the frontend's env var
# pointing *at* the backend) can't be wired the same way: Vite inlines it at
# build time, before Terraform ever runs. See the root README for the
# apply -> read backend_url -> build frontend image -> deploy order this
# implies for a brand-new environment.

module "backend" {
  source = "../cloud-run-service"

  project_id            = var.project_id
  region                = var.region
  name                  = "${local.name_prefix}-backend"
  image                 = var.backend_image
  service_account_email = google_service_account.backend.email
  cpu                   = var.backend_cpu
  memory                = var.backend_memory
  min_instance_count    = var.backend_min_instances
  max_instance_count    = var.backend_max_instances
  allow_unauthenticated = true

  env = [
    { name = "APP_ENV", value = var.app_env },
    { name = "JWT_ACCESS_TTL", value = var.jwt_access_ttl },
    { name = "UPLOAD_DIR", value = "/mnt/uploads" },
    # The custom-domain origin is what actually matters (see the SameSite
    # note on local.frontend_hostname above); the raw *.run.app URL is kept
    # too purely so hitting it directly during setup/debugging doesn't trip
    # CORS as a secondary symptom on top of the cookie not arriving.
    { name = "CORS_ALLOWED_ORIGINS", value = join(",", concat(["https://${local.frontend_hostname}", module.frontend.uri], var.extra_cors_origins)) },
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

# --- Custom domains ----------------------------------------------------------
# Required, not cosmetic: see local.frontend_hostname's comment above for why
# both services need to live under one registrable domain. `var.domain` must
# already be a verified domain (Google Search Console) under the identity
# running Terraform, or these fail at apply time — see README "Prerequisites".

resource "google_cloud_run_domain_mapping" "frontend" {
  name     = local.frontend_hostname
  location = var.region
  project  = var.project_id

  metadata {
    namespace = var.project_id
  }

  spec {
    route_name       = module.frontend.name
    certificate_mode = "AUTOMATIC"
  }
}

resource "google_cloud_run_domain_mapping" "backend" {
  name     = local.backend_hostname
  location = var.region
  project  = var.project_id

  metadata {
    namespace = var.project_id
  }

  spec {
    route_name       = module.backend.name
    certificate_mode = "AUTOMATIC"
  }
}
