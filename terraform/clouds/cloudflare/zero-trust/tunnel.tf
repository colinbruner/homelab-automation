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
# Public hostnames are protected by Cloudflare Access (see access.tf).
# ---------------------------------------------------------------------------
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "homelab" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.homelab.id

  config {
    # Proxmox — Access-protected; HTTPS backend requires TLS verify disabled
    ingress_rule {
      hostname = "pve.${var.cloudflare_domain}"
      service  = var.proxmox_service_url

      origin_request {
        no_tls_verify = true
      }
    }

    # ArgoCD — Access-protected
    ingress_rule {
      hostname = "argocd.${var.cloudflare_domain}"
      service  = var.argocd_service_url

      origin_request {
        no_tls_verify = true
      }
    }

    # Dashboard — Access-protected
    ingress_rule {
      hostname = "dashboard.${var.cloudflare_domain}"
      service  = var.dashboard_service_url
    }

    # Catch-all — return 404 for any unmatched hostname
    ingress_rule {
      service = "http_status:404"
    }
  }
}
