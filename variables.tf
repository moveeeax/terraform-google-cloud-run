variable "project_id" {
  description = "ID of the project in which to create the Cloud Run service."
  type        = string
}

variable "name" {
  description = "Name of the Cloud Run service."
  type        = string
}

variable "location" {
  description = "Region in which to deploy the Cloud Run service."
  type        = string
}

variable "image" {
  description = "Container image to deploy."
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "port" {
  description = "Container port the service listens on."
  type        = number
  default     = 8080
}

variable "cpu" {
  description = "CPU limit for the container, e.g. \"1\" or \"1000m\"."
  type        = string
  default     = "1"
}

variable "memory" {
  description = "Memory limit for the container, e.g. \"512Mi\"."
  type        = string
  default     = "512Mi"
}

variable "service_account" {
  description = <<-EOT
    Email of the service account the container runs as. When left null, Cloud Run falls
    back to the Compute Engine default service account, which holds `roles/editor` on
    the entire project — set `allow_default_service_account = true` to accept that.
    Prefer a dedicated service account granted only the roles this service needs.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.service_account == null || can(regex("^[a-z0-9-]+@[a-z0-9.-]+\\.gserviceaccount\\.com$", var.service_account))
    error_message = "service_account must be a service account email address, e.g. \"run-api@my-project.iam.gserviceaccount.com\"."
  }
}

variable "allow_default_service_account" {
  description = <<-EOT
    Allow the service to run as the Compute Engine default service account by leaving
    `service_account` unset. That account has `roles/editor` on the project, so any code
    running in the container can read and modify almost every resource in it. Leave
    `false` unless you have deliberately accepted that blast radius.
  EOT
  type        = bool
  default     = false
}

variable "ingress" {
  description = <<-EOT
    Which network traffic may reach the service. `INGRESS_TRAFFIC_ALL` accepts requests
    from the internet (they still need `roles/run.invoker` unless the service is public),
    `INGRESS_TRAFFIC_INTERNAL_ONLY` accepts only VPC and internal traffic, and
    `INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER` additionally accepts traffic from an
    external Application Load Balancer.
  EOT
  type        = string
  default     = "INGRESS_TRAFFIC_ALL"

  validation {
    condition = contains([
      "INGRESS_TRAFFIC_ALL",
      "INGRESS_TRAFFIC_INTERNAL_ONLY",
      "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER",
    ], var.ingress)
    error_message = "ingress must be one of INGRESS_TRAFFIC_ALL, INGRESS_TRAFFIC_INTERNAL_ONLY or INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER."
  }
}

variable "min_instance_count" {
  description = "Minimum number of container instances."
  type        = number
  default     = 0

  validation {
    condition     = var.min_instance_count >= 0
    error_message = "min_instance_count must not be negative."
  }
}

variable "max_instance_count" {
  description = "Maximum number of container instances."
  type        = number
  default     = 100

  validation {
    condition     = var.max_instance_count >= 1
    error_message = "max_instance_count must be at least 1."
  }
}

variable "env" {
  description = <<-EOT
    Plain-text environment variables passed to the container. These values are stored in
    the service spec and in Terraform state in clear text and are readable by anyone with
    view access to either. Use `secret_env` for credentials, tokens and keys.
  EOT
  type        = map(string)
  default     = {}
}

variable "secret_env" {
  description = <<-EOT
    Environment variables sourced from Secret Manager, keyed by variable name. `secret`
    is the secret ID (or a full `projects/<project>/secrets/<id>` path) and `version`
    defaults to `"latest"`. Cloud Run resolves these at runtime, so the value never
    reaches the service spec or Terraform state. The service's runtime service account
    needs `roles/secretmanager.secretAccessor` on each secret.
  EOT
  type = map(object({
    secret  = string
    version = optional(string, "latest")
  }))
  default = {}
}

variable "allow_unauthenticated" {
  description = <<-EOT
    Grant `roles/run.invoker` to `allUsers`, which puts the service on the open internet
    with no authentication at all. Leave `false` and use `invokers` to name the
    principals that may call the service unless it is deliberately a public endpoint.
  EOT
  type        = bool
  default     = false
}

variable "invokers" {
  description = <<-EOT
    IAM principals granted `roles/run.invoker` on the service, e.g.
    `["serviceAccount:frontend@my-project.iam.gserviceaccount.com"]`. `allUsers` and
    `allAuthenticatedUsers` are rejected here unless `allow_unauthenticated = true`.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for member in var.invokers :
      contains(["allUsers", "allAuthenticatedUsers"], member) ||
      can(regex("^(user|serviceAccount|group|domain|principal|principalSet|principalHierarchy|deleted):.+$", member))
    ])
    error_message = "Every entry of `invokers` must be a fully qualified IAM principal identifier, e.g. \"user:alice@example.com\", \"group:team@example.com\" or \"serviceAccount:app@<project>.iam.gserviceaccount.com\". A bare email address is not a valid member."
  }
}

variable "labels" {
  description = "Labels applied to the service."
  type        = map(string)
  default     = {}
}
