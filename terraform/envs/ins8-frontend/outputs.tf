output "frontend_url" {
  description = "The frontend's raw *.run.app URL. Needed by envs/ins8-tasks' frontend_url variable for CORS_ALLOWED_ORIGINS — apply this env first."
  value       = module.frontend.uri
}

output "artifact_registry_repository" {
  description = "Push images here, e.g. <this>/frontend:<tag>."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.app.repository_id}"
}

output "ci_service_account" {
  value = module.ci.service_account_email
}

output "workload_identity_provider" {
  value = module.ci.workload_identity_provider
}
