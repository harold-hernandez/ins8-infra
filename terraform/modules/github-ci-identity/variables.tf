variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "name_prefix" {
  description = "Short name for resource naming, e.g. \"ins8-frontend\"."
  type        = string
}

variable "repository" {
  description = "\"owner/repo\" this identity is trusted for, e.g. \"harold-hernandez/ins8-frontend\"."
  type        = string
}

variable "ci_deploy_branch" {
  type    = string
  default = "main"
}

variable "artifact_registry_repository_id" {
  type = string
}

variable "cloud_run_service_names" {
  description = "Cloud Run service names (not full resource paths) this identity can deploy to."
  type        = list(string)
  default     = []
}

variable "cloud_run_job_names" {
  description = "Cloud Run job names (not full resource paths) this identity can execute/update."
  type        = list(string)
  default     = []
}

variable "runtime_service_account_names" {
  description = "Full resource names (google_service_account.<x>.name, not email) of runtime service accounts this identity needs roles/iam.serviceAccountUser on, to deploy revisions/jobs running as them."
  type        = list(string)
  default     = []
}
