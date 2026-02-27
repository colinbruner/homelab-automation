output "identity_provider_id" {
  description = "Cloudflare Zero Trust identity provider ID — reference this when creating Access applications or policies that use Pocket ID for authentication"
  value       = cloudflare_zero_trust_access_identity_provider.pocket_id.id
}

output "identity_provider_name" {
  description = "Display name of the identity provider in Cloudflare Zero Trust"
  value       = cloudflare_zero_trust_access_identity_provider.pocket_id.name
}

output "callback_url" {
  description = "Redirect URI — set this as the redirect URI on the Pocket ID OIDC client before running terraform apply"
  value       = "https://${var.cloudflare_team_name}.cloudflareaccess.com/cdn-cgi/access/callback"
}

# ---------------------------------------------------------------------------
# Homelab tunnel
# ---------------------------------------------------------------------------

output "homelab_tunnel_id" {
  description = "Homelab Cloudflare Tunnel ID"
  value       = cloudflare_zero_trust_tunnel_cloudflared.homelab.id
}

output "homelab_tunnel_token" {
  description = "Homelab tunnel token — pass to cloudflared: tunnel run --token <token>"
  value       = cloudflare_zero_trust_tunnel_cloudflared.homelab.tunnel_token
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Access applications
# ---------------------------------------------------------------------------

output "prometheus_url" {
  description = "Public URL for Prometheus (Access-protected)"
  value       = "https://prometheus.${var.cloudflare_domain}"
}

output "grafana_url" {
  description = "Public URL for Grafana (Access-protected)"
  value       = "https://grafana.${var.cloudflare_domain}"
}

output "prometheus_access_application_id" {
  description = "Cloudflare Access application ID for Prometheus"
  value       = cloudflare_zero_trust_access_application.prometheus.id
}

output "grafana_access_application_id" {
  description = "Cloudflare Access application ID for Grafana"
  value       = cloudflare_zero_trust_access_application.grafana.id
}
