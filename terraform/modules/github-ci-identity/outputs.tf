output "service_account_email" {
  description = "Pass to the repo's workflow as google-github-actions/auth's `service_account` input."
  value       = google_service_account.ci.email
}

output "workload_identity_provider" {
  description = "Pass to the repo's workflow as google-github-actions/auth's `workload_identity_provider` input."
  value       = google_iam_workload_identity_pool_provider.github.name
}
