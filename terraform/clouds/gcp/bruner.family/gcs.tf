###
# appliances.bruner.family
###

resource "google_storage_bucket" "appliances" {
  name     = "appliances.bruner.family"
  location = "US-CENTRAL1"

  uniform_bucket_level_access = true

  website {
    main_page_suffix = "index.html"
    not_found_page   = "index.html"
  }
}

# Allow public read access for static site hosting
resource "google_storage_bucket_iam_member" "appliances_public_read" {
  bucket = google_storage_bucket.appliances.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}
