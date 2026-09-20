variable "project_id" {
  description = "GCP project ID for prod, e.g. seedtech-prod."
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

# Same WIF trust setup as staging (see modules/environment/ci.tf) so this
# environment's config stays structurally complete even though no CI
# pipeline deploys to prod yet — see the root README. ci_deploy_branch has
# no safe default here on purpose (see modules/environment/variables.tf):
# pick a real value only once a prod deploy pipeline actually exists, rather
# than reusing "main" and accidentally letting every staging merge assume
# this environment's deploy identity too.

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

variable "ci_deploy_branch" {
  description = "Branch (or tag pattern, once a real release process exists) allowed to deploy prod. Not \"main\" — see comment above."
  type        = string
}
