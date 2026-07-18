terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

module "cloud_run" {
  source = "../.."

  project_id            = var.project_id
  name                  = "example-service"
  location              = var.region
  allow_unauthenticated = true

  env = {
    GREETING = "hello"
  }
}

variable "project_id" {
  description = "Project ID to deploy the example Cloud Run service into."
  type        = string
}

variable "region" {
  description = "Region for the google provider and service."
  type        = string
  default     = "us-central1"
}

output "service_uri" {
  value = module.cloud_run.uri
}
