output "service_account" {
  sensitive = true
  value = {
    email = google_service_account.this.email
    key   = base64decode(google_service_account_key.this.private_key)
  }
}
