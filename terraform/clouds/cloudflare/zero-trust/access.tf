# ---------------------------------------------------------------------------
# DNS records
#
# All hostnames CNAME to the homelab tunnel — Cloudflare routes traffic
# to the cloudflared agent running in the homelab.
#
# Public hostnames  (pve, prometheus, grafana) — Access-protected
# Internal hostnames (prometheus-internal, grafana-internal) — WARP-only
# ---------------------------------------------------------------------------
resource "cloudflare_record" "proxmox" {
  zone_id = var.cloudflare_zone_id
  name    = "pve"
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.homelab.id}.cfargotunnel.com"
  proxied = true
}

resource "cloudflare_record" "argocd" {
  zone_id = var.cloudflare_zone_id
  name    = "argocd"
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.homelab.id}.cfargotunnel.com"
  proxied = true
}

resource "cloudflare_record" "prometheus" {
  zone_id = var.cloudflare_zone_id
  name    = "prometheus"
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.homelab.id}.cfargotunnel.com"
  proxied = true
}

resource "cloudflare_record" "grafana" {
  zone_id = var.cloudflare_zone_id
  name    = "grafana"
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.homelab.id}.cfargotunnel.com"
  proxied = true
}

resource "cloudflare_record" "dashboard" {
  zone_id = var.cloudflare_zone_id
  name    = "dashboard"
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.homelab.id}.cfargotunnel.com"
  proxied = true
}

# ---------------------------------------------------------------------------
# Access applications — protect public hostnames with Pocket ID authentication
#
# auto_redirect_to_identity skips the Cloudflare login page and sends users
# directly to Pocket ID since it is the only allowed identity provider.
# ---------------------------------------------------------------------------
resource "cloudflare_zero_trust_access_application" "proxmox" {
  account_id = var.cloudflare_account_id
  name       = "Proxmox"
  domain     = "pve.${var.cloudflare_domain}"
  type       = "self_hosted"

  session_duration          = var.session_duration
  allowed_idps              = [cloudflare_zero_trust_access_identity_provider.pocket_id.id]
  auto_redirect_to_identity = true
}

resource "cloudflare_zero_trust_access_application" "argocd" {
  account_id = var.cloudflare_account_id
  name       = "ArgoCD"
  domain     = "argocd.${var.cloudflare_domain}"
  type       = "self_hosted"

  session_duration          = var.session_duration
  allowed_idps              = [cloudflare_zero_trust_access_identity_provider.pocket_id.id]
  auto_redirect_to_identity = true
}

resource "cloudflare_zero_trust_access_application" "prometheus" {
  account_id = var.cloudflare_account_id
  name       = "Prometheus"
  domain     = "prometheus.${var.cloudflare_domain}"
  type       = "self_hosted"

  session_duration          = var.session_duration
  allowed_idps              = [cloudflare_zero_trust_access_identity_provider.pocket_id.id]
  auto_redirect_to_identity = true
}

resource "cloudflare_zero_trust_access_application" "grafana" {
  account_id = var.cloudflare_account_id
  name       = "Grafana"
  domain     = "grafana.${var.cloudflare_domain}"
  type       = "self_hosted"

  session_duration          = var.session_duration
  allowed_idps              = [cloudflare_zero_trust_access_identity_provider.pocket_id.id]
  auto_redirect_to_identity = true
}

resource "cloudflare_zero_trust_access_application" "dashboard" {
  account_id = var.cloudflare_account_id
  name       = "Dashboard"
  domain     = "dashboard.${var.cloudflare_domain}"
  type       = "self_hosted"

  session_duration          = var.session_duration
  allowed_idps              = [cloudflare_zero_trust_access_identity_provider.pocket_id.id]
  auto_redirect_to_identity = true
}

# ---------------------------------------------------------------------------
# Access policies — allow any user authenticated via Pocket ID
# ---------------------------------------------------------------------------
resource "cloudflare_zero_trust_access_policy" "proxmox" {
  account_id     = var.cloudflare_account_id
  application_id = cloudflare_zero_trust_access_application.proxmox.id
  name           = "Allow Pocket ID users"
  precedence     = 1
  decision       = "allow"

  include {
    login_method = [cloudflare_zero_trust_access_identity_provider.pocket_id.id]
  }
}

resource "cloudflare_zero_trust_access_policy" "argocd" {
  account_id     = var.cloudflare_account_id
  application_id = cloudflare_zero_trust_access_application.argocd.id
  name           = "Allow Pocket ID users"
  precedence     = 1
  decision       = "allow"

  include {
    login_method = [cloudflare_zero_trust_access_identity_provider.pocket_id.id]
  }
}

resource "cloudflare_zero_trust_access_policy" "prometheus" {
  account_id     = var.cloudflare_account_id
  application_id = cloudflare_zero_trust_access_application.prometheus.id
  name           = "Allow Pocket ID users"
  precedence     = 1
  decision       = "allow"

  include {
    login_method = [cloudflare_zero_trust_access_identity_provider.pocket_id.id]
  }
}

resource "cloudflare_zero_trust_access_policy" "grafana" {
  account_id     = var.cloudflare_account_id
  application_id = cloudflare_zero_trust_access_application.grafana.id
  name           = "Allow Pocket ID users"
  precedence     = 1
  decision       = "allow"

  include {
    login_method = [cloudflare_zero_trust_access_identity_provider.pocket_id.id]
  }
}

resource "cloudflare_zero_trust_access_policy" "dashboard" {
  account_id     = var.cloudflare_account_id
  application_id = cloudflare_zero_trust_access_application.dashboard.id
  name           = "Allow Pocket ID users"
  precedence     = 1
  decision       = "allow"

  include {
    login_method = [cloudflare_zero_trust_access_identity_provider.pocket_id.id]
  }
}
