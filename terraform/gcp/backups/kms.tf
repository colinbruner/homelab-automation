data "google_project" "this" {}

# Required via docs: https://cloud.google.com/storage/docs/encryption/using-customer-managed-keys
resource "google_project_iam_binding" "kms_crypto_key_encrypter_decrypter" {
  project = data.google_project.this.project_id
  role    = "roles/cloudkms.cryptoKeyEncrypterDecrypter"

  members = [
    "serviceAccount:service-${data.google_project.this.number}@gs-project-accounts.iam.gserviceaccount.com"
  ]
}

resource "google_kms_key_ring" "keyring" {
  name     = "backups-keyring"
  location = "us-central1"
}

resource "google_kms_crypto_key" "backups" {
  name            = "backups-key"
  key_ring        = google_kms_key_ring.keyring.id
  rotation_period = "63113904s" # 2 years

  lifecycle {
    prevent_destroy = true
  }
}


