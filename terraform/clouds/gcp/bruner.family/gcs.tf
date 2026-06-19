###
# home.bruner.family
###

resource "google_storage_bucket" "home" {
  name     = "home.bruner.family"
  location = "US-CENTRAL1"

  uniform_bucket_level_access = true

  website {
    main_page_suffix = "index.html"
    not_found_page   = "index.html"
  }
}

# Allow public read access for static site hosting
resource "google_storage_bucket_iam_member" "home_public_read" {
  bucket = google_storage_bucket.home.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

###
# hearth supabase backups
###

resource "random_id" "hearth_backup" {
  byte_length = 2
}

resource "google_storage_bucket" "hearth_backup" {
  name     = "hearth-supabase-backup-${random_id.hearth_backup.hex}"
  location = "US"

  public_access_prevention    = "enforced"
  uniform_bucket_level_access = true

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 7
    }
  }
}

resource "google_storage_bucket_iam_member" "hearth_backup_object_admin" {
  bucket = google_storage_bucket.hearth_backup.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.gha_home_deployer.email}"
}
