terraform {
  backend "gcs" {
    bucket = "bruner-infra"
    prefix = "colinbruner.com/"
  }
}
