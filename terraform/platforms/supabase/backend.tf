terraform {
  backend "gcs" {
    bucket = "bruner-infra"
    prefix = "platforms/supabase"
  }
}
