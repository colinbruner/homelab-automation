# ---------------------------------------------------------------------------
# Grafana connection
# ---------------------------------------------------------------------------

variable "grafana_url" {
  description = "Root URL of the Grafana instance, e.g. https://grafana-internal.colinbruner.com"
  type        = string
}

variable "grafana_auth" {
  description = "Grafana authentication — service account token (glsa_...), API key, or username:password"
  type        = string
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Pocket ID OAuth
# ---------------------------------------------------------------------------

variable "pocket_id_app_url" {
  description = "Base URL of the Pocket ID instance, e.g. https://auth.colinbruner.com (no trailing slash)"
  type        = string
}

variable "grafana_client_id" {
  description = "OIDC client ID from the Pocket ID application created for Grafana"
  type        = string
}

variable "grafana_client_secret" {
  description = "OIDC client secret from the Pocket ID application created for Grafana"
  type        = string
  sensitive   = true
}

variable "oauth_provider_name" {
  description = "Display name shown on the Grafana login button"
  type        = string
  default     = "Pocket ID"
}

variable "role_attribute_path" {
  description = <<-EOT
    JMESPath expression evaluated against the Pocket ID UserInfo response to
    determine the Grafana role. Groups are returned as a string array in the
    `groups` claim. Adjust the group names to match those in your Pocket ID.
    Default: Admin if in 'grafana-admin', Editor if in 'grafana-editor', else Viewer.
  EOT
  type        = string
  default     = "contains(groups[*], 'grafana-admin') && 'Admin' || contains(groups[*], 'grafana-editor') && 'Editor' || 'Viewer'"
}

# ---------------------------------------------------------------------------
# GCP Cloud Logging data source
# ---------------------------------------------------------------------------

variable "gcp_project_id" {
  description = "GCP project ID to query logs from"
  type        = string
}

variable "gcp_service_account_email" {
  description = "Email of the GCP service account with roles/logging.viewer — from the downloaded JSON key's `client_email` field"
  type        = string
}

variable "gcp_service_account_private_key" {
  description = "PEM-encoded private key for the GCP service account — the `private_key` field from the downloaded JSON key file"
  type        = string
  sensitive   = true
}
