# ---------------------------------------------------------------------------
# GCP
# ---------------------------------------------------------------------------

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region — must be us-east1, us-west1, or us-central1 to qualify for free-tier e2-micro"
  type        = string
  default     = "us-central1"

  validation {
    condition     = contains(["us-east1", "us-west1", "us-central1"], var.region)
    error_message = "Region must be us-east1, us-west1, or us-central1 to qualify for the GCP free tier."
  }
}

variable "zone" {
  description = "GCP zone within the chosen region"
  type        = string
  default     = "us-central1-a"
}

variable "iap_user" {
  description = "Google account (user:email) granted IAP tunnel access for SSH, e.g. user:you@gmail.com"
  type        = string
}

# ---------------------------------------------------------------------------
# Pocket ID
# ---------------------------------------------------------------------------

variable "pocket_id_version" {
  description = "Pocket ID Docker image tag (ghcr.io/pocket-id/pocket-id)"
  type        = string
  default     = "latest"
}

variable "pocket_id_app_url" {
  description = "Public URL Pocket ID is reachable at, e.g. https://id.example.com — used as OIDC issuer"
  type        = string
}

# ---------------------------------------------------------------------------
# Cloudflare
# ---------------------------------------------------------------------------

variable "cloudflare_api_token" {
  description = "Cloudflare API token — needs Zone:DNS:Edit and Account:Cloudflare Tunnel:Edit permissions"
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID (found in the dashboard sidebar URL or Overview page)"
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for the domain hosting Pocket ID"
  type        = string
}

variable "cloudflare_subdomain" {
  description = "DNS subdomain for Pocket ID, e.g. 'id' for id.example.com (relative name, not FQDN)"
  type        = string
  default     = "id"
}

variable "cloudflare_tunnel_hostname" {
  description = "Full hostname the tunnel serves, e.g. id.example.com — must match pocket_id_app_url domain"
  type        = string
}
