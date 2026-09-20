output "backend_https_url" {
  value = module.environment.backend_https_url
}

output "frontend_https_url" {
  value = module.environment.frontend_https_url
}

output "backend_url" {
  description = "Raw *.run.app URL — do not use for VITE_API_BASE_URL, see backend_https_url."
  value       = module.environment.backend_url
}

output "frontend_url" {
  value = module.environment.frontend_url
}

output "dns_records_needed" {
  value = module.environment.dns_records_needed
}

output "artifact_registry_repository" {
  value = module.environment.artifact_registry_repository
}

output "uploads_bucket" {
  value = module.environment.uploads_bucket
}

output "neon_connection_uri" {
  value     = module.environment.neon_connection_uri
  sensitive = true
}
