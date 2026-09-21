# A GitHub Actions deploy identity for one GCP project, trusted by exactly
# one repository via Workload Identity Federation — no service-account key
# ever stored as a GitHub secret. Reused identically by both envs/ (frontend,
# backend); the only differences between them are which Cloud Run
# services/jobs and runtime service accounts this identity is allowed to
# touch, passed in as arguments.

resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = "${var.name_prefix}-github"
  display_name              = "GitHub Actions"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"
  display_name                       = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  # With only one repository trusted per project (unlike the earlier shared-
  # project design, where this condition had to OR between two repos), this
  # duplicates what the principalSet binding below already enforces — kept
  # anyway as an independently-configured second check, not a single point
  # of failure if one or the other gets misconfigured later.
  attribute_condition = "attribute.repository == \"${var.repository}\" && attribute.ref == \"refs/heads/${var.ci_deploy_branch}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account" "ci" {
  project      = var.project_id
  account_id   = "${var.name_prefix}-ci"
  display_name = "GitHub Actions deploy identity for ${var.repository}"
}

resource "google_service_account_iam_member" "ci_wif" {
  service_account_id = google_service_account.ci.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.repository}"
}

resource "google_artifact_registry_repository_iam_member" "ci_push" {
  project    = var.project_id
  location   = var.region
  repository = var.artifact_registry_repository_id
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.ci.email}"
}

resource "google_cloud_run_v2_service_iam_member" "ci_deploy" {
  for_each = toset(var.cloud_run_service_names)
  project  = var.project_id
  location = var.region
  name     = each.value
  role     = "roles/run.developer"
  member   = "serviceAccount:${google_service_account.ci.email}"
}

resource "google_cloud_run_v2_job_iam_member" "ci_run_job" {
  for_each = toset(var.cloud_run_job_names)
  project  = var.project_id
  location = var.region
  name     = each.value
  role     = "roles/run.developer"
  member   = "serviceAccount:${google_service_account.ci.email}"
}

# `gcloud run deploy`/`jobs update` needs to act *as* the runtime service
# account it's assigning to the revision/job (roles/run.developer alone only
# covers managing the Cloud Run resource itself, not "wearing" another SA).
resource "google_service_account_iam_member" "ci_sa_user" {
  for_each           = toset(var.runtime_service_account_names)
  service_account_id = each.value
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.ci.email}"
}
