###
# Service account used by the colinbruner/appliance-tracker GitHub Actions
# workflow to deploy the appliances.bruner.family static site to GCS.
###

data "google_project" "project" {}

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

# Allow the GitHub Actions WIF pool to impersonate this service account.
# The WIF pool is defined in colinbruner.com/auth.tf (pool: github-actions).
resource "google_service_account_iam_member" "gha_appliance_tracker_wif" {
  service_account_id = google_service_account.gha_appliance_tracker.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/projects/${data.google_project.project.number}/locations/global/workloadIdentityPools/github-actions/attribute.repository/colinbruner/appliance-tracker"
}
