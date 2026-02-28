terraform {
  backend "gcs" {
    bucket = "bruner-infra"
    prefix = "aws/email-notifications"
  }
}
