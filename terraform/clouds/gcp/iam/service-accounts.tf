###
# Logging Viewer service account
###
resource "google_service_account" "grafana_gcp_logs_viewer" {
  project      = var.project_id
  account_id   = "svc-grafana-logs-viewer"
  display_name = "Grafana GCP Logs Viewer Service Account"
}

resource "google_project_iam_member" "grafana_gcp_logs_viewer" {
  project = var.project_id
  role    = "roles/logging.viewer"
  member  = "serviceAccount:${google_service_account.grafana_gcp_logs_viewer.email}"
}

resource "google_service_account_key" "grafana_gcp_logs_viewer" {
  service_account_id = google_service_account.grafana_gcp_logs_viewer.name
}
