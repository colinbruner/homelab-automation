terraform {
  backend "gcs" {
    bucket = "bruner-infra"
    prefix = "auth.colinbruner.com/"
  }
}
