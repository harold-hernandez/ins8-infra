variable "project_id" {
  description = "GCP project ID for staging, e.g. seedtech-staging."
  type        = string
}

variable "region" {
  type    = string
  default = "us-east4"
}

variable "domain" {
  description = "Registrable domain you own, e.g. \"seedtech.dev\". See modules/environment/variables.tf for why this is required."
  type        = string
}

variable "backend_image" {
  type    = string
  default = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "frontend_image" {
  type    = string
  default = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "extra_cors_origins" {
  type    = list(string)
  default = []
}

variable "github_owner" {
  description = "GitHub account or org that owns both repos, e.g. \"harold-hernandez\"."
  type        = string
}

variable "backend_repository" {
  description = "\"owner/repo\" for the backend, e.g. \"harold-hernandez/ins8-tasks\"."
  type        = string
}

variable "frontend_repository" {
  description = "\"owner/repo\" for the frontend, e.g. \"harold-hernandez/ins8-frontend\"."
  type        = string
}

variable "migrate_image" {
  type    = string
  default = "us-docker.pkg.dev/cloudrun/container/hello"
}
