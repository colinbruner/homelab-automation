
data "terraform_remote_state" "gcp_iam" {
  backend = "gcs"
  config = {
    bucket = "bruner-infra"
    prefix = "clouds/gcp/iam/"
  }
}
