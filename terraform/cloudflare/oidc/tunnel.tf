# ---------------------------------------------------------------------------
# Homelab Cloudflare Tunnel
#
# A single cloudflared agent running in the homelab connects outbound to
# Cloudflare and serves traffic for all homelab-hosted services. No inbound
# firewall rules or public IPs are required.
#
# After apply, deploy cloudflared in the homelab using the tunnel_token output:
#   docker run cloudflare/cloudflared:latest tunnel run --token <token>
# ---------------------------------------------------------------------------
resource "random_id" "homelab_tunnel_secret" {
  byte_length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "homelab" {
  account_id = var.cloudflare_account_id
  name       = "homelab"
  secret     = random_id.homelab_tunnel_secret.b64_std
}

# ---------------------------------------------------------------------------
# Tunnel ingress rules
#
# Public hostnames (prometheus, grafana) are protected by Cloudflare Access
# (see access.tf). Internal hostnames (*-internal) bypass Access and are
# reachable only via WARP-connected clients — WARP enforces network-level
# access control so no additional auth layer is needed for service-to-service
# or internal tooling use cases.
# ---------------------------------------------------------------------------
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "homelab" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.homelab.id

  config {
    # Prometheus — public (Access-protected) and internal (WARP-only)
    ingress_rule {
      hostname = "prometheus.${var.cloudflare_domain}"
      service  = var.prometheus_service_url
    }

    # Grafana — public (Access-protected) and internal (WARP-only)
    ingress_rule {
      hostname = "grafana.${var.cloudflare_domain}"
      service  = var.grafana_service_url
    }

    # Catch-all — return 404 for any unmatched hostname
    ingress_rule {
      service = "http_status:404"
    }
  }
}
