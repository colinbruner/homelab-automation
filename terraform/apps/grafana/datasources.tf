# ---------------------------------------------------------------------------
# GCP Cloud Logging data source
#
# Plugin requirement: the `googlecloud-logging-datasource` plugin must be
# installed in Grafana before this resource is applied. Add it to your
# Grafana deployment:
#   - Docker:      -e GF_INSTALL_PLUGINS=googlecloud-logging-datasource
#   - Helm values: plugins: ["googlecloud-logging-datasource"]
#   - grafana.ini: [plugins] / install_plugins = googlecloud-logging-datasource
#
# GCP prerequisites:
#   1. Create a service account in the GCP project
#   2. Grant it the "Logs Viewer" role (roles/logging.viewer)
#   3. Create and download a JSON key for the service account
#   4. Set gcp_service_account_email to the SA's email address
#   5. Set gcp_service_account_private_key to the `private_key` field from
#      the downloaded JSON (the PEM block including header/footer lines)
# ---------------------------------------------------------------------------
resource "grafana_data_source" "gcp_logging" {
  type = "googlecloud-logging-datasource"
  name = "GCP Cloud Logging"

  json_data_encoded = jsonencode({
    authenticationType = "jwt"
    defaultProject     = var.gcp_project_id
    clientEmail        = var.gcp_service_account_email
    tokenUri           = "https://oauth2.googleapis.com/token"
  })

  secure_json_data_encoded = jsonencode({
    # The private_key value from the GCP service account JSON key file.
    # Include the full PEM block with -----BEGIN/END RSA PRIVATE KEY----- lines.
    privateKey = var.gcp_service_account_private_key
  })
}
