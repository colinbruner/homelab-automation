# ---------------------------------------------------------------------------
# Generic OAuth via Pocket ID
#
# Prerequisites — complete in Pocket ID before running terraform apply:
#   1. Create an OIDC client in Pocket ID (Settings → OIDC Clients)
#   2. Set the redirect URI to the `oauth_redirect_uri` output:
#        https://<grafana-hostname>/login/generic_oauth
#   3. Copy the Client ID and Client Secret into terraform.tfvars
#
# Pocket ID groups → Grafana roles:
#   The role_attribute_path variable controls which Pocket ID group names
#   map to Admin / Editor. Anyone authenticated but not in those groups
#   gets Viewer. Adjust the group names to match what you create in Pocket ID.
# ---------------------------------------------------------------------------
resource "grafana_sso_settings" "pocket_id" {
  provider_name = "generic_oauth"

  oauth2_settings {
    name          = var.oauth_provider_name
    client_id     = var.grafana_client_id
    client_secret = var.grafana_client_secret

    # Pocket ID OIDC endpoints
    auth_url    = "${var.pocket_id_app_url}/authorize"
    token_url   = "${var.pocket_id_app_url}/api/oidc/token"
    api_url     = "${var.pocket_id_app_url}/api/oidc/userinfo"
    jwk_set_url = "${var.pocket_id_app_url}/.well-known/jwks.json"

    # groups scope is required for role_attribute_path group lookups
    scopes = "openid profile email groups"

    enabled           = true
    allow_sign_up     = true
    auto_login        = false
    use_pkce          = true
    use_refresh_token = true
    validate_id_token = true

    # JMESPath expression evaluated against the UserInfo response.
    # Groups are returned as a string array in the `groups` claim.
    role_attribute_path = var.role_attribute_path

    # Standard OIDC claim mappings
    login_attribute_path = "preferred_username"
    name_attribute_path  = "name"
    email_attribute_path = "email"
  }
}
