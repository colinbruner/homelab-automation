###
# SA
###
resource "google_service_account" "this" {
  account_id   = "${var.name}-backups-${random_id.this.hex}"
  display_name = "UNAS Volume ${var.name} Service Account for Backups"
}

resource "google_storage_bucket_iam_member" "this" {
  bucket = google_storage_bucket.this.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.this.email}"
}

resource "google_service_account_key" "this" {
  service_account_id = google_service_account.this.name
}
