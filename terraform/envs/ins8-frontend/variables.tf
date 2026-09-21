variable "project_id" {
  type    = string
  default = "ins8-frontend"
}

variable "region" {
  type    = string
  default = "us-east4"
}

variable "frontend_image" {
  description = "Defaults to a placeholder so the first `terraform apply` succeeds before CI has pushed a real one — see the root README's apply order."
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "min_instances" {
  type    = number
  default = 0
}

variable "max_instances" {
  type    = number
  default = 2
}

variable "github_repository" {
  description = "\"owner/repo\" for this frontend, e.g. \"harold-hernandez/ins8-frontend\"."
  type        = string
  default     = "harold-hernandez/ins8-frontend"
}

variable "ci_deploy_branch" {
  type    = string
  default = "main"
}
