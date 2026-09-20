variable "project_id" {
  description = "GCP project for this environment (staging and prod each get their own project)."
  type        = string
}

variable "region" {
  description = "GCP region for Cloud Run and the uploads bucket, e.g. us-east4."
  type        = string
  default     = "us-east4"
}

variable "domain" {
  description = <<-EOT
    Registrable domain you own, e.g. "seedtech.dev". The frontend and backend
    are mapped to subdomains of it (app./api. for prod, app.<env>./api.<env>.
    for staging) so they're same-site for the SameSite=Lax session cookie —
    Cloud Run's default *.run.app URLs put every service on its own site
    (run.app is on the Public Suffix List), which breaks that cookie's
    cross-service delivery entirely. Must be verified in Google Search
    Console under the identity running Terraform before apply — see README.
  EOT
  type        = string
}

variable "environment" {
  description = "Short environment name, used for resource naming (e.g. \"staging\", \"prod\")."
  type        = string
  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be \"staging\" or \"prod\"."
  }
}

variable "app_env" {
  description = "Value of APP_ENV the backend receives. Controls internal/logging's JSON-vs-text handler — set to \"production\" for any real deployment (staging included), since staging should behave like production code-path-wise."
  type        = string
  default     = "production"
}

variable "backend_image" {
  description = "Backend container image. Defaults to a placeholder so the first `terraform apply` succeeds before any real image has been pushed; the service gets a stable URL that later `gcloud run deploy` calls (or a later terraform apply) then update in place."
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "frontend_image" {
  description = "Frontend container image. See backend_image for why the default is a placeholder."
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "artifact_registry_repository_id" {
  type    = string
  default = "app"
}

variable "neon_region_id" {
  description = "Neon region ID (see https://neon.tech/docs/introduction/regions). Pick one geographically close to `region` to minimize Cloud Run <-> Postgres latency."
  type        = string
  default     = "aws-us-east-2"
}

variable "neon_pg_version" {
  type    = number
  default = 16
}

variable "jwt_access_ttl" {
  type    = string
  default = "30m"
}

variable "extra_cors_origins" {
  description = "Additional origins to allow beyond the frontend's own Cloud Run URL, e.g. a custom domain once one is set up."
  type        = list(string)
  default     = []
}

variable "backend_cpu" {
  type    = string
  default = "1"
}

variable "backend_memory" {
  type    = string
  default = "512Mi"
}

variable "backend_min_instances" {
  type    = number
  default = 0
}

variable "backend_max_instances" {
  type    = number
  default = 2
}

variable "frontend_cpu" {
  type    = string
  default = "1"
}

variable "frontend_memory" {
  type    = string
  default = "512Mi"
}

variable "frontend_min_instances" {
  type    = number
  default = 0
}

variable "frontend_max_instances" {
  type    = number
  default = 2
}
