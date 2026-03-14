variable "access_token" {
  description = "Supabase management API access token (https://supabase.com/dashboard/account/tokens)"
  type        = string
  sensitive   = true
}

variable "organization_id" {
  description = "Supabase organization ID to create the project under"
  type        = string
}

variable "database_password" {
  description = "Password for the Supabase project database"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "Supabase project region"
  type        = string
  default     = "us-west-2"
}

variable "oidc_issuer_url" {
  description = "OIDC issuer URL for external auth provider (Pocket ID)"
  type        = string
  default     = ""
}

variable "oidc_client_id" {
  description = "OIDC client ID registered with Pocket ID"
  type        = string
  default     = ""
}

variable "oidc_secret" {
  description = "OIDC client secret registered with Pocket ID"
  type        = string
  sensitive   = true
  default     = ""
}
