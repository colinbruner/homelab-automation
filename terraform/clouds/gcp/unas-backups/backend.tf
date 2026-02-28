terraform {
  backend "gcs" {
    bucket = "bruner-infra"
    prefix = "unas-backups/"
  }
}
