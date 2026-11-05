terraform {
  required_version = ">= 1.5"

  required_providers {
    # Floor: deletion_protection on google_cloud_run_v2_service was added in
    # 6.0.0. Ceiling: tested against 8.x; 9.0 has not been vetted.
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0, < 9.0"
    }
  }
}
