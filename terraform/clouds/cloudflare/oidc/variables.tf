# ---------------------------------------------------------------------------
# Cloudflare
# ---------------------------------------------------------------------------

variable "cloudflare_api_token" {
  description = "Cloudflare API token — requires Account:Zero Trust:Edit permission"
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID (found in the dashboard sidebar or overview page URL)"
  type        = string
}

variable "cloudflare_team_name" {
  description = "Cloudflare Zero Trust team/organization name — the subdomain of <team>.cloudflareaccess.com (used to derive the OIDC callback URL)"
  type        = string
}

# ---------------------------------------------------------------------------
# Pocket ID
# ---------------------------------------------------------------------------

variable "pocket_id_app_url" {
  description = "Base URL of your Pocket ID instance, e.g. https://auth.colinbruner.com (no trailing slash)"
  type        = string
}

variable "client_id" {
  description = "OIDC client ID from the Pocket ID application (Settings > OIDC Clients)"
  type        = string
}

variable "client_secret" {
  description = "OIDC client secret from the Pocket ID application"
  type        = string
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Identity provider
# ---------------------------------------------------------------------------

variable "identity_provider_name" {
  description = "Display name shown on the Cloudflare Zero Trust login page"
  type        = string
  default     = "Home Auth"
}

# ---------------------------------------------------------------------------
# DNS / domain
# ---------------------------------------------------------------------------

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for the domain (found in the zone overview page)"
  type        = string
}

variable "cloudflare_domain" {
  description = "Root domain managed in Cloudflare, e.g. colinbruner.com — used to construct hostnames"
  type        = string
}

# ---------------------------------------------------------------------------
# Homelab services
# ---------------------------------------------------------------------------

variable "prometheus_service_url" {
  description = "Internal URL cloudflared uses to reach Prometheus, e.g. http://192.168.10.x:9090"
  type        = string
}

variable "grafana_service_url" {
  description = "Internal URL cloudflared uses to reach Grafana, e.g. http://192.168.10.x:3000"
  type        = string
}

variable "session_duration" {
  description = "Cloudflare Access session duration before re-authentication is required"
  type        = string
  default     = "24h"
}
