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

variable "bitbucket_workspace" {
  description = "Bitbucket workspace slug, e.g. \"seedtech-software\"."
  type        = string
}

variable "bitbucket_workspace_uuid" {
  description = "Bitbucket workspace UUID, with braces. Repository Settings -> OpenID Connect on either repo shows it."
  type        = string
}

variable "backend_repository_uuid" {
  description = "Bitbucket repository UUID for `tasks`, with braces."
  type        = string
}

variable "frontend_repository_uuid" {
  description = "Bitbucket repository UUID for `ins8-frontend`, with braces."
  type        = string
}

variable "migrate_image" {
  type    = string
  default = "us-docker.pkg.dev/cloudrun/container/hello"
}
