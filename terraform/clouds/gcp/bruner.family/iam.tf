###
# Service account used by the colinbruner/Home GitHub Actions
# workflow to deploy the home.bruner.family static site to GCS.
###

resource "google_service_account" "gha_home_deployer" {
  project      = var.project_id
  account_id   = "svc-gha-home-deployer"
  display_name = "GitHub Actions — home deployer"
}

resource "google_storage_bucket_iam_member" "gha_home_object_admin" {
  bucket = google_storage_bucket.home.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.gha_home_deployer.email}"
}

# storage.buckets.get is required by `gcloud storage rsync` but is not included
# in roles/storage.objectAdmin — legacyBucketReader provides that permission.
resource "google_storage_bucket_iam_member" "gha_home_bucket_reader" {
  bucket = google_storage_bucket.home.name
  role   = "roles/storage.legacyBucketReader"
  member = "serviceAccount:${google_service_account.gha_home_deployer.email}"
}
