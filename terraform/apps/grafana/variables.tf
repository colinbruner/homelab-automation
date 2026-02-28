# ---------------------------------------------------------------------------
# Grafana connection
# ---------------------------------------------------------------------------

variable "grafana_url" {
  description = "Root URL of the Grafana instance"
  default     = "https://grafana-internal.colinbruner.com"
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
  description = "Base URL of the Pocket ID instance"
  default     = "https://auth.colinbruner.com"
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
  default     = "Authenticate"
}

variable "role_attribute_path" {
  description = <<-EOT
    JMESPath expression evaluated against the Pocket ID UserInfo response to
    determine the Grafana role. Groups are returned as a string array in the
    `groups` claim. Adjust the group names to match those in your Pocket ID.
    Default: Admin if in 'admin', Editor if in 'grafana-editor', else Viewer.
  EOT
  type        = string
  default     = "contains(groups[*], 'admin') && 'Admin' || contains(groups[*], 'grafana-editor') && 'Editor' || 'Viewer'"
}

# ---------------------------------------------------------------------------
# GCP Cloud Logging data source
# ---------------------------------------------------------------------------

variable "gcp_project_id" {
  description = "GCP project ID to query logs from"
  type        = string
}
