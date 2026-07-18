output "id" {
  description = "Identifier of the Cloud Run service."
  value       = google_cloud_run_v2_service.this.id
}

output "name" {
  description = "Name of the Cloud Run service."
  value       = google_cloud_run_v2_service.this.name
}

output "uri" {
  description = "Public URI of the Cloud Run service."
  value       = google_cloud_run_v2_service.this.uri
}
