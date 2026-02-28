terraform {
  backend "gcs" {
    bucket = "bruner-infra"
    prefix = "clouds/cloudflare/zero-trust/"
  }
}
