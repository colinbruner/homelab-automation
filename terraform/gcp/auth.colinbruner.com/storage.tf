resource "random_id" "bucket_suffix" {
  byte_length = 2
}

# ---------------------------------------------------------------------------
# GCS backup bucket
#
# Location "US" (multi-region) qualifies for the GCP free tier:
#   5 GB-months Standard Storage in US multi-regions per month.
# Pocket ID's SQLite DB is tiny so this should stay within free limits.
#
# Versioning is enabled. The backup script writes to a fixed object name
# (pocket-id.db.enc) so each nightly run creates a new GCS version of that
# object. The lifecycle rule retains the 7 most recent versions and deletes
# older ones — no unbounded accumulation, no age-based expiry.
#
# num_newer_versions = 6 on ARCHIVED objects means: delete a non-current
# version once 6 newer versions exist, giving 6 non-current + 1 live = 7 total.
#
# Public access is enforced-off; the VM SA has write-only access.
# ---------------------------------------------------------------------------
resource "google_storage_bucket" "backups" {
  project                     = var.project_id
  name                        = "backup-auth-colinbruner-com-${random_id.bucket_suffix.hex}"
  location                    = "US"
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  # Protect backups from accidental terraform destroy
  force_destroy = false

  versioning {
    enabled = true
  }

  # Keep the 7 most recent versions (6 non-current + 1 live).
  # Older non-current versions are deleted automatically.
  lifecycle_rule {
    condition {
      num_newer_versions = 6
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }
}

# ---------------------------------------------------------------------------
# IAM — VM SA needs both create and get on bucket objects.
#
# objectCreator alone (storage.objects.create) is insufficient: gcloud storage cp
# also requires storage.objects.get to handle checksums and resumable upload state
# against the existing versioned object at the destination path.
#
# objectViewer adds storage.objects.get + storage.objects.list.
# Neither role grants delete — lifecycle-based deletion is handled by GCS itself.
# ---------------------------------------------------------------------------
resource "google_storage_bucket_iam_member" "auth_colinbruner_backup_writer" {
  bucket = google_storage_bucket.backups.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.this.email}"
}

resource "google_storage_bucket_iam_member" "auth_colinbruner_backup_viewer" {
  bucket = google_storage_bucket.backups.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.this.email}"
}
