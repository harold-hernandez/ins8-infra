output "backend_url" {
  description = "The backend's raw *.run.app URL. Bake this (with /api/v1 appended) into the frontend's VITE_API_BASE_URL at build time."
  value       = module.backend.uri
}

output "artifact_registry_repository" {
  description = "Push images here, e.g. <this>/backend:<tag> or <this>/migrate:<tag>."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.app.repository_id}"
}

output "neon_connection_uri" {
  value     = neon_project.this.connection_uri
  sensitive = true
}

output "uploads_bucket" {
  value = google_storage_bucket.uploads.name
}

output "migrate_job_name" {
  value = google_cloud_run_v2_job.migrate.name
}

output "ci_service_account" {
  value = module.ci.service_account_email
}

output "workload_identity_provider" {
  value = module.ci.workload_identity_provider
}
