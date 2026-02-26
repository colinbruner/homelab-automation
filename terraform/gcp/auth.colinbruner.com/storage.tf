# ---------------------------------------------------------------------------
# GCS backup bucket
#
# Location "US" (multi-region) qualifies for the GCP free tier:
#   5 GB-months Standard Storage in US multi-regions per month.
# Pocket ID's SQLite DB is tiny so this should stay within free limits.
#
# Objects expire after 30 days via lifecycle rule — no manual cleanup needed.
# Public access is enforced-off; the VM SA has write-only access.
# ---------------------------------------------------------------------------
resource "google_storage_bucket" "backups" {
  project                     = var.project_id
  name                        = "${var.project_id}-pocket-id-backups"
  location                    = "US"
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  # Protect backups from accidental terraform destroy
  force_destroy = false

  lifecycle_rule {
    condition {
      age = 30 # days
    }
    action {
      type = "Delete"
    }
  }
}

# ---------------------------------------------------------------------------
# IAM — VM SA can write objects but not read, list, or delete them.
# Lifecycle-based deletion is handled by GCS itself, not the SA.
# ---------------------------------------------------------------------------
resource "google_storage_bucket_iam_member" "pocket_id_backup_writer" {
  bucket = google_storage_bucket.backups.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.pocket_id.email}"
}
