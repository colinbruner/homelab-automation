terraform {
  backend "gcs" {
    bucket = "bruner-infra"
    prefix = "clouds/cloudflare/zone/colinbruner.com/"
  }
}
