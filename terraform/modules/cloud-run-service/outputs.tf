output "uri" {
  description = "HTTPS URL Cloud Run assigned to the service. Stable across image deploys."
  value       = google_cloud_run_v2_service.this.uri
}

output "name" {
  value = google_cloud_run_v2_service.this.name
}
