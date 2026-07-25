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

# A dedicated runtime service account. Grant it only what the container actually needs.
# Without it the service would run as the Compute Engine default service account, which
# holds roles/editor on the whole project.
resource "google_service_account" "run" {
  project      = var.project_id
  account_id   = "example-service-run"
  display_name = "Runtime service account for example-service"
}

module "cloud_run" {
  source = "../.."

  project_id      = var.project_id
  name            = "example-service"
  location        = var.region
  service_account = google_service_account.run.email

  env = {
    GREETING = "hello"
  }

  # Authenticated callers only. Pass allow_unauthenticated = true instead to publish the
  # service to the internet with no authentication.
  invokers = var.invokers
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

variable "invokers" {
  description = "IAM principals allowed to invoke the example service, e.g. [\"user:alice@example.com\"]."
  type        = list(string)
  default     = []
}

output "service_uri" {
  value = module.cloud_run.uri
}
