data "google_project" "this" {}

# Add encryptorDecrypter role to GCS Storage SA
resource "google_project_iam_binding" "kms_crypto_key_encrypter_decrypter" {
  project = data.google_project.this.project_id
  role    = "roles/cloudkms.cryptoKeyEncrypterDecrypter"

  members = [
    "serviceAccount:service-${data.google_project.this.number}@gs-project-accounts.iam.gserviceaccount.com"
  ]
}

# Add encryptorDecrypter role to backup SA
resource "google_project_iam_member" "kms" {
  for_each = module.backups

  project = data.google_project.this.project_id
  role    = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member  = "serviceAccount:${each.value.service_account.email}"
}
