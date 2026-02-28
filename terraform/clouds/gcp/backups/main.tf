resource "random_id" "this" {
  byte_length = 4
}

###
# Bucket
###
resource "google_storage_bucket" "backups" {
  name     = "bruner-backups"
  location = "US-CENTRAL1"

  public_access_prevention    = "enforced"
  uniform_bucket_level_access = true

  autoclass {
    enabled                = true
    terminal_storage_class = "ARCHIVE"
  }

  encryption {
    default_kms_key_name = google_kms_crypto_key.backups.id
  }

  # Delete object versions more than 2 after 30 days
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      num_newer_versions = 2
      with_state         = "ARCHIVED"
    }
  }
  # Delete noncurrent object versions after 30 days
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      days_since_noncurrent_time = 30
    }
  }


  versioning {
    enabled = true
  }
}

###
# SA
###
resource "google_service_account" "backups" {
  account_id   = "backups-${random_id.this.hex}"
  display_name = "Backups Service Account"
}

resource "google_storage_bucket_iam_member" "backups" {
  bucket = google_storage_bucket.backups.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.backups.email}"
}

resource "google_service_account_key" "backups" {
  service_account_id = google_service_account.backups.name
}

output "backups_service_account" {
  sensitive = true
  value = {
    email = google_service_account.backups.email
    key   = base64decode(google_service_account_key.backups.private_key)
  }
}
