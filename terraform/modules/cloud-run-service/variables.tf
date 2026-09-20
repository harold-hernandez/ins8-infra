variable "project_id" {
  description = "GCP project the service is deployed into."
  type        = string
}

variable "region" {
  description = "GCP region, e.g. us-east4."
  type        = string
}

variable "name" {
  description = "Cloud Run service name."
  type        = string
}

variable "image" {
  description = "Container image to deploy. Ignored on later applies (see lifecycle block) so CI can update it with `gcloud run deploy` without Terraform reverting it."
  type        = string
}

variable "service_account_email" {
  description = "Runtime service account for the revision."
  type        = string
}

variable "container_port" {
  description = "Port the container listens on. Cloud Run injects PORT with this value at runtime."
  type        = number
  default     = 8080
}

variable "cpu" {
  type    = string
  default = "1"
}

variable "memory" {
  type    = string
  default = "512Mi"
}

variable "min_instance_count" {
  type    = number
  default = 0
}

variable "max_instance_count" {
  type    = number
  default = 2
}

variable "allow_unauthenticated" {
  description = "Whether to grant roles/run.invoker to allUsers. Needed for anything called directly by a browser (this app has no separate API gateway/auth proxy in front of Cloud Run — app-level auth is the JWT cookie, not Cloud Run IAM)."
  type        = bool
  default     = true
}

variable "env" {
  description = "Plain (non-secret) environment variables."
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "secret_env" {
  description = "Environment variables sourced from Secret Manager."
  type = list(object({
    name      = string
    secret_id = string
    version   = optional(string, "latest")
  }))
  default = []
}

variable "gcs_volumes" {
  description = "GCS buckets to mount into the container via Cloud Run's built-in Cloud Storage FUSE volume support."
  type = list(object({
    name       = string
    bucket     = string
    mount_path = string
    read_only  = optional(bool, false)
  }))
  default = []
}
