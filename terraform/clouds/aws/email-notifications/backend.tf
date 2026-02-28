terraform {
  backend "gcs" {
    bucket = "bruner-infra"
    prefix = "clouds/aws/email-notifications"
  }
}
