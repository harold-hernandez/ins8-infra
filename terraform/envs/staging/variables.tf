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
