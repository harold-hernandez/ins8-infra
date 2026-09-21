variable "project_id" {
  type    = string
  default = "ins8-tasks"
}

variable "region" {
  type    = string
  default = "us-east4"
}

variable "backend_image" {
  description = "Defaults to a placeholder so the first `terraform apply` succeeds before CI has pushed a real one — see the root README's apply order."
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "migrate_image" {
  type    = string
  default = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "frontend_url" {
  description = "The frontend's raw *.run.app URL, for CORS_ALLOWED_ORIGINS — `terraform output -raw frontend_url` from envs/ins8-frontend, once that env has been applied at least once. No safe default: an empty CORS origin isn't meaningfully different from a wrong one, so this forces you to actually go get the real value."
  type        = string
}

variable "extra_cors_origins" {
  type    = list(string)
  default = []
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

variable "backend_cpu" {
  type    = string
  default = "1"
}

variable "backend_memory" {
  type    = string
  default = "512Mi"
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
  description = "\"owner/repo\" for this backend, e.g. \"harold-hernandez/ins8-tasks\"."
  type        = string
  default     = "harold-hernandez/ins8-tasks"
}

variable "ci_deploy_branch" {
  type    = string
  default = "main"
}
