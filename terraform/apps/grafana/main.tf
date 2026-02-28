terraform {
  required_version = ">= 1.5"

  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "~> 3.0"
    }
  }
}

# ---------------------------------------------------------------------------
# Grafana provider — connects to the self-hosted OSS instance.
#
# auth accepts any of:
#   - Service account token: "glsa_xxxxxxxxxxxxxxxxxxxx"
#   - API key (legacy):      "eyJr..."
#   - Basic auth:            "admin:password"
#
# Recommended: create a service account in Grafana (Administration →
# Service Accounts) with Admin role, generate a token, and use that.
# ---------------------------------------------------------------------------
provider "grafana" {
  url  = var.grafana_url
  auth = var.grafana_auth
}
