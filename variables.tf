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

variable "min_instance_count" {
  description = "Minimum number of container instances."
  type        = number
  default     = 0
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
  description = "Environment variables passed to the container."
  type        = map(string)
  default     = {}
}

variable "allow_unauthenticated" {
  description = "Whether to allow public unauthenticated invocations."
  type        = bool
  default     = false
}

variable "labels" {
  description = "Labels applied to the service."
  type        = map(string)
  default     = {}
}
