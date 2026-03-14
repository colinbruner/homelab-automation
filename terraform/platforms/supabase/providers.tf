# Supabase access token: set via SUPABASE_ACCESS_TOKEN env var
# or provide via -var="access_token=..."
provider "supabase" {
  access_token = var.access_token
}
