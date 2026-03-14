###
# Service account used by the colinbruner/appliance-tracker GitHub Actions
# workflow to deploy the appliances.bruner.family static site to GCS.
###

resource "google_service_account" "gha_appliance_tracker" {
  project      = var.project_id
  account_id   = "svc-gha-appliance-tracker"
  display_name = "GitHub Actions — appliance-tracker deployer"
}

resource "google_storage_bucket_iam_member" "gha_appliance_tracker_object_admin" {
  bucket = google_storage_bucket.appliances.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.gha_appliance_tracker.email}"
}

# storage.buckets.get is required by `gcloud storage rsync` but is not included
# in roles/storage.objectAdmin — legacyBucketReader provides that permission.
resource "google_storage_bucket_iam_member" "gha_appliance_tracker_bucket_reader" {
  bucket = google_storage_bucket.appliances.name
  role   = "roles/storage.legacyBucketReader"
  member = "serviceAccount:${google_service_account.gha_appliance_tracker.email}"
}
