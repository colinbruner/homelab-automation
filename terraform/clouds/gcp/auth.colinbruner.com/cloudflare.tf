provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# ---------------------------------------------------------------------------
# Tunnel secret — 32 random bytes, base64-encoded (Cloudflare requirement)
# ---------------------------------------------------------------------------
resource "random_id" "tunnel_secret" {
  byte_length = 32
}

# ---------------------------------------------------------------------------
# Cloudflare Tunnel
# Creates a named tunnel scoped to your account. The VM connects outbound
# using tunnel_token — no inbound firewall rules or public IP needed.
# ---------------------------------------------------------------------------
resource "cloudflare_zero_trust_tunnel_cloudflared" "auth_colinbruner" {
  account_id = var.cloudflare_account_id
  name       = "auth-colinbruner-tunnel"
  secret     = random_id.tunnel_secret.b64_std
}

# ---------------------------------------------------------------------------
# Tunnel ingress configuration
# Routes id.example.com → localhost:1411 (Pocket ID's default port)
# Catch-all returns 404 for any unmatched hostname.
# ---------------------------------------------------------------------------
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "auth_colinbruner" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.auth_colinbruner.id

  config {
    ingress_rule {
      hostname = var.cloudflare_tunnel_hostname
      service  = "http://localhost:1411"
    }
    ingress_rule {
      service = "http_status:404"
    }
  }
}

# ---------------------------------------------------------------------------
# DNS record — CNAME pointing your subdomain at the tunnel
# Cloudflare proxies this (orange cloud), so the VM IP is never exposed.
# ---------------------------------------------------------------------------
resource "cloudflare_record" "pocket_id" {
  zone_id = var.cloudflare_zone_id
  name    = var.cloudflare_subdomain
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.auth_colinbruner.id}.cfargotunnel.com"
  proxied = true
}
