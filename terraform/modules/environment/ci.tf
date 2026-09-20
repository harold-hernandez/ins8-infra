# --- CI/CD: GitHub Actions via Workload Identity Federation ------------------
# A workflow requests a short-lived OIDC token (`permissions: id-token: write`)
# and the official `google-github-actions/auth` action trades it for GCP
# credentials through Workload Identity Federation — no service-account JSON
# key is ever stored as a GitHub secret. Matches CLAUDE.md's "JWT signing
# secret comes only from JWT_SECRET, never hardcoded" rule — same principle,
# applied to the identity CI deploys as.
#
# Two independent deploy identities (ci_backend / ci_frontend), each trusted
# by exactly one GitHub repository via attribute_condition below: a
# compromised or misconfigured workflow in one repo still can't deploy the
# other, and neither can any other repository under the same GitHub account.
# This is the same "defense in depth" reasoning CLAUDE.md gives for scoping
# every Postgres query by client_id even though middleware already checked
# it — the IAM binding's principalSet restriction and this attribute_condition
# are two independent checks, not one.

resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = "${local.name_prefix}-github"
  display_name              = "GitHub Actions (${var.environment})"
  depends_on                = [google_project_service.apis]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"
  display_name                       = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.ref"              = "assertion.ref"
  }

  # Belt-and-suspenders alongside the per-service-account principalSet
  # bindings below: even a token from the right GitHub account is rejected
  # here unless it also claims one of the two repositories this environment
  # actually deploys from, and the branch this environment deploys on.
  # (Prod's copy of this same module should tighten ci_deploy_branch to a
  # release branch/tag once prod deploys are wired up — see the root README,
  # prod is deliberately not there yet.)
  attribute_condition = "attribute.repository_owner == \"${var.github_owner}\" && attribute.ref == \"refs/heads/${var.ci_deploy_branch}\" && (attribute.repository == \"${var.backend_repository}\" || attribute.repository == \"${var.frontend_repository}\")"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
    # No allowed_audiences override needed here (unlike the previous
    # Bitbucket setup): google-github-actions/auth requests the OIDC token
    # with its audience already set to this provider's own resource name,
    # which is what GCP expects by default.
  }
}

resource "google_service_account" "ci_backend" {
  project      = var.project_id
  account_id   = "${local.name_prefix}-ci-backend"
  display_name = "GitHub Actions deploy identity for the backend repo (${var.environment})"
}

resource "google_service_account" "ci_frontend" {
  project      = var.project_id
  account_id   = "${local.name_prefix}-ci-frontend"
  display_name = "GitHub Actions deploy identity for the frontend repo (${var.environment})"
}

resource "google_service_account_iam_member" "ci_backend_wif" {
  service_account_id = google_service_account.ci_backend.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.backend_repository}"
}

resource "google_service_account_iam_member" "ci_frontend_wif" {
  service_account_id = google_service_account.ci_frontend.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.frontend_repository}"
}

# --- Least-privilege deploy grants -------------------------------------------
# Each CI identity can push its own image and redeploy its own Cloud Run
# service/job only — nothing project-wide, mirroring the backend/frontend
# runtime service-account split above (google_service_account.backend /
# .frontend), which likewise get only the two grants each actually needs.

resource "google_artifact_registry_repository_iam_member" "ci_backend_push" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.app.repository_id
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.ci_backend.email}"
}

resource "google_artifact_registry_repository_iam_member" "ci_frontend_push" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.app.repository_id
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.ci_frontend.email}"
}

resource "google_cloud_run_v2_service_iam_member" "ci_backend_deploy" {
  project  = var.project_id
  location = var.region
  name     = module.backend.name
  role     = "roles/run.developer"
  member   = "serviceAccount:${google_service_account.ci_backend.email}"
}

resource "google_cloud_run_v2_service_iam_member" "ci_frontend_deploy" {
  project  = var.project_id
  location = var.region
  name     = module.frontend.name
  role     = "roles/run.developer"
  member   = "serviceAccount:${google_service_account.ci_frontend.email}"
}

resource "google_cloud_run_v2_job_iam_member" "ci_backend_run_migration" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_job.migrate.name
  role     = "roles/run.developer"
  member   = "serviceAccount:${google_service_account.ci_backend.email}"
}

# `gcloud run deploy` needs to act *as* the runtime service account it's
# assigning to the new revision (roles/run.developer alone only covers
# managing the Cloud Run resource itself, not "wearing" another SA).
resource "google_service_account_iam_member" "ci_backend_runtime_sa_user" {
  service_account_id = google_service_account.backend.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.ci_backend.email}"
}

resource "google_service_account_iam_member" "ci_backend_migrate_sa_user" {
  service_account_id = google_service_account.migrate.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.ci_backend.email}"
}

resource "google_service_account_iam_member" "ci_frontend_runtime_sa_user" {
  service_account_id = google_service_account.frontend.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.ci_frontend.email}"
}
