terraform {
  backend "gcs" {
    bucket = "bruner-infra"
    prefix = "apps/grafana/"
  }
}
