resource "supabase_project" "home" {
  name              = "home"
  organization_id   = var.organization_id
  database_password = var.database_password
  region            = var.region

  lifecycle {
    ignore_changes = [database_password]
  }
}

# Auth settings: enable external OIDC provider (Pocket ID) and disable
# Supabase's built-in email/password auth since the app uses PKCE + OIDC.
resource "supabase_settings" "home" {
  project_ref = supabase_project.home.id

  auth = jsonencode({
    site_url                  = "https://home.bruner.family"
    additional_redirect_urls  = []
    jwt_expiry                = 3600
    enable_signup             = true
    enable_anonymous_sign_ins = false

    # Disable email/password — auth handled by OIDC (Pocket ID)
    mailer_autoconfirm     = false
    external_email_enabled = false

    # External OIDC provider (Pocket ID)
    external_oidc_enabled    = var.oidc_issuer_url != ""
    external_oidc_issuer_url = var.oidc_issuer_url
    external_oidc_client_id  = var.oidc_client_id
    external_oidc_secret     = var.oidc_secret
  })
}
