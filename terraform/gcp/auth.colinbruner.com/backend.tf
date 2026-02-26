terraform {
  backend "gcs" {
    bucket = "bruner-infra"
    prefix = "backups/"
  }
}
