###
# WIF binding for the Home GitHub Actions workflow.
# The WIF pool/provider itself is managed in the colinbruner.com workspace.
###

data "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-actions"
}

data "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = "github-actions"
  workload_identity_pool_provider_id = "github-provider"
}

resource "google_service_account_iam_member" "gha_home_wif" {
  service_account_id = google_service_account.gha_home_deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${data.google_iam_workload_identity_pool.github.name}/attribute.repository/colinbruner/Home"
}

output "workload_identity_provider" {
  description = "WIF provider resource name — use as `workload_identity_provider` in google-github-actions/auth"
  value       = data.google_iam_workload_identity_pool_provider.github.name
}

output "service_account_email" {
  description = "SA email to impersonate via WIF"
  value       = google_service_account.gha_appliance_tracker.email
}
