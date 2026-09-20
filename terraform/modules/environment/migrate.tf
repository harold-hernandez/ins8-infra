# --- Database migrations -----------------------------------------------------
# A Cloud Run Job running golang-migrate against Neon, executed on demand by
# CI after pushing a new migrate image (`gcloud run jobs execute ... --wait`)
# — see the root README's "what's deliberately not here yet" section this
# closes. Not run automatically by `terraform apply`; ordering relative to
# the backend deploy is the pipeline's job, not Terraform's.
#
# tasks/migrations/Dockerfile builds the image this job runs: golang-migrate's
# official binary plus this repo's migrations/*.sql, with every dev-only
# *_seed_*.sql fixture migration stripped out (see that Dockerfile's own
# comment) — staging and prod only ever get real schema changes this way,
# never Acme/Megaworld's fake demo data.

resource "google_service_account" "migrate" {
  project      = var.project_id
  account_id   = "${local.name_prefix}-migrate"
  display_name = "Cloud Run Job runtime SA for golang-migrate (${var.environment})"
}

resource "google_secret_manager_secret_iam_member" "migrate_database_url_access" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.database_url.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.migrate.email}"
}

resource "google_cloud_run_v2_job" "migrate" {
  name     = "${local.name_prefix}-migrate"
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

  # CI pushes new migrate images directly, same reasoning as
  # cloud-run-service's image lifecycle block.
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
