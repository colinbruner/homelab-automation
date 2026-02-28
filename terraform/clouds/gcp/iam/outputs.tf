output "grafana_gcp_logs_viewer_email" {
  value = google_service_account.grafana_gcp_logs_viewer.email
}

output "grafana_gcp_logs_viewer_key" {
  sensitive = true
  value     = google_service_account_key.grafana_gcp_logs_viewer.private_key
}
