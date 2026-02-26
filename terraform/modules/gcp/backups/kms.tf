# Create kingring, key, and apply IAM binding to SA
resource "google_kms_key_ring" "this" {
  name     = "${var.name}-backups-keyring"
  location = "us-central1"
}

resource "google_kms_crypto_key" "this" {
  name            = "${var.name}-backups-key"
  key_ring        = google_kms_key_ring.this.id
  rotation_period = "63113904s" # 2 years

  lifecycle {
    prevent_destroy = true
  }
}

# Required via docs: https://cloud.google.com/storage/docs/encryption/using-customer-managed-keys
resource "google_kms_crypto_key_iam_binding" "this" {
  crypto_key_id = google_kms_crypto_key.this.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"

  members = [
    google_service_account.this.member
  ]
}

