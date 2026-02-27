# ---------------------------------------------------------------------------
# Pocket ID OIDC identity provider for Cloudflare Zero Trust
#
# Prerequisites — complete these in Pocket ID before running terraform apply:
#   1. Create an OIDC client application in Pocket ID (Settings > OIDC Clients)
#   2. Set the redirect URI to the value of the `callback_url` output:
#        https://<team_name>.cloudflareaccess.com/cdn-cgi/access/callback
#   3. Copy the generated Client ID and Client Secret into terraform.tfvars
#
# After apply, Cloudflare will appear as a login method under
#   Zero Trust → Settings → Authentication → Login Methods.
# ---------------------------------------------------------------------------
resource "cloudflare_zero_trust_access_identity_provider" "pocket_id" {
  account_id = var.cloudflare_account_id
  name       = var.identity_provider_name
  type       = "oidc"

  config {
    client_id     = var.client_id
    client_secret = var.client_secret

    # Pocket ID OIDC endpoints (relative to the app base URL)
    auth_url  = "${var.pocket_id_app_url}/authorize"
    token_url = "${var.pocket_id_app_url}/api/oidc/token"
    certs_url = "${var.pocket_id_app_url}/.well-known/jwks.json"

    # openid is required; profile + email populate user identity fields in Access
    scopes = ["openid", "profile", "email", "groups"]

    # PKCE (Proof Key for Code Exchange) — recommended for all OIDC flows
    pkce_enabled = true
  }
}
