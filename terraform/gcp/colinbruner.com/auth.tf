###
# Create a OIDC application for GitHub Actions to authenticate with for
# access to GCP resources. Used within colinbruner.com CI
###

# https://github.com/terraform-google-modules/terraform-google-github-actions-runners/tree/master/modules/gh-oidc
module "gh_oidc" {
  source = "terraform-google-modules/github-actions-runners/google//modules/gh-oidc"

  project_id            = var.project_id
  pool_id               = "github-actions"
  provider_id           = "github-provider"
  provider_display_name = "github-provider"

  attribute_condition = "assertion.repository_owner == \"colinbruner\""
  attribute_mapping = {
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.actor"            = "assertion.actor"
    "attribute.aud"              = "assertion.aud"
    "attribute.repository"       = "assertion.repository"
    "google.subject"             = "assertion.sub"
  }

  # NOTE: Can allow for multiple mappings in the event multiple 
  # repos need access to GCP resources
  sa_mapping = {
    "svc-gha-runners" = {
      sa_name   = "projects/${var.project_id}/serviceAccounts/svc-gha-runner@${var.project_id}.iam.gserviceaccount.com"
      attribute = "attribute.repository/colinbruner/colinbruner.com"
    }
  }
}

# Used in configuring GitHub repo secrets for consumption by Actions
output "gh_oidc" {
  value = module.gh_oidc
}
