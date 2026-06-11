###
# Service account GitHub Actions impersonates to run Terraform plan/apply
# for this repo (ADR 0001). The WIF pool/provider itself is managed in the
# colinbruner.com workspace.
###

# Required by every resource below: Resource Manager for project IAM
# bindings, IAM API for service accounts and SA IAM policies.
resource "google_project_service" "cloudresourcemanager" {
  project            = var.project_id
  service            = "cloudresourcemanager.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "iam" {
  project            = var.project_id
  service            = "iam.googleapis.com"
  disable_on_destroy = false
}

data "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = "github-actions"
}

data "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = "github-actions"
  workload_identity_pool_provider_id = "github-provider"
}

resource "google_service_account" "gha_terraform" {
  project      = var.project_id
  account_id   = "svc-gha-terraform"
  display_name = "GitHub Actions Terraform Runner"

  depends_on = [
    google_project_service.cloudresourcemanager,
    google_project_service.iam,
  ]
}

resource "google_service_account_iam_member" "gha_terraform_wif" {
  service_account_id = google_service_account.gha_terraform.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${data.google_iam_workload_identity_pool.github.name}/attribute.repository/colinbruner/homelab-automation"
}

# Editor covers most resource management; the IAM admin roles cover what
# editor lacks (project bindings, SA IAM policies/keys, WIF pools). If an
# apply fails on a missing permission, extend this list.
resource "google_project_iam_member" "gha_terraform" {
  for_each = toset([
    "roles/editor",
    "roles/resourcemanager.projectIamAdmin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountKeyAdmin",
    "roles/iam.workloadIdentityPoolAdmin",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gha_terraform.email}"
}

# State bucket access — every workspace needs this regardless of target cloud.
resource "google_storage_bucket_iam_member" "gha_terraform_state" {
  bucket = "bruner-infra"
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.gha_terraform.email}"
}

output "gha_terraform_workload_identity_provider" {
  description = "Set as GCP_WORKLOAD_IDENTITY_PROVIDER GitHub Actions variable"
  value       = data.google_iam_workload_identity_pool_provider.github.name
}

output "gha_terraform_service_account_email" {
  description = "Set as GCP_TERRAFORM_SERVICE_ACCOUNT GitHub Actions variable"
  value       = google_service_account.gha_terraform.email
}
