output "backend_url" {
  description = "Backend's raw *.run.app URL. Do NOT bake this into VITE_API_BASE_URL — use backend_https_url instead (see its description)."
  value       = module.backend.uri
}

output "frontend_url" {
  description = "Frontend's raw *.run.app URL."
  value       = module.frontend.uri
}

output "backend_https_url" {
  description = "Backend's custom-domain URL. Bake THIS (with /api/v1 appended) into the frontend's VITE_API_BASE_URL at build time — the raw *.run.app URL is cross-site from the frontend's custom domain and will silently drop the session cookie."
  value       = "https://${local.backend_hostname}"
}

output "frontend_https_url" {
  value = "https://${local.frontend_hostname}"
}

output "dns_records_needed" {
  description = "Add these records at your DNS provider once, per environment. Cloud Run won't finish provisioning the managed TLS cert (and the mapping stays in a pending state) until they resolve."
  value = {
    frontend = google_cloud_run_domain_mapping.frontend.status[0].resource_records
    backend  = google_cloud_run_domain_mapping.backend.status[0].resource_records
  }
}

output "artifact_registry_repository" {
  description = "Push images here, e.g. <region>-docker.pkg.dev/<project>/<repo>/backend:<tag>."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.app.repository_id}"
}

output "neon_connection_uri" {
  value     = neon_project.this.connection_uri
  sensitive = true
}

output "uploads_bucket" {
  value = google_storage_bucket.uploads.name
}

output "ci_backend_service_account" {
  description = "Pass to the backend repo's workflow as google-github-actions/auth's `service_account` input."
  value       = google_service_account.ci_backend.email
}

output "ci_frontend_service_account" {
  description = "Pass to the frontend repo's workflow as google-github-actions/auth's `service_account` input."
  value       = google_service_account.ci_frontend.email
}

output "workload_identity_provider" {
  description = "Full provider resource name — pass to both workflows as google-github-actions/auth's `workload_identity_provider` input."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "migrate_job_name" {
  value = google_cloud_run_v2_job.migrate.name
}
