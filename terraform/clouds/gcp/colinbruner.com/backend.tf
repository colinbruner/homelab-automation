terraform {
  backend "gcs" {
    bucket = "bruner-infra"
    prefix = "clouds/gcp/colinbruner.com/"
  }
}
