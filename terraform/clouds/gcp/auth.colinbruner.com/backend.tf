terraform {
  backend "gcs" {
    bucket = "bruner-infra"
    prefix = "clouds/gcp/auth.colinbruner.com/"
  }
}
